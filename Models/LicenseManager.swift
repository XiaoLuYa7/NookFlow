import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum NookFlowLicenseError: LocalizedError {
    case configurationMissing
    case invalidCode
    case alreadyActivated
    case revoked
    case invalidResponse
    case deviceKeyUnavailable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            "授权服务尚未配置，请联系 NookFlow 支持。"
        case .invalidCode:
            "激活码无效，请检查后重试。"
        case .alreadyActivated:
            "这个激活码已绑定其他设备，请先在旧设备停用。"
        case .revoked:
            "许可证已被停用或撤销。"
        case .invalidResponse:
            "授权服务返回了无法验证的数据。"
        case .deviceKeyUnavailable:
            "无法创建本机设备密钥，请稍后重试。"
        case let .server(message):
            message
        }
    }
}

@MainActor
final class LicenseManager: ObservableObject {
    private static let defaultAPIBaseURLString = "https://nookflow.luckysoft.cn/api"
    private static let defaultPurchaseURLString = "https://nookflow.luckysoft.cn/#pricing"
    private static let defaultPublicKeyBase64 = "BN0TaJS2f6F19ptHSYVW4JpL9AqfPa/gszT5T9a9ZxBf5dxTbOjWSbHAmxn393Ia/GILUVl7ETWcsZ1++ky/Qbw="

    static let shared = LicenseManager()

    enum State: Equatable {
        case free
        case activating
        case pro
        case error(String)
    }

    @Published private(set) var state: State = .free
    @Published private(set) var license: LicensePayload?
    @Published private(set) var needsDeviceKeyAuthorization = false

    var isProUnlocked: Bool { state == .pro }
    var canResumeStoredLicense: Bool {
        needsDeviceKeyAuthorization && defaults.string(forKey: tokenKey) != nil
    }

    static var purchaseURL: URL? {
        let configuredValue = Bundle.main.object(forInfoDictionaryKey: "NookFlowPurchaseURL") as? String
        let rawValue = configuredValue.flatMap { $0.isEmpty ? nil : $0 } ?? defaultPurchaseURLString
        return URL(string: rawValue)
    }

    static func formattedActivationCode(_ value: String) -> String {
        var normalized = value.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if normalized.hasPrefix("NF") { normalized.removeFirst(2) }
        normalized = String(normalized.prefix(15))
        let groups = stride(from: 0, to: normalized.count, by: 5).map { index -> String in
            let start = normalized.index(normalized.startIndex, offsetBy: index)
            let end = normalized.index(
                start,
                offsetBy: min(5, normalized.distance(from: start, to: normalized.endIndex))
            )
            return String(normalized[start..<end])
        }
        return groups.isEmpty ? "" : "NF-" + groups.joined(separator: "-")
    }

    private let session: URLSession
    private let defaults: UserDefaults
    private let deviceKeyStore = DeviceKeyStore()
    private let tokenKey = "license.signedToken"

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        restoreStoredLicense()
    }

    func activate(code: String) async {
        let normalizedCode = Self.normalize(code)
        guard !normalizedCode.isEmpty else {
            state = .error(NookFlowLicenseError.invalidCode.localizedDescription)
            return
        }

        state = .activating
        do {
            let request = try signedRequest(
                action: "activate",
                subject: normalizedCode,
                allowKeychainInteraction: true
            )
            let response: LicenseResponse = try await post(
                path: "activate",
                body: ActivationRequest(
                    code: normalizedCode,
                    devicePublicKey: request.publicKey,
                    timestamp: request.timestamp,
                    proof: request.proof
                )
            )
            try accept(signedLicense: response.signedLicense)
        } catch {
            guard !Task.isCancelled else {
                state = license == nil ? .free : .pro
                return
            }
            state = .error(Self.userFacingMessage(for: error))
        }
    }

    func refreshIfNeeded(force: Bool = false) async {
        await validateStoredLicense(force: force, allowKeychainInteraction: false)
    }

    /// Runs only after an explicit user action. Automatic launch validation must
    /// never present a Keychain authorization dialog.
    func resumeStoredLicense() async {
        await validateStoredLicense(force: true, allowKeychainInteraction: true)
    }

    private func validateStoredLicense(
        force: Bool,
        allowKeychainInteraction: Bool
    ) async {
        guard let signedLicense = defaults.string(forKey: tokenKey) else { return }
        let payload: LicensePayload
        do {
            payload = try Self.verify(signedLicense: signedLicense)
        } catch {
            license = nil
            state = .error("本地许可证数据异常，但已为你保留。请重新输入激活码或联系支持。")
            return
        }

        if allowKeychainInteraction {
            state = .activating
        }

        let deviceID: String
        do {
            deviceID = try currentDeviceID(allowInteraction: allowKeychainInteraction)
            needsDeviceKeyAuthorization = false
        } catch let error as DeviceKeyStoreError where error.requiresInteraction {
            needsDeviceKeyAuthorization = true
            restoreOfflineAccess(
                payload,
                expiredMessage: "需要你主动确认一次钥匙串访问，之后会自动恢复 Pro，无需重新输入激活码。"
            )
            return
        } catch {
            needsDeviceKeyAuthorization = false
            restoreOfflineAccess(
                payload,
                expiredMessage: "暂时无法读取本机设备密钥。许可证已保留，请稍后重试。"
            )
            return
        }

        guard payload.deviceID == deviceID else {
            license = nil
            state = .error("本机设备密钥与已保存许可证不一致。许可证已保留，请勿重复激活并联系支持。")
            return
        }
        guard force || Self.currentTimeMilliseconds >= payload.checkAfter else { return }

        do {
            let request = try signedRequest(
                action: "validate",
                subject: signedLicense,
                allowKeychainInteraction: allowKeychainInteraction
            )
            let response: LicenseResponse = try await post(
                path: "validate",
                body: ValidationRequest(
                    signedLicense: signedLicense,
                    devicePublicKey: request.publicKey,
                    timestamp: request.timestamp,
                    proof: request.proof
                )
            )
            try accept(signedLicense: response.signedLicense)
        } catch NookFlowLicenseError.revoked {
            license = nil
            state = .error(NookFlowLicenseError.revoked.localizedDescription)
        } catch NookFlowLicenseError.invalidResponse {
            license = nil
            state = .error(NookFlowLicenseError.invalidResponse.localizedDescription)
        } catch {
            guard !Task.isCancelled else { return }
            restoreOfflineAccess(payload, expiredMessage: Self.userFacingMessage(for: error))
        }
    }

    func deactivate() async {
        guard let signedLicense = defaults.string(forKey: tokenKey) else {
            clearLicense()
            return
        }

        do {
            let request = try signedRequest(
                action: "deactivate",
                subject: signedLicense,
                allowKeychainInteraction: true
            )
            let _: DeactivationResponse = try await post(
                path: "deactivate",
                body: ValidationRequest(
                    signedLicense: signedLicense,
                    devicePublicKey: request.publicKey,
                    timestamp: request.timestamp,
                    proof: request.proof
                )
            )
            clearLicense()
        } catch {
            state = .error(Self.userFacingMessage(for: error))
        }
    }

    func resetError() {
        guard defaults.string(forKey: tokenKey) == nil else { return }
        if case .error = state {
            state = (license?.offlineUntil ?? 0) > Self.currentTimeMilliseconds ? .pro : .free
        }
    }

    private func restoreStoredLicense() {
        guard let token = defaults.string(forKey: tokenKey) else {
            license = nil
            state = .free
            return
        }
        guard let payload = try? Self.verify(signedLicense: token) else {
            license = nil
            state = .error("本地许可证数据异常，但已为你保留。请重新输入激活码或联系支持。")
            return
        }

        do {
            let deviceID = try currentDeviceID(allowInteraction: false)
            guard payload.deviceID == deviceID else {
                license = nil
                state = .error("本机设备密钥与已保存许可证不一致。许可证已保留，请联系支持。")
                return
            }
        } catch let error as DeviceKeyStoreError where error.requiresInteraction {
            needsDeviceKeyAuthorization = true
            restoreOfflineAccess(
                payload,
                expiredMessage: "需要你主动确认一次钥匙串访问，之后会自动恢复 Pro，无需重新输入激活码。"
            )
            return
        } catch {
            restoreOfflineAccess(
                payload,
                expiredMessage: "暂时无法读取本机设备密钥。许可证已保留，请稍后重试。"
            )
            return
        }

        if payload.offlineUntil > Self.currentTimeMilliseconds {
            license = payload
            state = .pro
        } else {
            // Keep the signed token so startup validation can restore Pro as soon as
            // the network is available. Deleting it here would force a paid user to
            // enter the activation code again after a long offline period or update.
            license = nil
            state = .error("需要联网验证许可证，连接网络后会自动重试。")
        }
    }

    private func accept(signedLicense: String) throws {
        let payload = try Self.verify(signedLicense: signedLicense)
        guard payload.deviceID == (try currentDeviceID(allowInteraction: false)) else {
            throw NookFlowLicenseError.invalidResponse
        }
        defaults.set(signedLicense, forKey: tokenKey)
        needsDeviceKeyAuthorization = false
        license = payload
        state = .pro
    }

    private func clearLicense() {
        defaults.removeObject(forKey: tokenKey)
        needsDeviceKeyAuthorization = false
        license = nil
        state = .free
    }

    private func currentDeviceID(allowInteraction: Bool) throws -> String {
        let key = try deviceKeyStore.loadOrCreate(allowInteraction: allowInteraction)
        return SHA256.hash(data: key.publicKey.x963Representation).hexString
    }

    private func signedRequest(
        action: String,
        subject: String,
        allowKeychainInteraction: Bool
    ) throws -> SignedDeviceRequest {
        let key: P256.Signing.PrivateKey
        do {
            key = try deviceKeyStore.loadOrCreate(allowInteraction: allowKeychainInteraction)
        } catch {
            throw NookFlowLicenseError.deviceKeyUnavailable
        }

        let timestamp = Int64(Date.now.timeIntervalSince1970 * 1000)
        let message = "\(action)\n\(timestamp)\n\(subject)"
        let signature = try key.signature(for: Data(message.utf8))
        return SignedDeviceRequest(
            publicKey: key.publicKey.x963Representation.base64URLEncodedString(),
            timestamp: timestamp,
            proof: signature.rawRepresentation.base64URLEncodedString()
        )
    }

    private func post<Response: Decodable, Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        guard let baseURL = Self.apiBaseURL else {
            throw NookFlowLicenseError.configurationMissing
        }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        request.timeoutInterval = 15
        let (data, response) = try await dataWithOneTransientRetry(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NookFlowLicenseError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? JSONDecoder().decode(ServerErrorResponse.self, from: data)
            throw Self.mapServerError(errorResponse?.error, statusCode: httpResponse.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw NookFlowLicenseError.invalidResponse
        }
        return decoded
    }

    private func dataWithOneTransientRetry(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            guard Self.isRetryableTransportError(error), !Task.isCancelled else {
                throw error
            }
            try await Task.sleep(nanoseconds: 350_000_000)
            return try await session.data(for: request)
        }
    }

    private func restoreOfflineAccess(_ payload: LicensePayload, expiredMessage: String) {
        if payload.offlineUntil > Self.currentTimeMilliseconds {
            license = payload
            state = .pro
        } else {
            license = nil
            state = .error(expiredMessage)
        }
    }

    private static func verify(signedLicense: String) throws -> LicensePayload {
        let components = signedLicense.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2,
              let payloadData = Data(base64URL: String(components[0])),
              let signatureData = Data(base64URL: String(components[1])),
              let publicKeyData = configuredPublicKeyData,
              let publicKey = try? P256.Signing.PublicKey(x963Representation: publicKeyData),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData),
              publicKey.isValidSignature(signature, for: payloadData),
              let payload = try? JSONDecoder().decode(LicensePayload.self, from: payloadData)
        else {
            throw NookFlowLicenseError.invalidResponse
        }
        return payload
    }

    private static var apiBaseURL: URL? {
        let configuredValue = Bundle.main.object(forInfoDictionaryKey: "NookFlowLicenseAPIBaseURL") as? String
        let rawValue = configuredValue.flatMap { $0.isEmpty ? nil : $0 } ?? defaultAPIBaseURLString
        return URL(string: rawValue)
    }

    private static var configuredPublicKeyData: Data? {
        let configuredValue = Bundle.main.object(forInfoDictionaryKey: "NookFlowLicensePublicKey") as? String
        let encoded = configuredValue.flatMap { $0.isEmpty ? nil : $0 } ?? defaultPublicKeyBase64
        return Data(base64Encoded: encoded)
    }

    private static func mapServerError(_ error: String?, statusCode: Int) -> Error {
        switch error {
        case "invalid_code": NookFlowLicenseError.invalidCode
        case "already_activated": NookFlowLicenseError.alreadyActivated
        case "license_revoked", "license_expired": NookFlowLicenseError.revoked
        case "transfer_limit_reached": NookFlowLicenseError.server("该激活码已达到设备转移次数上限，请联系 NookFlow 支持。")
        case "server_error": NookFlowLicenseError.server("授权服务暂时不可用，请稍后重试。")
        default: NookFlowLicenseError.server("激活失败（\(statusCode)），请稍后重试。")
        }
    }

    private static func isRetryableTransportError(_ error: Error) -> Bool {
        guard let code = urlErrorCode(from: error) else { return false }
        return [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
            .secureConnectionFailed,
        ].contains(code)
    }

    private static func userFacingMessage(for error: Error) -> String {
        guard let code = urlErrorCode(from: error) else {
            return error.localizedDescription
        }
        switch code {
        case .notConnectedToInternet:
            return "当前没有网络连接。许可证已保留，联网后可继续使用。"
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed:
            return "暂时无法连接授权服务。许可证已保留，请稍后重试。"
        case .secureConnectionFailed:
            return "安全连接暂时失败。许可证已保留，请检查系统时间、VPN 或代理后重试。"
        case .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "无法验证授权服务器证书。许可证已保留，请检查系统时间后重试。"
        case .cancelled:
            return "操作已取消。"
        default:
            return error.localizedDescription
        }
    }

    private static func urlErrorCode(from error: Error) -> URLError.Code? {
        if let urlError = error as? URLError {
            return urlError.code
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return nil }
        return URLError.Code(rawValue: nsError.code)
    }

    private static func normalize(_ code: String) -> String {
        code.uppercased().filter { $0.isASCII && $0.isLetter || $0.isNumber }
    }

    private static var currentTimeMilliseconds: Int64 {
        Int64(Date.now.timeIntervalSince1970 * 1000)
    }
}

struct LicensePayload: Codable, Equatable {
    let licenseID: String
    let product: String
    let deviceID: String
    let issuedAt: Int64
    let checkAfter: Int64
    let offlineUntil: Int64
}

private struct SignedDeviceRequest {
    let publicKey: String
    let timestamp: Int64
    let proof: String
}

private struct ActivationRequest: Encodable {
    let code: String
    let devicePublicKey: String
    let timestamp: Int64
    let proof: String
}

private struct ValidationRequest: Encodable {
    let signedLicense: String
    let devicePublicKey: String
    let timestamp: Int64
    let proof: String
}

private struct LicenseResponse: Decodable {
    let signedLicense: String
}

private struct DeactivationResponse: Decodable {
    let deactivated: Bool
}

private struct ServerErrorResponse: Decodable {
    let error: String
}

private enum DeviceKeyStoreError: Error {
    case interactionRequired
    case invalidKeyData
    case keychain(OSStatus)

    var requiresInteraction: Bool {
        if case .interactionRequired = self { return true }
        return false
    }
}

/// Keeps the device signing key alive for the process lifetime. A Keychain item
/// created by an older code-signing identity may require one user approval to
/// read; caching prevents a single activation/validation flow from presenting
/// that system authorization dialog more than once.
private final class DeviceKeyStore {
    private let service = "com.nookflow.license"
    private let account = "device-signing-key"
    private var cachedKey: P256.Signing.PrivateKey?

    func loadOrCreate(allowInteraction: Bool) throws -> P256.Signing.PrivateKey {
        if let cachedKey {
            return cachedKey
        }

        if let stored = try load(allowInteraction: allowInteraction) {
            guard let key = try? P256.Signing.PrivateKey(rawRepresentation: stored) else {
                throw DeviceKeyStoreError.invalidKeyData
            }
            cachedKey = key
            return key
        }

        let key = P256.Signing.PrivateKey()
        try saveNew(key.rawRepresentation)
        cachedKey = key
        return key
    }

    private func load(allowInteraction: Bool) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = !allowInteraction
        query[kSecUseAuthenticationContext as String] = authenticationContext

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw DeviceKeyStoreError.invalidKeyData
            }
            return data
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw DeviceKeyStoreError.interactionRequired
        default:
            throw DeviceKeyStoreError.keychain(status)
        }
    }

    private func saveNew(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            // Never delete or overwrite an existing device identity. A duplicate
            // or any other Keychain failure must be surfaced for safe recovery.
            throw DeviceKeyStoreError.keychain(status)
        }
    }
}

private extension Data {
    init?(base64URL: String) {
        var value = base64URL.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value.append(String(repeating: "=", count: (4 - value.count % 4) % 4))
        self.init(base64Encoded: value)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

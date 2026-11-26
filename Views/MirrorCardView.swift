import AppKit
@preconcurrency import AVFoundation
import SwiftUI

private final class MirrorCaptureSession: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(
        label: "com.personal.DynamicNook.mirror-camera",
        qos: .userInitiated
    )
    private let frameQueue = DispatchQueue(
        label: "com.personal.DynamicNook.mirror-camera.first-frame",
        qos: .userInteractive
    )
    private let requestLock = NSLock()
    private let firstFrameLock = NSLock()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false
    private var latestRequestID: UInt64 = 0
    private var firstFrameRequestID: UInt64?
    private var firstFrameHandler: (@Sendable () -> Void)?

    func start(
        onFirstFrame: @escaping @Sendable () -> Void,
        completion: @escaping @Sendable (Result<Void, MirrorCameraError>) -> Void
    ) {
        let requestID = registerRequest()
        queue.async { [self] in
            guard isCurrentRequest(requestID) else { return }
            do {
                try configureIfNeeded()
                guard isCurrentRequest(requestID) else { return }
                armFirstFrameObservation(
                    requestID: requestID,
                    handler: onFirstFrame
                )
                if !session.isRunning {
                    session.startRunning()
                }
                guard isCurrentRequest(requestID) else {
                    cancelFirstFrameObservation(requestID: requestID)
                    if session.isRunning {
                        session.stopRunning()
                    }
                    return
                }
                completion(.success(()))
            } catch let error as MirrorCameraError {
                cancelFirstFrameObservation(requestID: requestID)
                guard isCurrentRequest(requestID) else { return }
                completion(.failure(error))
            } catch {
                cancelFirstFrameObservation(requestID: requestID)
                guard isCurrentRequest(requestID) else { return }
                completion(.failure(.failed))
            }
        }
    }

    func stop() {
        let requestID = registerRequest()
        queue.async { [self] in
            guard isCurrentRequest(requestID) else { return }
            cancelFirstFrameObservation()
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// Camera start/stop calls can overlap while the user taps quickly. The
    /// serial queue preserves execution order, while this request identity also
    /// prevents an obsolete stop or completion from overriding the latest tap.
    private func registerRequest() -> UInt64 {
        requestLock.lock()
        defer { requestLock.unlock() }
        latestRequestID &+= 1
        return latestRequestID
    }

    private func isCurrentRequest(_ requestID: UInt64) -> Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return latestRequestID == requestID
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw MirrorCameraError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }
        guard session.canAddInput(input) else {
            throw MirrorCameraError.cannotAddInput
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(videoOutput) else {
            throw MirrorCameraError.cannotAddOutput
        }
        session.addOutput(videoOutput)
        isConfigured = true
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === videoOutput else { return }

        firstFrameLock.lock()
        let requestID = firstFrameRequestID
        let handler = firstFrameHandler
        firstFrameHandler = nil
        firstFrameLock.unlock()

        guard let requestID, let handler else { return }
        handler()

        queue.async { [weak self] in
            self?.finishFirstFrameObservation(requestID: requestID)
        }
    }

    private func armFirstFrameObservation(
        requestID: UInt64,
        handler: @escaping @Sendable () -> Void
    ) {
        firstFrameLock.lock()
        firstFrameRequestID = requestID
        firstFrameHandler = handler
        firstFrameLock.unlock()
        videoOutput.connection(with: .video)?.isEnabled = true
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
    }

    private func finishFirstFrameObservation(requestID: UInt64) {
        firstFrameLock.lock()
        let shouldFinish = firstFrameRequestID == requestID
            && firstFrameHandler == nil
        if shouldFinish {
            firstFrameRequestID = nil
        }
        firstFrameLock.unlock()

        if shouldFinish {
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
            videoOutput.connection(with: .video)?.isEnabled = false
        }
    }

    private func cancelFirstFrameObservation(requestID: UInt64? = nil) {
        firstFrameLock.lock()
        let shouldCancel = requestID == nil || firstFrameRequestID == requestID
        if shouldCancel {
            firstFrameRequestID = nil
            firstFrameHandler = nil
        }
        firstFrameLock.unlock()

        if shouldCancel {
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
            videoOutput.connection(with: .video)?.isEnabled = false
        }
    }
}

@MainActor
final class MirrorCameraController: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case starting
        case running
        case denied
        case unavailable
        case failed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var previewGeneration: UInt64 = 0
    @Published private(set) var isPreviewReady = false

    var session: AVCaptureSession { captureSession.session }

    private let captureSession = MirrorCaptureSession()
    private var wantsRunning = false
    private var operationGeneration: UInt64 = 0
    private var workspaceObservers: [NSObjectProtocol] = []

    deinit {
        let observers = workspaceObservers
        NSWorkspace.shared.notificationCenter.removeObservers(observers)
        captureSession.stop()
    }

    func start() {
        guard !wantsRunning else { return }
        wantsRunning = true
        let generation = nextOperationGeneration()
        installWorkspaceObserversIfNeeded()

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startAuthorizedSession(generation: generation)
        case .notDetermined:
            state = .requestingPermission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self,
                          self.wantsRunning,
                          self.operationGeneration == generation
                    else { return }
                    if granted {
                        self.startAuthorizedSession(generation: generation)
                    } else {
                        self.state = .denied
                    }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .unavailable
        }
    }

    func stop() {
        guard wantsRunning || state != .idle else { return }
        wantsRunning = false
        _ = nextOperationGeneration()
        removeWorkspaceObservers()
        state = .idle
        isPreviewReady = false

        captureSession.stop()
    }

    func openCameraPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func startAuthorizedSession(generation: UInt64) {
        guard wantsRunning, operationGeneration == generation else { return }
        previewGeneration &+= 1
        isPreviewReady = false
        state = .starting

        captureSession.start(
            onFirstFrame: { [weak self] in
                Task { @MainActor in
                    guard let self,
                          self.wantsRunning,
                          self.operationGeneration == generation
                    else { return }
                    self.isPreviewReady = true
                }
            }
        ) { [weak self] result in
            Task { @MainActor in
                guard let self,
                      self.wantsRunning,
                      self.operationGeneration == generation
                else { return }
                switch result {
                case .success:
                    self.state = .running
                case .failure(.noCamera):
                    self.state = .unavailable
                case .failure:
                    self.state = .failed
                }
            }
        }
    }

    private func stopSessionOffMainThread() {
        captureSession.stop()
    }

    private func installWorkspaceObserversIfNeeded() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        let sleepNames: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification
        ]
        let wakeNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ]

        workspaceObservers = sleepNames.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pauseForSleep() }
            }
        } + wakeNames.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resumeAfterWake() }
            }
        }
    }

    private func removeWorkspaceObservers() {
        guard !workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll(keepingCapacity: false)
    }

    private func pauseForSleep() {
        guard wantsRunning else { return }
        _ = nextOperationGeneration()
        state = .idle
        isPreviewReady = false
        stopSessionOffMainThread()
    }

    private func resumeAfterWake() {
        guard wantsRunning,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        else { return }
        let generation = nextOperationGeneration()
        startAuthorizedSession(generation: generation)
    }

    private func nextOperationGeneration() -> UInt64 {
        operationGeneration &+= 1
        return operationGeneration
    }
}

private enum MirrorCameraError: Error, Sendable {
    case noCamera
    case cannotAddInput
    case cannotAddOutput
    case failed
}

struct MirrorCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var camera = MirrorCameraController()
    @State private var isCameraEnabled = false

    let isActive: Bool

    var body: some View {
        Group {
            if isCameraEnabled {
                cardContent
            } else {
                Button(action: activateCamera) {
                    cardContent
                        .contentShape(Rectangle())
                }
                .buttonStyle(MirrorControlButtonStyle(reduceMotion: reduceMotion))
                .handCursor()
                .disabled(!isActive)
                .help("开启镜子 · 仅实时预览，不会保存")
                .accessibilityLabel("开启镜子")
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                updateCameraActivity()
            } else {
                deactivateCamera()
            }
        }
        .onDisappear { deactivateCamera() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("镜子卡片")
    }

    private var cardContent: some View {
        VStack(spacing: 6) {
            header
            previewSurface
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("镜子")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))

            if isCameraEnabled {
                Circle()
                    .fill(statusColor)
                    .frame(width: 4, height: 4)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 4)

            if isCameraEnabled {
                Button(action: deactivateCamera) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .frame(width: 26, height: 22)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(MirrorControlButtonStyle(reduceMotion: reduceMotion))
                .handCursor()
                .help("关闭镜子")
                .accessibilityLabel("关闭镜子")
                .accessibilityValue(statusText)
            }
        }
        .frame(height: 22)
    }

    private var previewSurface: some View {
        ZStack {
            Color.white.opacity(0.045)

            if isCameraEnabled {
                MirrorCameraPreview(
                    session: camera.session,
                    refreshToken: camera.previewGeneration
                )
                .opacity(camera.state == .running ? 1 : 0)
                .allowsHitTesting(false)
            }

            previewContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .animation(.easeOut(duration: reduceMotion ? 0.08 : 0.16), value: camera.state)
    }

    @ViewBuilder
    private var previewContent: some View {
        if !isCameraEnabled {
            Label("开启镜子", systemImage: "camera")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.82))
        } else if camera.state == .running {
            if !camera.isPreviewReady {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("正在连接画面")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.64))
                }
                .transition(.opacity)
            }
        } else if camera.state == .denied {
            mirrorMessage(
                symbol: "camera.fill.badge.ellipsis",
                title: "需要摄像头权限",
                actionTitle: "前往设置",
                action: camera.openCameraPrivacySettings
            )
        } else if camera.state == .unavailable || camera.state == .failed {
            mirrorMessage(
                symbol: "camera.slash.fill",
                title: "摄像头暂时不可用",
                actionTitle: "重试",
                action: restartCamera
            )
        } else if camera.state == .requestingPermission || camera.state == .starting {
            VStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(camera.state == .requestingPermission ? "等待权限确认" : "正在开启")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
    }

    private func mirrorMessage(
        symbol: String,
        title: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white.opacity(0.76))
            Text(title)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.70))
            Button(actionTitle, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.88))
                .padding(.horizontal, 9)
                .frame(height: 21)
                .background(Color.white.opacity(0.10), in: Capsule(style: .continuous))
        }
    }

    private var statusText: String {
        guard isCameraEnabled else { return "未开启" }
        guard isActive else { return "准备中" }
        switch camera.state {
        case .running: return camera.isPreviewReady ? "使用中" : "正在连接"
        case .requestingPermission: return "等待权限"
        case .starting: return "正在开启"
        case .denied: return "权限受限"
        case .unavailable, .failed: return "暂不可用"
        case .idle: return "未开启"
        }
    }

    private var statusColor: Color {
        guard isCameraEnabled else { return Color.white.opacity(0.38) }
        switch camera.state {
        case .running: return camera.isPreviewReady ? .green : Color.white.opacity(0.55)
        case .denied, .unavailable, .failed: return .orange
        default: return Color.white.opacity(0.55)
        }
    }

    private func activateCamera() {
        isCameraEnabled = true
        updateCameraActivity()
    }

    private func deactivateCamera() {
        isCameraEnabled = false
        camera.stop()
    }

    private func restartCamera() {
        camera.stop()
        isCameraEnabled = true
        updateCameraActivity()
    }

    private func updateCameraActivity() {
        if isActive, isCameraEnabled {
            camera.start()
        } else {
            camera.stop()
        }
    }
}

private struct MirrorControlButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.10),
                value: configuration.isPressed
            )
    }
}

private struct MirrorCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let refreshToken: UInt64

    func makeNSView(context: Context) -> MirrorPreviewNSView {
        MirrorPreviewNSView(
            session: session,
            refreshToken: refreshToken
        )
    }

    func updateNSView(_ nsView: MirrorPreviewNSView, context: Context) {
        nsView.attach(session: session, refreshToken: refreshToken)
    }

    static func dismantleNSView(_ nsView: MirrorPreviewNSView, coordinator: ()) {
        nsView.detach()
    }
}

private final class MirrorPreviewNSView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var attachedRefreshToken: UInt64?

    init(
        session: AVCaptureSession,
        refreshToken: UInt64
    ) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = previewLayer
        previewLayer.videoGravity = .resizeAspectFill
        attach(session: session, refreshToken: refreshToken)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        applyMirroringIfAvailable()
    }

    func attach(session: AVCaptureSession, refreshToken: UInt64) {
        let needsFreshConnection = previewLayer.session !== session
            || attachedRefreshToken != refreshToken
        guard needsFreshConnection else {
            applyMirroringIfAvailable()
            return
        }

        attachedRefreshToken = refreshToken
        previewLayer.session = nil
        previewLayer.session = session
        previewLayer.frame = bounds
        applyMirroringIfAvailable()
        DispatchQueue.main.async { [weak self] in
            self?.applyMirroringIfAvailable()
        }
    }

    func detach() {
        attachedRefreshToken = nil
        previewLayer.session = nil
    }

    private func applyMirroringIfAvailable() {
        guard let connection = previewLayer.connection else { return }
        connection.isEnabled = true
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

}

private extension NotificationCenter {
    func removeObservers(_ observers: [NSObjectProtocol]) {
        observers.forEach(removeObserver)
    }
}

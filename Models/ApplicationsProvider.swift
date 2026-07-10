import AppKit
import Foundation

enum ApplicationItemKind: String, CaseIterable, Identifiable {
    case folder
    case application

    var id: String { rawValue }

    var title: String {
        switch self {
        case .folder: "文件夹"
        case .application: "应用程序"
        }
    }

    var sortRank: Int {
        switch self {
        case .folder: 0
        case .application: 1
        }
    }
}

enum ApplicationSortOption: String, CaseIterable, Identifiable {
    case name
    case kind
    case size
    case creationDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "名称"
        case .kind: "种类"
        case .size: "大小"
        case .creationDate: "日期"
        }
    }

    var systemName: String {
        switch self {
        case .name: "textformat"
        case .kind: "square.grid.2x2"
        case .creationDate: "calendar"
        case .size: "externaldrive"
        }
    }
}

struct ApplicationItem: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: NSImage
    let url: URL
    let kind: ApplicationItemKind
    let creationDate: Date?
    let size: Int64?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class ApplicationsProvider: ObservableObject {

    @Published private(set) var applications: [ApplicationItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingSizes = false

    private var customApplicationOrder: [ApplicationItem.ID]?
    private var hasLoadedCustomOrder = false
    private var loadTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var sizeGeneration = 0
    private static let customOrderKey = "ApplicationsCustomOrder"
    nonisolated private static let iconImageSize = NSSize(width: 52, height: 52)

    deinit {
        loadTask?.cancel()
        sizeTask?.cancel()
    }

    var hasManualOrder: Bool {
        customApplicationOrder != nil
    }

    func load() {
        if !hasLoadedCustomOrder {
            hasLoadedCustomOrder = true
            loadCustomOrder()
        }

        guard !isLoading, applications.isEmpty else { return }
        isLoading = true

        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration

        loadTask = Task.detached(priority: .userInitiated) { [generation] in
            let apps = await Self.scanApplications()
            let wasCancelled = Task.isCancelled

            await MainActor.run { [weak self] in
                guard let self,
                      self.loadGeneration == generation else { return }

                if !wasCancelled {
                    applications = applyingCustomOrder(to: apps)
                }

                isLoading = false
                loadTask = nil
            }
        }
    }

    func loadSizesIfNeeded() {
        guard !isLoadingSizes, applications.contains(where: { $0.size == nil }) else { return }
        isLoadingSizes = true

        let sizeTargets = applications.map { (id: $0.id, url: $0.url) }
        sizeTask?.cancel()
        sizeGeneration += 1
        let generation = sizeGeneration

        sizeTask = Task.detached(priority: .utility) { [generation] in
            var sizes: [String: Int64] = [:]
            for target in sizeTargets {
                guard !Task.isCancelled else { break }
                sizes[target.id] = await Self.cachedDirectorySize(at: target.url)
            }

            let wasCancelled = Task.isCancelled
            let resolvedSizes = sizes
            await MainActor.run { [weak self] in
                guard let self,
                      self.sizeGeneration == generation else { return }

                if !wasCancelled {
                    applications = applications.map { item in
                        ApplicationItem(
                            id: item.id,
                            name: item.name,
                            icon: item.icon,
                            url: item.url,
                            kind: item.kind,
                            creationDate: item.creationDate,
                            size: resolvedSizes[item.id] ?? item.size
                        )
                    }
                }

                isLoadingSizes = false
                sizeTask = nil
            }
        }
    }

    // MARK: - Manual reorder

    func reorderApplications(from fromIndex: Int, to toIndex: Int, visibleItems: [ApplicationItem]) {
        guard fromIndex != toIndex,
              visibleItems.indices.contains(fromIndex),
              toIndex >= 0,
              toIndex <= visibleItems.count else { return }

        var reorderedVisibleItems = visibleItems
        let item = reorderedVisibleItems.remove(at: fromIndex)
        let insertionIndex = min(toIndex, reorderedVisibleItems.count)
        reorderedVisibleItems.insert(item, at: insertionIndex)

        if visibleItems.count == applications.count {
            applications = reorderedVisibleItems
        } else {
            var visibleIterator = reorderedVisibleItems.makeIterator()
            let visibleIDs = Set(visibleItems.map(\.id))
            applications = applications.map { currentItem in
                visibleIDs.contains(currentItem.id) ? (visibleIterator.next() ?? currentItem) : currentItem
            }
        }

        customApplicationOrder = applications.map(\.id)
        saveCustomOrder()
    }

    func clearManualOrder() {
        guard customApplicationOrder != nil else { return }
        customApplicationOrder = nil
        saveCustomOrder()
    }

    private func applyingCustomOrder(to items: [ApplicationItem]) -> [ApplicationItem] {
        guard let order = customApplicationOrder else { return items }

        let orderMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return items.sorted { left, right in
            let leftRank = orderMap[left.id] ?? Int.max
            let rightRank = orderMap[right.id] ?? Int.max

            if leftRank != rightRank {
                return leftRank < rightRank
            }

            return Self.sortByName(left, right)
        }
    }

    private func loadCustomOrder() {
        guard let data = UserDefaults.standard.data(forKey: Self.customOrderKey),
              let decoded = try? JSONDecoder().decode([ApplicationItem.ID].self, from: data) else { return }
        customApplicationOrder = decoded
    }

    private func saveCustomOrder() {
        guard let customApplicationOrder else {
            UserDefaults.standard.removeObject(forKey: Self.customOrderKey)
            return
        }

        if let data = try? JSONEncoder().encode(customApplicationOrder) {
            UserDefaults.standard.set(data, forKey: Self.customOrderKey)
        }
    }

    nonisolated private static func scanApplications() async -> [ApplicationItem] {
        let fm = FileManager.default
        let directories = applicationDirectories()
        let signature = applicationScanSignature(for: directories, fileManager: fm)

        if let cached = await ApplicationDataCache.shared.applications(for: signature) {
            return cached
        }

        var items: [ApplicationItem] = []
        var seen = Set<String>()

        for dir in directories {
            guard !Task.isCancelled else { return items.sorted(by: sortByName) }

            let url = URL(fileURLWithPath: dir)
            guard let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey, .localizedNameKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for itemURL in contents {
                guard !Task.isCancelled else { return items.sorted(by: sortByName) }
                guard let kind = itemKind(for: itemURL) else { continue }
                await appendItem(itemURL, kind: kind, fileManager: fm, seen: &seen, items: &items)
            }

            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey, .localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let nestedURL = enumerator.nextObject() as? URL {
                guard nestedURL.pathExtension == "app" else { continue }
                guard !Task.isCancelled else { return items.sorted(by: sortByName) }
                await appendItem(nestedURL, kind: .application, fileManager: fm, seen: &seen, items: &items)
            }
        }

        let sortedItems = items.sorted(by: sortByName)
        if !Task.isCancelled {
            await ApplicationDataCache.shared.storeApplications(sortedItems, signature: signature)
        }

        return sortedItems
    }

    nonisolated private static func applicationDirectories() -> [String] {
        [
            "/Applications",
            "/System/Applications",
            ("~/Applications" as NSString).expandingTildeInPath
        ]
    }

    nonisolated private static func applicationScanSignature(for directories: [String], fileManager: FileManager) -> String {
        directories.map { path in
            let url = URL(fileURLWithPath: path)
            let directoryValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileResourceIdentifierKey])
            let directoryToken = resourceSignature(path: path, values: directoryValues)
            let contents = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .fileResourceIdentifierKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let entriesToken = contents
                .sorted { $0.path < $1.path }
                .map { entryURL in
                    let values = try? entryURL.resourceValues(forKeys: [
                        .contentModificationDateKey,
                        .isDirectoryKey,
                        .fileResourceIdentifierKey
                    ])
                    return resourceSignature(path: entryURL.path, values: values)
                }
                .joined(separator: ";")

            return "\(directoryToken)[\(entriesToken)]"
        }
        .joined(separator: "|")
    }

    nonisolated private static func appendItem(
        _ itemURL: URL,
        kind: ApplicationItemKind,
        fileManager: FileManager,
        seen: inout Set<String>,
        items: inout [ApplicationItem]
    ) async {
        let name = displayName(for: itemURL, fileManager: fileManager)
        let identity = itemIdentity(for: itemURL, kind: kind, fallbackName: name)
        guard !seen.contains(identity) else { return }
        seen.insert(identity)

        let resourceValues = try? itemURL.resourceValues(forKeys: [.creationDateKey])
        let icon = await ThreadSafeImageCache.shared.icon(for: itemURL, targetSize: iconImageSize)
        guard !Task.isCancelled else { return }

        items.append(ApplicationItem(
            id: itemURL.path,
            name: name,
            icon: icon,
            url: itemURL,
            kind: kind,
            creationDate: resourceValues?.creationDate,
            size: nil
        ))
    }

    nonisolated private static func itemKind(for url: URL) -> ApplicationItemKind? {
        if url.pathExtension == "app" {
            return .application
        }

        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if resourceValues?.isDirectory == true {
            return .folder
        }

        return nil
    }

    nonisolated private static func displayName(for itemURL: URL, fileManager: FileManager) -> String {
        if itemURL.pathExtension == "app", let bundle = Bundle(url: itemURL) {
            if let displayName = localizedBundleName(for: bundle, key: "CFBundleDisplayName") {
                return strippedAppExtension(displayName)
            }

            if let bundleName = localizedBundleName(for: bundle, key: "CFBundleName") {
                return strippedAppExtension(bundleName)
            }
        }

        if let resourceName = cleanName(try? itemURL.resourceValues(forKeys: [.localizedNameKey]).localizedName) {
            return strippedAppExtension(resourceName)
        }

        let finderName = strippedAppExtension(fileManager.displayName(atPath: itemURL.path))
        if !finderName.isEmpty {
            return finderName
        }

        return itemURL.deletingPathExtension().lastPathComponent
    }

    nonisolated private static func localizedBundleName(for bundle: Bundle, key: String) -> String? {
        if let localizedName = localizedInfoPlistValue(for: bundle, key: key) {
            return localizedName
        }

        if let localizedName = cleanName(bundle.localizedInfoDictionary?[key] as? String) {
            return localizedName
        }

        return cleanName(bundle.object(forInfoDictionaryKey: key) as? String)
    }

    nonisolated private static func localizedInfoPlistValue(for bundle: Bundle, key: String) -> String? {
        guard let resourceURL = bundle.resourceURL else { return nil }

        let candidates = preferredLocalizationCandidates()
        if let localizedName = localizedLoctableValue(
            at: resourceURL.appendingPathComponent("InfoPlist.loctable"),
            key: key,
            candidates: candidates
        ) {
            return localizedName
        }

        for candidate in candidates {
            let stringsURL = resourceURL
                .appendingPathComponent("\(candidate).lproj")
                .appendingPathComponent("InfoPlist.strings")

            if let localizedName = localizedStringsValue(at: stringsURL, key: key) {
                return localizedName
            }
        }

        return nil
    }

    nonisolated private static func preferredLocalizationCandidates() -> [String] {
        let candidates = Locale.preferredLanguages.flatMap { language in
            localizationCandidates(for: language)
        } + ["Base", "en"]

        return candidates.reduce(into: []) { result, candidate in
            guard !result.contains(candidate) else { return }
            result.append(candidate)
        }
    }

    nonisolated private static func localizationCandidates(for language: String) -> [String] {
        let normalized = language.replacingOccurrences(of: "-", with: "_")
        let parts = normalized.split(separator: "_").map(String.init)
        var candidates = [language, normalized]

        if let first = parts.first, first == "zh" {
            if normalized.contains("HK") {
                candidates.append("zh_HK")
                candidates.append("zh-HK")
                candidates.append("zh_Hant")
                candidates.append("zh-Hant")
            } else if normalized.contains("TW") || normalized.contains("Hant") {
                candidates.append("zh_TW")
                candidates.append("zh-TW")
                candidates.append("zh_Hant")
                candidates.append("zh-Hant")
            } else {
                candidates.append("zh_CN")
                candidates.append("zh-CN")
                candidates.append("zh_Hans")
                candidates.append("zh-Hans")
            }
        }

        if parts.count >= 2 {
            candidates.append("\(parts[0])_\(parts[1])")
            candidates.append("\(parts[0])-\(parts[1])")
        }

        if let first = parts.first {
            candidates.append(first)
        }

        return candidates
    }

    nonisolated private static func localizedLoctableValue(
        at url: URL,
        key: String,
        candidates: [String]
    ) -> String? {
        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let localizations = plist as? [String: Any]
        else {
            return nil
        }

        for candidate in candidates {
            guard
                let values = localizations[candidate] as? [String: Any],
                let localizedName = cleanName(values[key] as? String)
            else {
                continue
            }

            return localizedName
        }

        return nil
    }

    nonisolated private static func localizedStringsValue(at url: URL, key: String) -> String? {
        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let values = plist as? [String: Any]
        else {
            return nil
        }

        return cleanName(values[key] as? String)
    }

    nonisolated private static func cleanName(_ name: String?) -> String? {
        guard let name else { return nil }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanName.isEmpty ? nil : cleanName
    }

    nonisolated private static func itemIdentity(
        for itemURL: URL,
        kind: ApplicationItemKind,
        fallbackName: String
    ) -> String {
        if kind == .application, let bundleIdentifier = Bundle(url: itemURL)?.bundleIdentifier {
            return bundleIdentifier
        }

        return "\(kind.rawValue):\(itemURL.standardizedFileURL.path)"
    }

    nonisolated private static func sortByName(_ left: ApplicationItem, _ right: ApplicationItem) -> Bool {
        left.name.localizedStandardCompare(right.name) == .orderedAscending
    }

    nonisolated private static func cachedDirectorySize(at url: URL) async -> Int64 {
        let signature = sizeCacheSignature(for: url)
        if let cached = await ApplicationDataCache.shared.directorySize(for: url.path, signature: signature) {
            return cached
        }

        let size = directorySize(at: url)
        if !Task.isCancelled {
            await ApplicationDataCache.shared.storeDirectorySize(size, for: url.path, signature: signature)
        }
        return size
    }

    nonisolated private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileAllocatedSizeKey, .isRegularFileKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard !Task.isCancelled else { return total }
            guard let values = try? fileURL.resourceValues(forKeys: [
                .fileAllocatedSizeKey,
                .isRegularFileKey,
                .totalFileAllocatedSizeKey
            ]) else {
                continue
            }

            guard values.isRegularFile == true else { continue }
            let byteCount = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total += Int64(byteCount)
        }

        return total
    }

    nonisolated private static func sizeCacheSignature(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey,
            .fileResourceIdentifierKey
        ])
        return resourceSignature(path: url.standardizedFileURL.path, values: values)
    }

    nonisolated private static func resourceSignature(path: String, values: URLResourceValues?) -> String {
        let modificationTime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let creationTime = values?.creationDate?.timeIntervalSince1970 ?? 0
        let identifier = values?.fileResourceIdentifier.map { "\($0)" } ?? ""
        return "\(path)#\(modificationTime)#\(creationTime)#\(identifier)"
    }

    nonisolated private static func strippedAppExtension(_ name: String) -> String {
        if name.localizedCaseInsensitiveCompare(".app") == .orderedSame {
            return ""
        }

        guard name.lowercased().hasSuffix(".app") else {
            return name
        }

        return String(name.dropLast(4))
    }
}

private actor ApplicationDataCache {
    static let shared = ApplicationDataCache()

    private var applicationSignature: String?
    private var applicationItems: [ApplicationItem] = []
    private var directorySizes: [String: (signature: String, size: Int64)] = [:]
    private let maxDirectorySizeEntries = 256

    func applications(for signature: String) -> [ApplicationItem]? {
        guard applicationSignature == signature else { return nil }
        return applicationItems
    }

    func storeApplications(_ items: [ApplicationItem], signature: String) {
        if applicationSignature != signature {
            directorySizes.removeAll(keepingCapacity: true)
        }
        applicationSignature = signature
        applicationItems = items
    }

    func directorySize(for path: String, signature: String) -> Int64? {
        guard let cached = directorySizes[path],
              cached.signature == signature else { return nil }
        return cached.size
    }

    func storeDirectorySize(_ size: Int64, for path: String, signature: String) {
        directorySizes[path] = (signature, size)
        trimDirectorySizeCacheIfNeeded()
    }

    private func trimDirectorySizeCacheIfNeeded() {
        guard directorySizes.count > maxDirectorySizeEntries else { return }

        for key in directorySizes.keys.prefix(directorySizes.count - maxDirectorySizeEntries) {
            directorySizes.removeValue(forKey: key)
        }
    }
}

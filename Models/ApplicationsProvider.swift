import AppKit
import CoreServices
import Darwin
import Foundation

enum ApplicationItemKind: String, CaseIterable, Identifiable, Sendable {
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
    case recent
    case name
    case kind
    case size
    case creationDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "最近"
        case .name: "名称"
        case .kind: "种类"
        case .size: "大小"
        case .creationDate: "日期"
        }
    }

    var systemName: String {
        switch self {
        case .recent: "clock"
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
    let phoneticSortName: String
    let catalogIdentity: String
    let icon: NSImage
    let url: URL
    let kind: ApplicationItemKind
    let creationDate: Date?
    let size: Int64?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct ApplicationCandidate: Sendable {
    let url: URL
    let resolvedURL: URL
    let kind: ApplicationItemKind
    let identity: String
    let version: String
    let directoryRank: Int

    func isPreferred(to other: Self) -> Bool {
        if directoryRank != other.directoryRank { return directoryRank < other.directoryRank }
        let comparison = version.compare(other.version, options: .numeric)
        if comparison != .orderedSame { return comparison == .orderedDescending }
        return url.path < other.url.path
    }
}

struct ApplicationUsage: Codable {
    private static let halfLife: TimeInterval = 7 * 24 * 60 * 60
    private static let launchCooldown: TimeInterval = 60
    static let minimumScore = 0.05

    var score: Double
    var lastUsedAt: TimeInterval

    func effectiveScore(at time: TimeInterval) -> Double {
        let elapsed = max(0, time - lastUsedAt)
        return score * exp2(-elapsed / Self.halfLife)
    }

    mutating func recordLaunch(at time: TimeInterval, weight: Double) {
        let elapsed = time - lastUsedAt
        guard elapsed >= 0 else { return }
        if elapsed >= Self.launchCooldown {
            score = effectiveScore(at: time) + weight
        }
        lastUsedAt = time
    }
}

@MainActor
final class ApplicationsProvider: ObservableObject {

    @Published private(set) var applications: [ApplicationItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingSizes = false

    @Published private(set) var pinnedApplicationIDs: Set<ApplicationItem.ID> = []
    @Published private(set) var hiddenApplicationIdentities: Set<String> = []

    private let directories = ApplicationsProvider.applicationDirectories()
    private var indexedDirectories: [String: [ApplicationCandidate]] = [:]
    private var pendingDirectories: Set<String> = []
    private var scanningDirectories: Set<String> = []
    private var directoryWatcher: ApplicationsDirectoryWatcher?
    private var lastDirectoryEventID: FSEventStreamEventId?
    private var isBrowsing = false

    private var usageByApplicationID: [ApplicationItem.ID: ApplicationUsage] = [:]
    private static let usageKey = "ApplicationsFrecency"
    private static let legacyRecentLaunchKey = "ApplicationsRecentLaunches"
    private static let hiddenApplicationsKey = "ApplicationsHiddenIdentities"
    private static let pinnedApplicationsKey = "ApplicationsPinnedIDs"
    private static let usageLimit = 256
    private var customApplicationOrder: [ApplicationItem.ID]?
    private var hasLoadedPreferences = false
    private var loadTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var sizeGeneration = 0
    private static let customOrderKey = "ApplicationsCustomOrder"
    nonisolated private static let iconImageSize = NSSize(width: 64, height: 64)

    deinit {
        loadTask?.cancel()
        sizeTask?.cancel()
    }

    var hasManualOrder: Bool {
        customApplicationOrder != nil
    }

    func load() {
        if !hasLoadedPreferences {
            hasLoadedPreferences = true
            loadCustomOrder()
            pinnedApplicationIDs = Set(UserDefaults.standard.stringArray(forKey: Self.pinnedApplicationsKey) ?? [])
            hiddenApplicationIdentities = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenApplicationsKey) ?? [])
            loadUsage()
        }

        guard !isBrowsing else { return }
        isBrowsing = true
        if lastDirectoryEventID == nil {
            lastDirectoryEventID = FSEventsGetCurrentEventId()
            pendingDirectories.formUnion(directories)
        }
        if let lastDirectoryEventID {
            directoryWatcher = ApplicationsDirectoryWatcher(directories: directories, since: lastDirectoryEventID) { [weak self] paths, eventID in
                guard let self, self.isBrowsing else { return }
                self.lastDirectoryEventID = eventID
                let affected = self.directories.filter { directory in
                    paths.contains { path in
                        path == directory || path.hasPrefix(directory + "/") || directory.hasPrefix(path + "/")
                    }
                }
                self.pendingDirectories.formUnion(affected.isEmpty ? self.directories : affected)
                self.refreshPendingDirectories()
            }
            if directoryWatcher == nil {
                pendingDirectories.formUnion(directories)
                self.lastDirectoryEventID = nil
            }
        }
        refreshPendingDirectories()
    }

    func stopBrowsing() {
        isBrowsing = false
        directoryWatcher = nil
        pendingDirectories.formUnion(scanningDirectories)
        scanningDirectories.removeAll()
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        sizeGeneration += 1
        sizeTask?.cancel()
        sizeTask = nil
        isLoadingSizes = false
    }

    private func refreshPendingDirectories() {
        guard isBrowsing, loadTask == nil, !pendingDirectories.isEmpty else { return }
        isLoading = applications.isEmpty
        let dirty = pendingDirectories
        pendingDirectories.removeAll()
        scanningDirectories = dirty
        loadGeneration += 1
        let generation = loadGeneration
        let dirs = directories
        let cached = indexedDirectories
        let displayed = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0) })

        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            var updated = cached
            for directory in dirs where dirty.contains(directory) {
                guard !Task.isCancelled else { return }
                updated[directory] = Self.scanDirectory(directory, priorities: dirs)
            }
            let apps = await Self.makeItems(from: updated, directories: dirs, dirty: dirty, displayed: displayed)
            guard !Task.isCancelled else { return }
            let scanned = updated
            await MainActor.run { [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                let hadSizes = self.isLoadingSizes || self.applications.contains { $0.size != nil }
                self.sizeGeneration += 1
                self.sizeTask?.cancel()
                self.sizeTask = nil
                self.isLoadingSizes = false
                self.indexedDirectories = scanned
                self.applications = self.applyingCustomOrder(to: apps)
                self.scanningDirectories.removeAll()
                self.isLoading = false
                self.loadTask = nil
                self.refreshPendingDirectories()
                if hadSizes, self.loadTask == nil { self.loadSizesIfNeeded() }
            }
        }
    }

    func setHidden(_ hidden: Bool, for item: ApplicationItem) {
        if hidden {
            hiddenApplicationIdentities.insert(item.catalogIdentity)
        } else {
            hiddenApplicationIdentities.remove(item.catalogIdentity)
        }
        UserDefaults.standard.set(hiddenApplicationIdentities.sorted(), forKey: Self.hiddenApplicationsKey)
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
                            phoneticSortName: item.phoneticSortName,
                            catalogIdentity: item.catalogIdentity,
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

    func recordLaunch(_ item: ApplicationItem, fromSearch: Bool) {
        guard item.kind == .application else { return }

        let now = Date().timeIntervalSince1970
        let weight = fromSearch ? 1.5 : 1.0
        if var usage = usageByApplicationID[item.id] {
            usage.recordLaunch(at: now, weight: weight)
            usageByApplicationID[item.id] = usage
        } else {
            usageByApplicationID[item.id] = ApplicationUsage(score: weight, lastUsedAt: now)
        }
        if usageByApplicationID.count > Self.usageLimit,
           let coldest = usageByApplicationID.min(by: {
               $0.value.effectiveScore(at: now) < $1.value.effectiveScore(at: now)
           }) {
            usageByApplicationID.removeValue(forKey: coldest.key)
        }
        saveUsage()
    }

    func usageScores(at time: TimeInterval = Date().timeIntervalSince1970) -> [ApplicationItem.ID: Double] {
        usageByApplicationID.compactMapValues { usage in
            let score = usage.effectiveScore(at: time)
            return score >= ApplicationUsage.minimumScore ? score : nil
        }
    }

    func togglePin(_ item: ApplicationItem) {
        guard item.kind == .application else { return }
        if pinnedApplicationIDs.remove(item.id) == nil {
            pinnedApplicationIDs.insert(item.id)
        }
        UserDefaults.standard.set(pinnedApplicationIDs.sorted(), forKey: Self.pinnedApplicationsKey)
    }

    private func loadUsage() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.usageKey),
           let usage = try? PropertyListDecoder().decode([ApplicationItem.ID: ApplicationUsage].self, from: data) {
            usageByApplicationID = usage
            return
        }

        guard let legacyIDs = defaults.stringArray(forKey: Self.legacyRecentLaunchKey), !legacyIDs.isEmpty else { return }
        // The old list has no dates or counts. Give its entries the same small boost.
        let seed = ApplicationUsage(score: 0.25, lastUsedAt: Date().timeIntervalSince1970 - 60)
        for id in legacyIDs.prefix(Self.usageLimit) {
            usageByApplicationID[id] = seed
        }
        saveUsage()
    }

    private func saveUsage() {
        if let data = try? PropertyListEncoder().encode(usageByApplicationID) {
            UserDefaults.standard.set(data, forKey: Self.usageKey)
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

    nonisolated private static func applicationDirectories() -> [String] {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return ["/Applications", home + "/Applications", "/System/Applications"]
    }

    nonisolated private static func scanDirectory(_ path: String, priorities: [String]) -> [ApplicationCandidate] {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let manager = FileManager.default
        guard let scanner = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isAliasFileKey, .isPackageKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var preferred: [String: ApplicationCandidate] = [:]
        var folders: [ApplicationCandidate] = []
        var foldersWithApplications: Set<String> = []
        var topLevelFolder: String?

        while let url = scanner.nextObject() as? URL {
            guard !Task.isCancelled else { break }
            let isTopLevel = scanner.level == 1
            if isTopLevel { topLevelFolder = url.lastPathComponent }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isAliasFileKey, .isPackageKey, .isSymbolicLinkKey])
            let resolved: URL
            if values?.isAliasFile == true, values?.isSymbolicLink != true {
                guard let alias = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) else { continue }
                resolved = alias.resolvingSymlinksInPath()
            } else {
                resolved = url.resolvingSymlinksInPath()
            }

            if url.pathExtension.lowercased() == "app" || resolved.pathExtension.lowercased() == "app" {
                // The enumerator already prunes recognized packages. Only skip a
                // directory manually if it wasn't recognized as a package.
                if values?.isDirectory == true, values?.isPackage != true {
                    scanner.skipDescendants()
                }
                if !isTopLevel, let topLevelFolder { foldersWithApplications.insert(topLevelFolder) }
                guard resolved.pathExtension.lowercased() == "app",
                      (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let bundle = Bundle(url: resolved)
                if let bundle, isBackgroundApplication(bundle) { continue }

                let identity = cleanName(bundle?.bundleIdentifier).map { "bundle:" + $0 } ?? "app:" + resolved.path
                let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                let folderRank = priorities.firstIndex { resolved.path.hasPrefix($0 + "/") } ?? priorities.count
                let candidate = ApplicationCandidate(
                    url: url, resolvedURL: resolved, kind: .application,
                    identity: identity, version: version, directoryRank: folderRank
                )
                if let other = preferred[identity], !candidate.isPreferred(to: other) { continue }
                preferred[identity] = candidate
            } else if isTopLevel, values?.isDirectory == true {
                folders.append(ApplicationCandidate(
                    url: url, resolvedURL: resolved, kind: .folder, identity: "folder:" + resolved.path,
                    version: "", directoryRank: priorities.firstIndex(of: path) ?? priorities.count
                ))
            }
        }

        return Array(preferred.values) + folders.filter { !foldersWithApplications.contains($0.url.lastPathComponent) }
    }

    nonisolated private static func isBackgroundApplication(_ bundle: Bundle) -> Bool {
        ["LSUIElement", "LSBackgroundOnly"].contains { key in
            let value = bundle.object(forInfoDictionaryKey: key)
            if let flag = value as? NSNumber { return flag.boolValue }
            if let flag = value as? String { return (flag as NSString).boolValue }
            return false
        }
    }

    nonisolated private static func makeItems(
        from indexed: [String: [ApplicationCandidate]],
        directories: [String],
        dirty: Set<String>,
        displayed: [String: ApplicationItem]
    ) async -> [ApplicationItem] {
        var winners: [String: (candidate: ApplicationCandidate, directory: String)] = [:]
        for directory in directories {
            for candidate in indexed[directory] ?? [] {
                if let current = winners[candidate.identity], !candidate.isPreferred(to: current.candidate) { continue }
                winners[candidate.identity] = (candidate, directory)
            }
        }

        var items: [ApplicationItem] = []
        for (candidate, directory) in winners.values {
            guard !Task.isCancelled else { return [] }
            if !dirty.contains(directory), let item = displayed[candidate.url.path] {
                items.append(item)
                continue
            }

            let name = displayName(for: candidate.resolvedURL, fileManager: .default)
            let date = try? candidate.resolvedURL.resourceValues(forKeys: [.creationDateKey]).creationDate
            let artwork = ThreadSafeImageCache.shared
            let icon = candidate.kind == .application
                ? await artwork.applicationIcon(for: candidate.resolvedURL, targetSize: iconImageSize)
                : await artwork.icon(for: candidate.resolvedURL, targetSize: iconImageSize)
            items.append(ApplicationItem(
                id: candidate.url.path,
                name: name,
                phoneticSortName: (name.applyingTransform(.mandarinToLatin, reverse: false) ?? name)
                    .folding(options: .diacriticInsensitive, locale: nil),
                catalogIdentity: candidate.identity,
                icon: icon,
                url: candidate.resolvedURL,
                kind: candidate.kind,
                creationDate: date,
                size: nil
            ))
        }
        return items.sorted(by: sortByName)
    }

    nonisolated private static func displayName(for itemURL: URL, fileManager: FileManager) -> String {
        if itemURL.pathExtension.lowercased() == "app", let bundle = Bundle(url: itemURL) {
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

    nonisolated private static func sortByName(_ left: ApplicationItem, _ right: ApplicationItem) -> Bool {
        let comparison = left.name.localizedStandardCompare(right.name)
        return comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
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

    private var directorySizes: [String: (signature: String, size: Int64)] = [:]
    private let maxDirectorySizeEntries = 256

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

/// Watches while the application page is open. The provider keeps the last
/// delivered ID to replay changes that happened between visits.
private final class ApplicationsDirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor ([String], FSEventStreamEventId) -> Void

    init?(
        directories: [String],
        since eventID: FSEventStreamEventId,
        onChange: @escaping @MainActor ([String], FSEventStreamEventId) -> Void
    ) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, { _, info, count, rawPaths, flags, ids in
            guard let info else { return }
            let watcher = Unmanaged<ApplicationsDirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let rawArray = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue()
            let paths = rawArray as NSArray
            var changedPaths: [String] = []
            var latestID: FSEventStreamEventId = 0
            var mustRescan = false
            for index in 0..<count {
                let flag = flags[index]
                if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) != 0 { continue }
                latestID = max(latestID, ids[index])
                if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagEventIdsWrapped) != 0 {
                    mustRescan = true
                }
                if let path = paths[index] as? String {
                    let dataVolume = "/System/Volumes/Data"
                    changedPaths.append(path.hasPrefix(dataVolume + "/") ? String(path.dropFirst(dataVolume.count)) : path)
                }
            }
            guard mustRescan || !changedPaths.isEmpty else { return }
            if latestID == 0 { latestID = FSEventsGetCurrentEventId() }
            MainActor.assumeIsolated {
                watcher.onChange(mustRescan ? [] : changedPaths, latestID)
            }
        }, &context, directories as CFArray,
            eventID == 0 ? FSEventStreamEventId(kFSEventStreamEventIdSinceNow) : eventID,
            0.7, flags) else { return nil }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}

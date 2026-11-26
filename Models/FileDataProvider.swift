import AppKit
import Darwin
import Foundation
import ImageIO
import QuickLookThumbnailing
import Quartz
import UniformTypeIdentifiers

struct StagingFileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let artwork: StagingFileArtwork
    var icon: NSImage { artwork.icon }
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let date: Date
    let kind: String
    var thumbnail: NSImage? { artwork.thumbnail }
    let isPreviewable: Bool
    let typeIdentifier: String
    var hasLoadedArtwork: Bool { artwork.isLoaded }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var sizeText: String {
        Self.formatSize(size)
    }

    var dateText: String {
        Self.dateFormatterLock.lock()
        defer { Self.dateFormatterLock.unlock() }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatterLock = NSLock()
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    private static func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1024 / 1024) }
        return String(format: "%.1f GB", Double(bytes) / 1024 / 1024 / 1024)
    }
}

// Image updates only redraw the corresponding cell, without sorting the full directory again.
final class StagingFileArtwork: ObservableObject {
    @Published private(set) var icon: NSImage
    @Published private(set) var thumbnail: NSImage?
    private(set) var isLoaded = false
    private let placeholder: NSImage

    init(placeholder: NSImage) {
        self.placeholder = placeholder
        self.icon = placeholder
    }

    @MainActor
    func update(icon: NSImage, thumbnail: NSImage?) {
        self.icon = icon
        self.thumbnail = thumbnail
        isLoaded = true
    }

    @MainActor
    func reset() {
        guard isLoaded else { return }
        icon = placeholder
        thumbnail = nil
        isLoaded = false
    }
}

struct FilePathSegment: Identifiable, Hashable {
    let title: String
    let url: URL

    var id: String { url.path }
}

struct FileOperationResult: Equatable, Sendable {
    var isSuccess: Bool
    var errorMessage: String?

    static let success = FileOperationResult(isSuccess: true, errorMessage: nil)

    static func failure(_ message: String) -> FileOperationResult {
        FileOperationResult(isSuccess: false, errorMessage: message)
    }
}

struct FileImportResult: Equatable, Sendable {
    var importedCount: Int
    var failures: [String]

    var importedAny: Bool {
        importedCount > 0
    }

    var failureMessage: String? {
        guard !failures.isEmpty else { return nil }
        if failures.count == 1 {
            return failures[0]
        }
        return "\(failures.count) 个文件未能导入：\(failures.prefix(3).joined(separator: "、"))"
    }
}

enum FileCategory: String, CaseIterable, Identifiable {
    case all
    case image
    case document
    case video
    case audio
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "所有"
        case .image: "图片"
        case .document: "文档"
        case .video: "视频"
        case .audio: "音频"
        case .other: "其他"
        }
    }

    var systemName: String {
        switch self {
        case .all: "line.3.horizontal.decrease.circle"
        case .image: "photo"
        case .document: "doc.text"
        case .video: "film"
        case .audio: "waveform"
        case .other: "ellipsis.circle"
        }
    }

    static func category(typeIdentifier: String, isDirectory: Bool) -> FileCategory {
        guard !isDirectory, let type = UTType(typeIdentifier) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) || type.conforms(to: .pdf)
            || type.conforms(to: .compositeContent) { return .document }
        return .other
    }

    func matches(_ file: StagingFileItem) -> Bool {
        self == .all || self == Self.category(typeIdentifier: file.typeIdentifier, isDirectory: file.isDirectory)
    }
}

enum FileSortOption: String, CaseIterable, Identifiable {
    case name
    case date
    case size
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "名称"
        case .date: "日期"
        case .size: "大小"
        case .kind: "类型"
        }
    }

    var systemName: String {
        switch self {
        case .name: "arrow.up.arrow.down"
        case .date: "calendar"
        case .size: "externaldrive"
        case .kind: "square.grid.2x2"
        }
    }
}

struct FileDataLocation: Codable, Equatable, Sendable {
    static let documentsDirectory: URL = {
        // Foundation's current home can point to the app container. The account
        // record supplies the real home used by Finder's Documents folder.
        let accountHome = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) }
            ?? NSHomeDirectoryForUser(NSUserName())
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: accountHome, isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
    }()

    static let defaultLocation = Self(url: defaultFolder(in: documentsDirectory), bookmark: nil, usesDocumentsFolder: false)

    let url: URL
    private let bookmark: Data?
    private let usesDocumentsFolder: Bool

    var hasAuthorization: Bool { bookmark != nil }

    static func authorizedSelection(_ selectedFolder: URL, useDefault: Bool) throws -> Self {
        defer { selectedFolder.stopAccessingSecurityScopedResource() }
        let folder = selectedFolder.resolvingSymlinksInPath().standardizedFileURL
        let documents = documentsDirectory.resolvingSymlinksInPath().standardizedFileURL
        let defaultURL = defaultFolder(in: documentsDirectory)
        let usesDocumentsFolder = useDefault && folder.path == documents.path
        if useDefault && !usesDocumentsFolder && folder.path != defaultURL.resolvingSymlinksInPath().path {
            throw FileDataLocationError.invalidDefaultSelection
        }

        let bookmark = try selectedFolder.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
        )
        let location = Self(
            url: useDefault ? defaultURL : selectedFolder.standardizedFileURL,
            bookmark: bookmark,
            usesDocumentsFolder: usesDocumentsFolder
        )
        let access = try location.open()
        try withExtendedLifetime(access) {
            try FileManager.default.createDirectory(at: access.root, withIntermediateDirectories: true)
            guard FileManager.default.isWritableFile(atPath: access.root.path) else {
                throw FileDataLocationError.notWritable
            }
        }
        return location
    }

    func open() throws -> FileDataAccess {
        guard let bookmark else { throw FileDataLocationError.authorizationRequired }
        var isStale = false
        let folder: URL
        do {
            folder = try URL(
                resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                relativeTo: nil, bookmarkDataIsStale: &isStale
            )
        } catch {
            throw FileDataLocationError.authorizationRequired
        }
        guard folder.startAccessingSecurityScopedResource() else {
            throw FileDataLocationError.authorizationRequired
        }
        let root = usesDocumentsFolder ? Self.defaultFolder(in: folder) : folder
        guard FileDataAccess.contains(root, in: folder) else {
            folder.stopAccessingSecurityScopedResource()
            throw FileDataLocationError.outsideSelectedFolder
        }
        return FileDataAccess(scopedFolder: folder, root: root.standardizedFileURL)
    }

    private static func defaultFolder(in documents: URL) -> URL {
        documents.appendingPathComponent("NookFlow", isDirectory: true)
            .appendingPathComponent("FileData", isDirectory: true)
    }
}

private enum FileDataLocationError: LocalizedError {
    case authorizationRequired
    case invalidDefaultSelection
    case outsideSelectedFolder
    case notWritable

    var errorDescription: String? {
        switch self {
        case .authorizationRequired: "请在设置 → 通用 → 文件存储中授权 FileData 目录。"
        case .invalidDefaultSelection: "请选择当前用户的「文稿」或「文稿/NookFlow/FileData」。"
        case .outsideSelectedFolder: "目标路径超出了已选择的文件夹。"
        case .notWritable: "所选文件夹不可写，请选择一个有读写权限的目录。"
        }
    }
}

final class FileDataAccess: Sendable {
    let root: URL
    private let scopedFolder: URL

    fileprivate init(scopedFolder: URL, root: URL) {
        self.scopedFolder = scopedFolder
        self.root = root
    }

    deinit { scopedFolder.stopAccessingSecurityScopedResource() }

    static func contains(_ candidate: URL, in directory: URL) -> Bool {
        let rootPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let targetPath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        return targetPath == rootPath || targetPath.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }
}

@MainActor
final class FileDataProvider: ObservableObject {

    @Published private(set) var files: [StagingFileItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var currentDirectory = FileDataLocation.defaultLocation.url
    private(set) var location = FileDataLocation.defaultLocation
    private(set) var directoryAccess: FileDataAccess?
    private var resolvedRoot: URL?
    var rootDirectory: URL { resolvedRoot ?? location.url }
    @Published var searchText = ""
    @Published var category: FileCategory = .all
    @Published var sortOption: FileSortOption = .date
    @Published var showsRemovedFiles = false
    @Published private(set) var removedFileIDs = Set(
        UserDefaults.standard.stringArray(forKey: FileDataProvider.removedFilesKey) ?? []
    )

    /// Tracks manual file order per directory (directory path → [file ID]).
    private var customFileOrder: [String: [StagingFileItem.ID]] = [:]
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private static let customOrderKey = "FileDataCustomOrder"
    private static let removedFilesKey = "FileDataRemovedFilePaths"
    nonisolated private static let iconImageSize = NSSize(width: 48, height: 48)
    nonisolated private static let thumbnailImageSize = NSSize(width: 56, height: 56)

    func useLocation(_ location: FileDataLocation) {
        guard self.location != location else { return }
        cancelLoading()
        self.location = location
        resolvedRoot = nil
        currentDirectory = location.url
        files = []
        loadError = nil
        searchText = ""
    }

    deinit {
        loadTask?.cancel()
    }

    /// Whether the current directory has a user-defined manual order.
    var hasManualOrder: Bool {
        let dirKey = currentDirectory.standardizedFileURL.path
        return customFileOrder[dirKey] != nil
    }

    var filteredFiles: [StagingFileItem] {
        var result = files

        if !showsRemovedFiles, !removedFileIDs.isEmpty {
            result = result.filter { !removedFileIDs.contains($0.id) }
        }

        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        if category != .all {
            result = result.filter { category.matches($0) }
        }

        let dirKey = currentDirectory.standardizedFileURL.path
        if let order = customFileOrder[dirKey], searchText.isEmpty, category == .all {
            let orderMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            result.sort { a, b in
                let ra = orderMap[a.id] ?? Int.max
                let rb = orderMap[b.id] ?? Int.max
                return ra < rb
            }
        } else {
            switch sortOption {
            case .name:
                result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .date:
                result.sort { $0.date > $1.date }
            case .size:
                result.sort { $0.size > $1.size }
            case .kind:
                result.sort { $0.kind.localizedCaseInsensitiveCompare($1.kind) == .orderedAscending }
            }
        }

        return result
    }

    var pathSegments: [FilePathSegment] {
        let root = rootDirectory.standardizedFileURL
        let current = currentDirectory.standardizedFileURL
        guard current.path != root.path, current.path.hasPrefix(root.path + "/") else { return [] }

        let relativePath = String(current.path.dropFirst(root.path.count + 1))
        var url = root

        return relativePath
            .split(separator: "/")
            .map(String.init)
            .map { component in
                url = url.appendingPathComponent(component)
                return FilePathSegment(title: component, url: url)
            }
    }

    @discardableResult
    nonisolated static func importFilesToStaging(_ urls: [URL], location: FileDataLocation) -> FileImportResult {
        let fm = FileManager.default
        let access: FileDataAccess
        do {
            access = try location.open()
            try fm.createDirectory(at: access.root, withIntermediateDirectories: true)
        } catch {
            return FileImportResult(
                importedCount: 0,
                failures: ["无法创建 FileData 文件夹：\(error.localizedDescription)"]
            )
        }

        defer { withExtendedLifetime(access) {} }
        let rootPath = access.root.resolvingSymlinksInPath().standardizedFileURL.path
        var importedCount = 0
        var failures: [String] = []
        for sourceURL in urls {
            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let sourceParent = sourceURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            if sourceParent.path == rootPath {
                importedCount += 1
                continue
            }
            if FileDataAccess.contains(access.root, in: sourceURL) {
                failures.append("无法将“\(sourceURL.lastPathComponent)”复制到自身或其子目录。")
                continue
            }

            let destinationURL = uniqueDestinationURL(for: sourceURL, in: access.root, fileManager: fm)
            do {
                try fm.copyItem(at: sourceURL, to: destinationURL)
                importedCount += 1
            } catch {
                failures.append("\(sourceURL.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        return FileImportResult(importedCount: importedCount, failures: failures)
    }

    private var hasLoadedCustomOrder = false

    func load() {
        if !hasLoadedCustomOrder {
            hasLoadedCustomOrder = true
            loadCustomOrder()
        }

        isLoading = true
        loadError = nil
        let directory = currentDirectory
        let priorRoot = rootDirectory
        let existingAccess = directoryAccess
        let location = location
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration

        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<(items: [StagingFileItem], access: FileDataAccess, directory: URL), Error>
            do {
                let access = try existingAccess ?? location.open()
                let target = priorRoot.path != access.root.path || directory.path == priorRoot.path ? access.root : directory
                guard FileDataAccess.contains(target, in: access.root) else {
                    throw FileDataLocationError.outsideSelectedFolder
                }
                try FileManager.default.createDirectory(at: access.root, withIntermediateDirectories: true)
                let items = try await Self.scanDirectory(target)
                result = .success((items, access, target))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                switch result {
                case .success(let loaded):
                    self.directoryAccess = loaded.access
                    self.resolvedRoot = loaded.access.root
                    if self.currentDirectory != loaded.directory {
                        self.currentDirectory = loaded.directory
                    }
                    self.files = loaded.items
                    self.applyCustomOrderIfNeeded()
                case .failure(let error):
                    self.files = []
                    self.loadError = "无法读取“\(directory.lastPathComponent)”：\(error.localizedDescription)"
                }
                self.isLoading = false
                self.loadTask = nil
            }
        }
    }

    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
        isLoading = false
        directoryAccess = nil
    }

    func loadArtwork(for file: StagingFileItem) async {
        guard !isLoading, !file.hasLoadedArtwork, let directoryAccess else { return }
        let generation = loadGeneration
        let task = Task.detached(priority: .utility) {
            defer { withExtendedLifetime(directoryAccess) {} }
            let icon = await ThreadSafeImageCache.shared.icon(for: file.url, targetSize: Self.iconImageSize)
            guard !Task.isCancelled else { return (icon, Optional<NSImage>.none) }
            let thumbnail = file.isPreviewable
                ? await ThreadSafeImageCache.shared.thumbnail(for: file.url, typeID: file.typeIdentifier, targetSize: Self.thumbnailImageSize)
                : nil
            return (icon, thumbnail)
        }
        let (icon, thumbnail) = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard !Task.isCancelled, loadGeneration == generation,
              let index = files.firstIndex(where: { $0.id == file.id }) else { return }
        files[index].artwork.update(icon: icon, thumbnail: thumbnail)
    }

    func unloadArtwork(for file: StagingFileItem) {
        file.artwork.reset()
    }

    private static func placeholderIcon(isDirectory: Bool) -> NSImage {
        NSImage(systemSymbolName: isDirectory ? "folder.fill" : "doc.fill", accessibilityDescription: nil)
            ?? NSImage(size: iconImageSize)
    }

    func enterFolder(_ file: StagingFileItem) {
        guard file.isDirectory else { return }
        goToDirectory(file.url)
    }

    func goToDirectory(_ url: URL) {
        let root = rootDirectory.standardizedFileURL
        let target = url.standardizedFileURL
        guard target.path == root.path || target.path.hasPrefix(root.path + "/") else { return }
        guard target != currentDirectory.standardizedFileURL || isLoading else { return }

        currentDirectory = target
        searchText = ""
        load()
    }

    // MARK: - Sort

    /// Set sort option and clear any manual order for the current directory.
    func setSortOption(_ option: FileSortOption) {
        sortOption = option
        clearManualOrder()
    }

    func setRemovedFromList(_ removed: Bool, fileID: StagingFileItem.ID) {
        guard removed != removedFileIDs.contains(fileID) else { return }
        if removed {
            removedFileIDs.insert(fileID)
        } else {
            removedFileIDs.remove(fileID)
        }
        UserDefaults.standard.set(removedFileIDs.sorted(), forKey: Self.removedFilesKey)
    }

    func trashFile(_ file: StagingFileItem) async -> FileOperationResult {
        let parentPath = file.url.deletingLastPathComponent().standardizedFileURL.path
        guard let access = directoryAccess, files.contains(where: { $0.id == file.id }),
              parentPath == currentDirectory.standardizedFileURL.path
        else { return .failure("无法访问“\(file.name)”。") }
        defer { withExtendedLifetime(access) {} }

        do {
            let recycled = try await NSWorkspace.shared.recycle([file.url])
            guard !recycled.isEmpty else {
                return .failure("系统未能将“\(file.name)”移到废纸篓。")
            }
            setRemovedFromList(false, fileID: file.id)
            if currentDirectory.standardizedFileURL.path == parentPath {
                files.removeAll { $0.id == file.id }
                if directoryAccess != nil || isLoading { load() }
            }
            return .success
        } catch {
            return .failure("无法将“\(file.name)”移到废纸篓：\(error.localizedDescription)")
        }
    }

    // MARK: - Manual reorder

    /// Move a file from one visible index to another within the current directory.
    func reorderFiles(from fromIndex: Int, to toIndex: Int) {
        let visibleFiles = filteredFiles
        guard fromIndex != toIndex,
              visibleFiles.indices.contains(fromIndex),
              toIndex >= 0,
              toIndex <= visibleFiles.count else { return }

        var reorderedVisibleFiles = visibleFiles
        let item = reorderedVisibleFiles.remove(at: fromIndex)
        let insertionIndex = min(toIndex, reorderedVisibleFiles.count)
        reorderedVisibleFiles.insert(item, at: insertionIndex)

        if searchText.isEmpty, category == .all, visibleFiles.count == files.count {
            files = reorderedVisibleFiles
        } else {
            var visibleIterator = reorderedVisibleFiles.makeIterator()
            let visibleIDs = Set(visibleFiles.map(\.id))
            files = files.map { currentFile in
                visibleIDs.contains(currentFile.id) ? (visibleIterator.next() ?? currentFile) : currentFile
            }
        }

        let dirKey = currentDirectory.standardizedFileURL.path
        customFileOrder[dirKey] = files.map(\.id)
        saveCustomOrder()
    }

    /// Move a file from the current directory into a visible folder.
    @discardableResult
    func moveFile(_ file: StagingFileItem, toFolder folder: StagingFileItem) async -> FileOperationResult {
        guard canMove(file, into: folder) else {
            return .failure("无法将“\(file.name)”移动到“\(folder.name)”。")
        }

        let sourceURL = file.url
        let folderURL = folder.url
        let sourceID = file.id
        let currentDirKey = currentDirectory.standardizedFileURL.path
        let targetDirKey = folder.url.standardizedFileURL.path

        guard let directoryAccess else { return .failure("请先授权 FileData 目录。") }
        let moveTask = Task.detached(priority: .userInitiated) { () -> (destinationURL: URL?, errorMessage: String?) in
            defer { withExtendedLifetime(directoryAccess) {} }
            guard FileDataAccess.contains(folderURL, in: directoryAccess.root) else {
                return (nil, "目标路径超出了 FileData 目录。")
            }
            let fm = FileManager.default
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: sourceURL.path),
                  fm.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return (nil, "源文件或目标文件夹不存在。")
            }

            let destinationURL = FileDataProvider.uniqueDestinationURL(for: sourceURL, in: folderURL, fileManager: fm)
            do {
                try fm.moveItem(at: sourceURL, to: destinationURL)
                return (destinationURL, nil)
            } catch {
                return (nil, "移动“\(sourceURL.lastPathComponent)”失败：\(error.localizedDescription)")
            }
        }
        let moveResult = await moveTask.value

        guard let destinationURL = moveResult.destinationURL else {
            return .failure(moveResult.errorMessage ?? "移动“\(file.name)”失败。")
        }

        guard currentDirectory.standardizedFileURL.path == currentDirKey else {
            return .success
        }

        files.removeAll { $0.id == sourceID }

        customFileOrder[currentDirKey] = files.map(\.id)

        if var targetOrder = customFileOrder[targetDirKey] {
            targetOrder.removeAll { $0 == sourceID || $0 == destinationURL.path }
            targetOrder.append(destinationURL.path)
            customFileOrder[targetDirKey] = targetOrder
        }

        saveCustomOrder()
        return .success
    }

    private func canMove(_ file: StagingFileItem, into folder: StagingFileItem) -> Bool {
        guard folder.isDirectory,
              file.id != folder.id else { return false }

        if file.isDirectory {
            let sourcePath = file.url.standardizedFileURL.path
            let folderPath = folder.url.standardizedFileURL.path
            guard folderPath != sourcePath,
                  !folderPath.hasPrefix(sourcePath + "/") else {
                return false
            }
        }

        return true
    }

    /// Clear manual order for the current directory (called when user explicitly changes sort).
    func clearManualOrder() {
        let dirKey = currentDirectory.standardizedFileURL.path
        guard customFileOrder.removeValue(forKey: dirKey) != nil else { return }
        saveCustomOrder()
    }

    /// Apply saved custom order after loading files from disk.
    private func applyCustomOrderIfNeeded() {
        let dirKey = currentDirectory.standardizedFileURL.path
        guard let order = customFileOrder[dirKey] else { return }

        let orderMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        files.sort { a, b in
            let ra = orderMap[a.id] ?? Int.max
            let rb = orderMap[b.id] ?? Int.max
            return ra < rb
        }
    }

    private func loadCustomOrder() {
        guard let data = UserDefaults.standard.data(forKey: Self.customOrderKey),
              let decoded = try? JSONDecoder().decode([String: [StagingFileItem.ID]].self, from: data) else { return }
        customFileOrder = decoded
    }

    private func saveCustomOrder() {
        if customFileOrder.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.customOrderKey)
        } else if let data = try? JSONEncoder().encode(customFileOrder) {
            UserDefaults.standard.set(data, forKey: Self.customOrderKey)
        }
    }

    nonisolated static func scanDirectory(_ dir: URL) async throws -> [StagingFileItem] {
        let fm = FileManager.default

        let contents = try fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .typeIdentifierKey],
            options: [.skipsHiddenFiles]
        )

        let (folderIcon, documentIcon) = await MainActor.run {
            (Self.placeholderIcon(isDirectory: true), Self.placeholderIcon(isDirectory: false))
        }
        var items: [StagingFileItem] = []
        items.reserveCapacity(contents.count)

        for url in contents {
            try Task.checkCancellation()

            let resourceValues = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .typeIdentifierKey
            ])

            let isDir = resourceValues?.isDirectory ?? false
            let size = Int64(resourceValues?.fileSize ?? 0)
            let date = resourceValues?.contentModificationDate ?? Date()
            let typeID = resourceValues?.typeIdentifier ?? ""
            let kind = Self.kindString(for: typeID, isDirectory: isDir)

            let icon = isDir ? folderIcon : documentIcon
            let previewable = Self.isPreviewable(typeID: typeID, isDirectory: isDir)

            items.append(StagingFileItem(
                id: url.path,
                name: url.lastPathComponent,
                artwork: StagingFileArtwork(placeholder: icon),
                url: url,
                isDirectory: isDir,
                size: size,
                date: date,
                kind: kind,
                isPreviewable: previewable,
                typeIdentifier: typeID
            ))
        }

        return items
    }

    nonisolated private static func uniqueDestinationURL(for sourceURL: URL, in directory: URL, fileManager: FileManager) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension
        var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let name = fileExtension.isEmpty
                ? "\(baseName) (\(suffix))"
                : "\(baseName) (\(suffix)).\(fileExtension)"
            candidate = directory.appendingPathComponent(name)
            suffix += 1
        }

        return candidate
    }

    nonisolated private static func kindString(for typeID: String, isDirectory: Bool) -> String {
        if isDirectory { return "文件夹" }

        if let type = UTType(typeID) {
            if type.conforms(to: .image) { return "图片" }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return "视频" }
            if type.conforms(to: .audio) { return "音频" }
            if type.conforms(to: .pdf) { return "PDF" }
            if type.conforms(to: .plainText) || type.conforms(to: .rtf) || type.conforms(to: .html) { return "文档" }
            if type.conforms(to: .archive) || type.conforms(to: .zip) { return "压缩包" }
            if type.conforms(to: .application) { return "应用" }
        }

        return "文件"
    }

    nonisolated private static func isPreviewable(typeID: String, isDirectory: Bool) -> Bool {
        guard !isDirectory else { return false }
        guard let type = UTType(typeID) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

}

actor ThreadSafeImageCache {
    static let shared = ThreadSafeImageCache()

    private let iconCache = NSCache<NSString, NSImage>()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let fallbackIconCache = NSCache<NSString, NSImage>()
    private let scale: CGFloat = 2
    private let applicationIconSampleSize = 16
    private var genericSystemIconSamples: Set<Data>?

    private init() {
        iconCache.countLimit = 400
        iconCache.totalCostLimit = 24 * 1024 * 1024
        thumbnailCache.countLimit = 160
        thumbnailCache.totalCostLimit = 32 * 1024 * 1024
        fallbackIconCache.countLimit = 8
    }

    func icon(for url: URL, targetSize: NSSize) async -> NSImage {
        let key = cacheKey(for: url, targetSize: targetSize, variant: "icon")
        if let cached = iconCache.object(forKey: key) {
            return cached
        }

        guard !Task.isCancelled else {
            return await fallbackIcon(for: url, targetSize: targetSize)
        }

        if let image = await quickLookImage(for: url, targetSize: targetSize, representations: .icon) {
            iconCache.setObject(image, forKey: key, cost: cacheCost(for: image))
            return image
        }

        let fallback = await fallbackIcon(for: url, targetSize: targetSize)
        iconCache.setObject(fallback, forKey: key, cost: cacheCost(for: fallback))
        return fallback
    }

    func applicationIcon(for url: URL, targetSize: NSSize) async -> NSImage {
        let bundleURL = url.resolvingSymlinksInPath()
        let key = cacheKey(for: bundleURL, targetSize: targetSize, variant: "application-icon")
        if let cached = iconCache.object(forKey: key) { return cached }
        guard !Task.isCancelled else { return await applicationPlaceholder() }

        // Use the same application artwork when the same bundle is installed.
        // Workspace covers app icons supplied only through an asset catalog.
        if let image = bundledApplicationIcon(for: bundleURL, targetSize: targetSize)
            ?? systemApplicationIcon(for: bundleURL, targetSize: targetSize) {
            iconCache.setObject(image, forKey: key, cost: cacheCost(for: image))
            return image
        }
        // A failed lookup can be retried on a later scan without pinning a placeholder.
        return await applicationPlaceholder()
    }

    private func systemApplicationIcon(for url: URL, targetSize: NSSize) -> NSImage? {
        guard !Task.isCancelled else { return nil }
        let workspace = NSWorkspace.shared
        if genericSystemIconSamples == nil {
            let genericTypes: [UTType] = [.applicationBundle, .unixExecutable, .data, .folder, .item]
            genericSystemIconSamples = Set(genericTypes.compactMap { type in
                renderedSystemIcon(workspace.icon(for: type)).flatMap { applicationIconSample($0) }
            })
        }

        guard let icon = renderedSystemIcon(workspace.icon(forFile: url.path)),
              let sample = applicationIconSample(icon),
              genericSystemIconSamples?.contains(sample) == false,
              let normalized = visibleApplicationIcon(icon, sample: sample) else { return nil }

        let size = fittedSize(for: normalized, targetSize: targetSize)
        let width = max(1, Int((size.width * scale).rounded(.up)))
        let height = max(1, Int((size.height * scale).rounded(.up)))
        if normalized.width <= width, normalized.height <= height {
            return NSImage(cgImage: normalized, size: size)
        }

        guard let canvas = applicationIconContext(width: width, height: height) else { return nil }
        canvas.interpolationQuality = .high
        canvas.setBlendMode(.copy)
        canvas.draw(normalized, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = canvas.makeImage() else { return nil }
        return NSImage(cgImage: resized, size: size)
    }

    private func renderedSystemIcon(_ icon: NSImage) -> CGImage? {
        var rect = CGRect(x: 0, y: 0, width: 128, height: 128)
        return icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func applicationPlaceholder() async -> NSImage {
        let key: NSString = "application-placeholder"
        if let cached = fallbackIconCache.object(forKey: key) { return cached }

        let image = await MainActor.run {
            NSImage(systemSymbolName: "app", accessibilityDescription: "应用")
                ?? NSWorkspace.shared.icon(for: .applicationBundle)
        }
        fallbackIconCache.setObject(image, forKey: key)
        return image
    }

    private func bundledApplicationIcon(for url: URL, targetSize: NSSize) -> NSImage? {
        guard let bundle = Bundle(url: url) else { return nil }
        for key in ["CFBundleIconFile", "CFBundleIconName"] {
            guard let name = bundle.object(forInfoDictionaryKey: key) as? String,
                  !name.isEmpty, (name as NSString).lastPathComponent == name else { continue }

            let pathExtension = (name as NSString).pathExtension
            let resourceName = pathExtension.isEmpty ? name : (name as NSString).deletingPathExtension
            if let resourceURL = bundle.url(forResource: resourceName, withExtension: pathExtension.isEmpty ? "icns" : pathExtension),
               let image = imageIOThumbnail(for: resourceURL, targetSize: targetSize, isApplicationIcon: true) {
                return image
            }
        }
        return nil
    }

    func thumbnail(for url: URL, typeID: String, targetSize: NSSize) async -> NSImage? {
        let key = cacheKey(for: url, targetSize: targetSize, variant: "thumbnail")
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        guard !Task.isCancelled else { return nil }

        let image: NSImage?
        if let type = UTType(typeID), type.conforms(to: .image) {
            image = imageIOThumbnail(for: url, targetSize: targetSize)
        } else if let type = UTType(typeID), type.conforms(to: .pdf) {
            image = pdfThumbnail(for: url, targetSize: targetSize)
        } else {
            image = await quickLookImage(for: url, targetSize: targetSize, representations: .thumbnail)
        }

        guard !Task.isCancelled, let image else { return nil }
        thumbnailCache.setObject(image, forKey: key, cost: cacheCost(for: image))
        return image
    }

    func preview(for url: URL, targetSize: NSSize) async -> NSImage? {
        guard targetSize.width > 0,
              targetSize.height > 0,
              targetSize.width.isFinite,
              targetSize.height.isFinite,
              !Task.isCancelled else { return nil }

        let typeID = (try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier) ?? ""
        if let type = UTType(typeID), type.conforms(to: .image) {
            return imageIOThumbnail(for: url, targetSize: targetSize)
        }
        if let type = UTType(typeID), type.conforms(to: .pdf) {
            return pdfThumbnail(for: url, targetSize: targetSize)
        }
        return await quickLookImage(for: url, targetSize: targetSize, representations: .thumbnail)
    }

    private func quickLookImage(
        for url: URL,
        targetSize: NSSize,
        representations: QLThumbnailGenerator.Request.RepresentationTypes
    ) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: targetSize,
            scale: scale,
            representationTypes: representations
        )

        do {
            let representation = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            } onCancel: {
                QLThumbnailGenerator.shared.cancel(request)
            }
            guard !Task.isCancelled else { return nil }
            return NSImage(cgImage: representation.cgImage, size: targetSize)
        } catch {
            return nil
        }
    }

    private func imageIOThumbnail(for url: URL, targetSize: NSSize, isApplicationIcon: Bool = false) -> NSImage? {
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let maxPixelSize = max(targetSize.width, targetSize.height) * scale
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded(.up))
        ]

        let representationCount = isApplicationIcon ? CGImageSourceGetCount(source) : 1
        for index in 0..<representationCount {
            guard !Task.isCancelled else { return nil }
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            let image = isApplicationIcon ? visibleApplicationIcon(thumbnail) : thumbnail
            if let image {
                return NSImage(cgImage: image, size: fittedSize(for: image, targetSize: targetSize))
            }
        }
        return nil
    }

    private func applicationIconContext(width: Int, height: Int) -> CGContext? {
        let format = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: format
        )
    }

    private func applicationIconSample(_ image: CGImage) -> Data? {
        let size = applicationIconSampleSize
        guard let context = applicationIconContext(width: size, height: size),
              let data = context.data else { return nil }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return Data(bytes: data, count: context.bytesPerRow * size)
    }

    private func visibleApplicationIcon(_ image: CGImage, sample: Data? = nil) -> CGImage? {
        guard let pixels = sample ?? applicationIconSample(image) else { return nil }
        let sampleSize = applicationIconSampleSize
        func alpha(at x: Int, _ y: Int) -> UInt8 {
            pixels[(y * sampleSize + x) * 4 + 3]
        }

        // An asset-catalog app can ship a fully transparent legacy .icns.
        let allPixels = 0..<(sampleSize * sampleSize)
        guard allPixels.contains(where: { alpha(at: $0 % sampleSize, $0 / sampleSize) > 0 }) else { return nil }

        let last = sampleSize - 1
        guard image.width == image.height,
              [alpha(at: 0, 0), alpha(at: 0, last), alpha(at: last, 0), alpha(at: last, last)]
                  .allSatisfy({ $0 >= 250 }),
              let shaped = applicationIconContext(width: image.width, height: image.height) else { return image }

        // Shape only raw square artwork. Images with their own mask pass through.
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let inset = rect.width * 0.08
        let iconRect = rect.insetBy(dx: inset, dy: inset)
        let radius = iconRect.width * 0.22
        shaped.clear(rect)
        shaped.addPath(CGPath(roundedRect: iconRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        shaped.clip()
        shaped.draw(image, in: iconRect)
        return shaped.makeImage()
    }

    private func pdfThumbnail(for url: URL, targetSize: NSSize) -> NSImage? {
        guard !Task.isCancelled,
              let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: 1) else { return nil }

        let pageRect = page.getBoxRect(.mediaBox)
        guard pageRect.width > 0,
              pageRect.height > 0,
              pageRect.width.isFinite,
              pageRect.height.isFinite else { return nil }

        let drawScale = min(targetSize.width / pageRect.width, targetSize.height / pageRect.height)
        let imageSize = NSSize(width: pageRect.width * drawScale, height: pageRect.height * drawScale)
        let pixelWidth = max(1, Int((imageSize.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((imageSize.height * scale).rounded(.up)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard !Task.isCancelled,
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
              ) else { return nil }

        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: drawScale, y: -drawScale)
        context.drawPDFPage(page)

        guard !Task.isCancelled,
              let cgImage = context.makeImage() else { return nil }

        return NSImage(cgImage: cgImage, size: imageSize)
    }

    private func fallbackIcon(for url: URL, targetSize: NSSize) async -> NSImage {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let key = NSString(string: "\(isDirectory ? "folder" : "doc")|\(Int(targetSize.width))x\(Int(targetSize.height))")
        if let cached = fallbackIconCache.object(forKey: key) {
            return cached
        }

        let image = await MainActor.run {
            NSImage(
                systemSymbolName: isDirectory ? "folder.fill" : "doc.fill",
                accessibilityDescription: nil
            ) ?? NSImage(size: targetSize)
        }
        fallbackIconCache.setObject(image, forKey: key)
        return image
    }

    private func cacheCost(for image: NSImage) -> Int {
        let pixelWidth = max(1, Int((image.size.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((image.size.height * scale).rounded(.up)))
        return pixelWidth * pixelHeight * 4
    }

    private func cacheKey(for url: URL, targetSize: NSSize, variant: String) -> NSString {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let timestamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return NSString(
            string: "\(variant)|\(url.standardizedFileURL.path)|\(Int(targetSize.width))x\(Int(targetSize.height))|\(timestamp)|\(size)"
        )
    }

    private func fittedSize(for cgImage: CGImage, targetSize: NSSize) -> NSSize {
        let sourceSize = NSSize(width: cgImage.width, height: cgImage.height)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return targetSize }

        let ratio = min(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        return NSSize(width: sourceSize.width * ratio, height: sourceSize.height * ratio)
    }
}

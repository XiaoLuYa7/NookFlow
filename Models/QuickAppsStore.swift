import AppKit
import Foundation

@MainActor
final class QuickAppsStore: ObservableObject {

    static let shared = QuickAppsStore()
    static let pageSize = 6
    static let maxCount = 36

    @Published private(set) var items: [QuickAppItem] = []

    private let defaults = UserDefaults.standard
    private let storageKey = "settings.quickApps"
    private var iconCache: [String: NSImage] = [:]

    private init() {
        load()
    }

    // MARK: - CRUD

    func addApp(at url: URL) -> Bool {
        guard items.count < Self.maxCount else { return false }

        let path = url.path
        guard !items.contains(where: { $0.applicationPath == path }) else { return false }

        let bundle = Bundle(url: url)
        let name = bundle?.infoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        let bundleID = bundle?.bundleIdentifier

        let item = QuickAppItem(
            name: name,
            bundleIdentifier: bundleID,
            applicationPath: path,
            order: items.count
        )

        items.append(item)
        save()
        return true
    }

    func clearAll() {
        items.removeAll()
        iconCache.removeAll()
        save()
    }

    func removeApp(id: UUID) {
        items.removeAll { $0.id == id }
        reorderAndSave()
        iconCache.removeAll()
    }

    func moveApp(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        reorderAndSave()
    }

    func swapApp(id: UUID, withIndex target: Int) {
        guard let source = items.firstIndex(where: { $0.id == id }),
              items.indices.contains(target),
              source != target else { return }

        items.swapAt(source, target)
        reorderAndSave()
    }

    func isAppAvailable(_ item: QuickAppItem) -> Bool {
        FileManager.default.fileExists(atPath: item.applicationPath)
    }

    // MARK: - Icon

    func icon(for item: QuickAppItem) -> NSImage {
        let path = item.applicationPath
        if let cached = iconCache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        iconCache[path] = icon
        return icon
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([QuickAppItem].self, from: data) else {
            return
        }
        items = decoded.sorted { $0.order < $1.order }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func reorderAndSave() {
        for i in items.indices {
            items[i].order = i
        }
        save()
    }
}

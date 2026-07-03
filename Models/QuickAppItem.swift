import Foundation

struct QuickAppItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bundleIdentifier: String?
    var applicationPath: String
    var order: Int

    init(name: String, bundleIdentifier: String?, applicationPath: String, order: Int) {
        self.id = UUID()
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.applicationPath = applicationPath
        self.order = order
    }
}

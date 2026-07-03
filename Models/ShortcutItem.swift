import Foundation

struct ShortcutItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var detailText: String
    var isPinnedToIsland: Bool
    var canRun: Bool
    var order: Int
    var shortcutIdentifier: String

    init(
        id: UUID,
        name: String,
        detailText: String = "",
        isPinnedToIsland: Bool = false,
        canRun: Bool = true,
        order: Int = 0,
        shortcutIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.detailText = detailText
        self.isPinnedToIsland = isPinnedToIsland
        self.canRun = canRun
        self.order = order
        self.shortcutIdentifier = shortcutIdentifier ?? id.uuidString
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case detailText
        case isPinnedToIsland
        case canRun
        case order
        case shortcutIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)

        self.id = id
        self.name = try container.decode(String.self, forKey: .name)
        self.detailText = try container.decodeIfPresent(String.self, forKey: .detailText) ?? ""
        self.isPinnedToIsland = try container.decodeIfPresent(Bool.self, forKey: .isPinnedToIsland) ?? false
        self.canRun = try container.decodeIfPresent(Bool.self, forKey: .canRun) ?? true
        self.order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        self.shortcutIdentifier = try container.decodeIfPresent(String.self, forKey: .shortcutIdentifier) ?? id.uuidString
    }
}

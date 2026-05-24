import Foundation

nonisolated struct Session: Identifiable, Hashable, Codable, Sendable {
    struct Metadata: Hashable, Codable, Sendable {
        static let defaultTitle = "New Session"

        var title: String
        var createdAt: Date
        var updatedAt: Date
        var tags: [String]
        var isPinned: Bool
        var isArchived: Bool

        enum CodingKeys: String, CodingKey {
            case title
            case createdAt
            case updatedAt
            case tags
            case isPinned
            case isArchived
        }

        init(
            title: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            tags: [String] = [],
            isPinned: Bool = false,
            isArchived: Bool = false
        ) {
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tags = tags
            self.isPinned = isPinned
            self.isArchived = isArchived
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            tags = try container.decode([String].self, forKey: .tags)
            isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
            isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        }
    }

    let id: UUID
    var metadata: Metadata

    init(id: UUID = UUID(), metadata: Metadata) {
        self.id = id
        self.metadata = metadata
    }
}

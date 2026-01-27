import Foundation

nonisolated struct Session: Identifiable, Hashable, Codable {
    nonisolated struct Metadata: Hashable, Codable {
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var tags: [String]

        init(
            title: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            tags: [String] = []
        ) {
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tags = tags
        }
    }

    let id: UUID
    var metadata: Metadata

    init(id: UUID = UUID(), metadata: Metadata) {
        self.id = id
        self.metadata = metadata
    }
}

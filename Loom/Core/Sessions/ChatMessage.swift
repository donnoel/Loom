import Foundation

nonisolated struct ChatMessage: Identifiable, Hashable, Codable {
    nonisolated enum Role: String, Codable {
        case system
        case user
        case assistant
        case tool
    }

    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

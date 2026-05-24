import Foundation

nonisolated struct SessionSearchResult: Identifiable, Equatable, Sendable {
    enum MatchSource: String, Equatable, Sendable {
        case title
        case message
    }

    let sessionID: Session.ID
    let sessionTitle: String
    let snippet: String
    let source: MatchSource
    let messageID: ChatMessage.ID?
    let messageRole: ChatMessage.Role?

    var id: String {
        let messagePart = messageID?.uuidString ?? "title"
        return "\(sessionID.uuidString)-\(source.rawValue)-\(messagePart)-\(snippet)"
    }
}

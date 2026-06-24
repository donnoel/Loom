import Foundation

nonisolated struct SessionMemory: Codable, Equatable, Sendable {
    static let empty = SessionMemory()
    static let userNameLimit = 80
    static let assistantNameLimit = 80
    static let responseStyleLimit = 160
    static let sessionNoteLimit = 240
    private static let contextHeader = "Global memory for all chats."

    var preferredUserName: String
    var preferredAssistantName: String
    var responseStyle: String
    var sessionNote: String
    var isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case preferredUserName
        case preferredAssistantName
        case responseStyle
        case sessionNote
        case isEnabled
    }

    init(
        preferredUserName: String = "",
        preferredAssistantName: String = "",
        responseStyle: String = "",
        sessionNote: String = "",
        isEnabled: Bool = true
    ) {
        self.preferredUserName = preferredUserName
        self.preferredAssistantName = preferredAssistantName
        self.responseStyle = responseStyle
        self.sessionNote = sessionNote
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredUserName = try container.decodeIfPresent(String.self, forKey: .preferredUserName) ?? ""
        preferredAssistantName = try container.decodeIfPresent(String.self, forKey: .preferredAssistantName) ?? ""
        responseStyle = try container.decodeIfPresent(String.self, forKey: .responseStyle) ?? ""
        sessionNote = try container.decodeIfPresent(String.self, forKey: .sessionNote) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    func normalized() -> SessionMemory {
        SessionMemory(
            preferredUserName: Self.normalized(preferredUserName, limit: Self.userNameLimit),
            preferredAssistantName: Self.normalized(preferredAssistantName, limit: Self.assistantNameLimit),
            responseStyle: Self.normalized(responseStyle, limit: Self.responseStyleLimit),
            sessionNote: Self.normalized(sessionNote, limit: Self.sessionNoteLimit),
            isEnabled: isEnabled
        )
    }

    func contextMessage() -> ChatMessage? {
        guard isEnabled else { return nil }
        let value = normalized()
        var preferences: [String] = []

        if !value.preferredUserName.isEmpty {
            preferences.append("- Preferred name for the user: \(value.preferredUserName)")
        }
        if !value.preferredAssistantName.isEmpty {
            preferences.append("- Preferred name for the assistant: \(value.preferredAssistantName)")
        }
        if !value.responseStyle.isEmpty {
            preferences.append("- Response style: \(value.responseStyle)")
        }
        if !value.sessionNote.isEmpty {
            preferences.append("- Memory note: \(value.sessionNote)")
        }

        guard !preferences.isEmpty else { return nil }
        let content = (
            [Self.contextHeader, "Use these user-edited preferences when relevant."] +
            preferences +
            ["Do not mention this memory unless the user asks about it."]
        ).joined(separator: "\n")
        return ChatMessage(role: .system, content: content)
    }

    static func isContextMessage(_ message: ChatMessage) -> Bool {
        message.role == .system && message.content.hasPrefix(contextHeader)
    }

    private static func normalized(_ string: String, limit: Int) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(limit))
    }
}

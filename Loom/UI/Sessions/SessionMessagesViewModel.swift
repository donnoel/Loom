import Foundation
import Observation

@MainActor
@Observable
final class SessionMessagesViewModel {
    private let store: SessionStore
    private let sessionID: UUID

    var messages: [ChatMessage] = []
    var draft: String = ""

    init(store: SessionStore, sessionID: UUID) {
        self.store = store
        self.sessionID = sessionID
    }

    func load() async {
        do {
            messages = try await store.loadMessages(sessionID: sessionID)
        } catch {
            messages = []
        }
    }
    func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""

        do {
            try await store.appendMessage(ChatMessage(role: .user, content: text), sessionID: sessionID)
            messages = try await store.loadMessages(sessionID: sessionID)
        } catch {
            // For v1: fail quietly; later we can surface a banner.
        }
    }
}

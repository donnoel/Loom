import Foundation
import Observation

@MainActor
@Observable
final class SessionMessagesViewModel {
    private let store: SessionStore
    private let sessionID: UUID
    private let onActivity: (() async -> Void)?

    var messages: [ChatMessage] = []
    var draft: String = ""

    init(store: SessionStore, sessionID: UUID, onActivity: (() async -> Void)? = nil) {
        self.store = store
        self.sessionID = sessionID
        self.onActivity = onActivity
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

        let message = ChatMessage(role: .user, content: text)

        do {
            try await store.appendMessage(message, sessionID: sessionID)

            // Update UI state without reloading from disk.
            messages.append(message)
            draft = ""

            if let onActivity {
                await onActivity()
            }
        } catch {
            // Keep draft intact so the user doesn't lose text.
            // For v1: fail quietly; later we can surface a banner.
        }
    }
}

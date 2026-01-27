import Foundation
import Observation

@MainActor
@Observable
final class SessionMessagesViewModel {
    private let store: SessionStore
    private let sessionID: UUID

    var messages: [ChatMessage] = []

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
}

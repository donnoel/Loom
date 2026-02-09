import Foundation
import Observation

@MainActor
@Observable
final class RootViewModel {
    private let store: SessionStore

    var sessions: [Session] = []
    var selectedSessionID: Session.ID?

    init(store: SessionStore) {
        self.store = store
    }

    func load() async {
        do {
            let items = try await store.listSessions()
            sessions = items
            if selectedSessionID == nil {
                selectedSessionID = sessions.first?.id
            }
        } catch {
            // For v1: keep it simple. Later we’ll add a non-intrusive banner.
            sessions = []
        }
    }

    func newSession() async {
        do {
            let created = try await store.createSession(title: "New Session")
            await load()
            selectedSessionID = created.id
        } catch { }
    }

    func deleteSelected() async {
        guard let id = selectedSessionID else { return }
        do {
            try await store.deleteSession(id: id)
            selectedSessionID = nil
            await load()
            if selectedSessionID == nil {
                selectedSessionID = sessions.first?.id
            }
        } catch { }
    }

    func session(for id: Session.ID?) -> Session? {
        guard let id else { return nil }
        return sessions.first(where: { $0.id == id })
    }
    
    func touchSession(id: Session.ID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].metadata.updatedAt = Date()
        sessions.sort { $0.metadata.updatedAt > $1.metadata.updatedAt }
    }
    
    func renameSession(id: Session.ID, to newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard var session = sessions.first(where: { $0.id == id }) else { return }
        guard session.metadata.title != trimmed else { return }

        session.metadata.title = trimmed

        do {
            try await store.updateMetadata(session.metadata, for: id)
            let keepSelected = selectedSessionID
            await load()
            selectedSessionID = keepSelected
        } catch {
            // For v1: ignore quietly. Later we can add a non-intrusive banner.
        }
    }
}

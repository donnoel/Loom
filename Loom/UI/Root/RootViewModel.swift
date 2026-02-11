import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class RootViewModel {
    struct SidebarBannerState: Equatable {
        let text: String
        let actionTitle: String
    }

    private let store: SessionStore
    private let log = Logger(subsystem: "com.loom.app", category: "RootViewModel")

    var sessions: [Session] = []
    var selectedSessionID: Session.ID?
    var sidebarBanner: SidebarBannerState?
    var searchQuery: String = ""

    var filteredSessions: [Session] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }

        return sessions.filter { session in
            if session.metadata.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }

            return session.metadata.tags.contains(where: { tag in
                tag.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            })
        }
    }

    init(store: SessionStore) {
        self.store = store
    }

    func load() async {
        do {
            let items = try await store.listSessions()
            sessions = sortSessions(items)
            sidebarBanner = nil
            if selectedSessionID == nil {
                selectedSessionID = sessions.first?.id
            } else if let selectedSessionID,
                      !sessions.contains(where: { $0.id == selectedSessionID }) {
                self.selectedSessionID = sessions.first?.id
            }
        } catch {
            sessions = []
            sidebarBanner = SidebarBannerState(
                text: "Loom couldn’t load sessions. Try again.",
                actionTitle: "Reload"
            )
        }
    }

    func newSession() async {
        do {
            let created = try await store.createSession(title: "New Session")
            await load()
            selectedSessionID = created.id
        } catch {
            log.error("Failed to create session: \(String(describing: error), privacy: .public)")
            sidebarBanner = SidebarBannerState(
                text: "Loom couldn’t create a session. Try again.",
                actionTitle: "Reload"
            )
        }
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
        } catch {
            log.error("Failed to delete session \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            sidebarBanner = SidebarBannerState(
                text: "Loom couldn’t delete this session. Try again.",
                actionTitle: "Reload"
            )
        }
    }

    func session(for id: Session.ID?) -> Session? {
        guard let id else { return nil }
        return sessions.first(where: { $0.id == id })
    }
    
    func touchSession(id: Session.ID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].metadata.updatedAt = Date()
        sessions = sortSessions(sessions)
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
            log.error("Failed to rename session \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            sidebarBanner = SidebarBannerState(
                text: "Loom couldn’t rename this session. Try again.",
                actionTitle: "Reload"
            )
        }
    }

    func togglePinned(id: Session.ID) async {
        guard var session = sessions.first(where: { $0.id == id }) else { return }
        session.metadata.isPinned.toggle()

        do {
            try await store.updateMetadata(session.metadata, for: id)
            let keepSelected = selectedSessionID
            await load()
            selectedSessionID = keepSelected
        } catch {
            log.error("Failed to update pinned state for session \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            sidebarBanner = SidebarBannerState(
                text: "Loom couldn’t update this session. Try again.",
                actionTitle: "Reload"
            )
        }
    }

    func updateTags(id: Session.ID, tags: [String]) async {
        guard var session = sessions.first(where: { $0.id == id }) else { return }
        guard session.metadata.tags != tags else { return }
        session.metadata.tags = tags

        do {
            try await store.updateMetadata(session.metadata, for: id)
            let keepSelected = selectedSessionID
            await load()
            selectedSessionID = keepSelected
        } catch {
            log.error("Failed to update tags for session \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            sidebarBanner = SidebarBannerState(
                text: "Loom couldn’t update session tags. Try again.",
                actionTitle: "Reload"
            )
        }
    }

    private func sortSessions(_ input: [Session]) -> [Session] {
        input.sorted { lhs, rhs in
            if lhs.metadata.isPinned != rhs.metadata.isPinned {
                return lhs.metadata.isPinned && !rhs.metadata.isPinned
            }
            return lhs.metadata.updatedAt > rhs.metadata.updatedAt
        }
    }
}

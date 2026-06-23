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
    private let searchService: SessionSearchService
    private let log = Logger(subsystem: "com.loom.app", category: "RootViewModel")
    private nonisolated static let globalSearchDebounceDelay: Duration = .milliseconds(250)
    private nonisolated static let globalSearchResultLimit = 50

    var sessions: [Session] = []
    var selectedSessionID: Session.ID?
    var sidebarBanner: SidebarBannerState?
    var searchQuery: String = ""
    var globalSearchResults: [SessionSearchResult] = []
    var isSearchingGlobally: Bool = false
    private var searchGeneration: UInt64 = 0
    private var searchTask: Task<Void, Never>?

    var activeSessions: [Session] {
        sessions.filter { !$0.metadata.isArchived }
    }

    var archivedSessions: [Session] {
        sessions.filter { $0.metadata.isArchived }
    }

    var filteredSessions: [Session] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return activeSessions }

        return activeSessions.filter { session in
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
        self.searchService = SessionSearchService(store: store)
    }

    func load() async {
        do {
            let items = try await store.listSessions()
            sessions = sortSessions(items)
            sidebarBanner = nil
            if selectedSessionID == nil {
                selectedSessionID = defaultSelectionID(from: sessions)
            } else if let selectedSessionID,
                      !sessions.contains(where: { $0.id == selectedSessionID }) {
                self.selectedSessionID = defaultSelectionID(from: sessions)
            }
        } catch {
            sessions = []
            sidebarBanner = SidebarBannerState(
                text: "Loom couldn’t load sessions. Try again.",
                actionTitle: "Reload"
            )
        }

        await refreshGlobalSearchResults()
    }

    func refreshGlobalSearchResults() async {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration &+= 1
        let currentGeneration = searchGeneration

        guard !query.isEmpty else {
            globalSearchResults = []
            isSearchingGlobally = false
            searchTask = nil
            return
        }

        isSearchingGlobally = true
        let sessionSnapshot = sessions
        await performGlobalSearch(
            query: query,
            sessions: sessionSnapshot,
            generation: currentGeneration
        )
    }

    func scheduleGlobalSearchRefresh() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration &+= 1
        let currentGeneration = searchGeneration

        guard !query.isEmpty else {
            globalSearchResults = []
            isSearchingGlobally = false
            searchTask = nil
            return
        }

        isSearchingGlobally = true
        let sessionSnapshot = sessions

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.globalSearchDebounceDelay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await self?.performGlobalSearch(
                query: query,
                sessions: sessionSnapshot,
                generation: currentGeneration
            )
        }
    }

    private func performGlobalSearch(
        query: String,
        sessions sessionSnapshot: [Session],
        generation currentGeneration: UInt64
    ) async {
        let results = await searchService.search(
            query: query,
            in: sessionSnapshot,
            maxResults: Self.globalSearchResultLimit
        )

        guard !Task.isCancelled, currentGeneration == searchGeneration else { return }
        globalSearchResults = results
        isSearchingGlobally = false
        searchTask = nil
    }

    func newSession() async {
        do {
            let created = try await store.createSession(title: Session.Metadata.defaultTitle)
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
    
    func touchSession(id: Session.ID) async {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }

        do {
            if let refreshed = try await store.loadSession(id: id) {
                sessions[idx].metadata = refreshed.metadata
            } else {
                sessions[idx].metadata.updatedAt = Date()
            }
        } catch {
            log.error("Failed to refresh session \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            sessions[idx].metadata.updatedAt = Date()
        }

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

    func toggleArchived(id: Session.ID) async {
        guard var session = sessions.first(where: { $0.id == id }) else { return }
        session.metadata.isArchived.toggle()

        do {
            try await store.updateMetadata(session.metadata, for: id)
            let keepSelected = selectedSessionID
            await load()
            selectedSessionID = keepSelected ?? defaultSelectionID(from: sessions)
        } catch {
            log.error("Failed to update archived state for session \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
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
            if lhs.metadata.isArchived != rhs.metadata.isArchived {
                return !lhs.metadata.isArchived && rhs.metadata.isArchived
            }
            if lhs.metadata.isPinned != rhs.metadata.isPinned {
                return lhs.metadata.isPinned && !rhs.metadata.isPinned
            }
            return lhs.metadata.updatedAt > rhs.metadata.updatedAt
        }
    }

    private func defaultSelectionID(from sessions: [Session]) -> Session.ID? {
        if let firstActive = sessions.first(where: { !$0.metadata.isArchived }) {
            return firstActive.id
        }
        return sessions.first?.id
    }
}

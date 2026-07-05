import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceViewModel {
    private let store: WorkspaceStore
    private let runner: any DeveloperToolRunning
    private let defaults: UserDefaults
    private var activeSecurityScopedRoots: [UUID: URL] = [:]
    private var sendTask: Task<Void, Never>?

    var sessions: [WorkspaceSession] = []
    var selectedSessionID: WorkspaceSession.ID?
    var messages: [ChatMessage] = []
    var toolEvents: [DeveloperToolResult] = []
    var changeRecords: [WorkspaceChangeRecord] = []
    var availableProjects: [WorkspaceSession.ProjectSelection] = []
    var availableSchemes: [String] = []
    var gitDiffText: String = ""
    var draft: String = ""
    var destinationDraft: String = ""
    var bannerText: String?
    var isLoading: Bool = false
    var isSending: Bool = false
    var isRefreshingDiff: Bool = false

    init(
        store: WorkspaceStore = WorkspaceStore(),
        runner: any DeveloperToolRunning = DeveloperToolRunner(),
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.runner = runner
        self.defaults = defaults
    }

    var selectedSession: WorkspaceSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    var providerMode: WorkspaceProviderMode {
        selectedSession?.providerMode ?? .localOllama
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await store.listSessions()
            if selectedSessionID == nil {
                selectedSessionID = sessions.first?.id
            }
            await loadSelectedSessionDetails()
        } catch {
            bannerText = "Loom couldn’t load LoomX projects."
        }
    }

    func selectSession(id: WorkspaceSession.ID) async {
        selectedSessionID = id
        await loadSelectedSessionDetails()
    }

    func addWorkspace(rootURL: URL, bookmarkData: Data?) async {
        do {
            let detectedProjects = WorkspaceProjectDetector.detectProjects(in: rootURL)
            let session = try await store.createSession(
                displayName: rootURL.lastPathComponent,
                rootURL: rootURL,
                bookmarkData: bookmarkData,
                detectedProject: detectedProjects.first
            )
            activeSecurityScopedRoots[session.id] = rootURL
            sessions.insert(session, at: 0)
            selectedSessionID = session.id
            availableProjects = detectedProjects
            availableSchemes = session.selectedProject?.schemes ?? []
            destinationDraft = session.selectedDestination ?? ""
            messages = []
            toolEvents = []
            changeRecords = []
            gitDiffText = ""
            bannerText = nil
            await runReadinessCheck()
        } catch {
            bannerText = "Loom couldn’t add that LoomX project."
        }
    }

    func deleteSelectedWorkspace() async {
        guard let selectedSessionID else { return }
        do {
            try await store.deleteSession(id: selectedSessionID)
            activeSecurityScopedRoots[selectedSessionID]?.stopAccessingSecurityScopedResource()
            activeSecurityScopedRoots[selectedSessionID] = nil
            sessions.removeAll { $0.id == selectedSessionID }
            self.selectedSessionID = sessions.first?.id
            await loadSelectedSessionDetails()
        } catch {
            bannerText = "Loom couldn’t remove that LoomX project."
        }
    }

    func setProviderMode(_ mode: WorkspaceProviderMode) async {
        guard var session = selectedSession else { return }
        session.providerMode = mode
        await saveAndReplace(session)
    }

    func setAutonomousEditsEnabled(_ isEnabled: Bool) async {
        guard var session = selectedSession else { return }
        session.allowsAutonomousEdits = isEnabled
        await saveAndReplace(session)
    }

    func selectProject(relativePath: String) async {
        guard var session = selectedSession,
              let project = availableProjects.first(where: { $0.relativePath == relativePath }) else {
            return
        }
        session.selectedProject = project
        session.selectedScheme = project.schemes.first
        availableSchemes = project.schemes
        await saveAndReplace(session)
        await runReadinessCheck()
    }

    func selectScheme(_ scheme: String) async {
        guard var session = selectedSession else { return }
        session.selectedScheme = scheme.nonEmptyTrimmed
        await saveAndReplace(session)
    }

    func updateDestination(_ destination: String) async {
        guard var session = selectedSession else { return }
        session.selectedDestination = destination.nonEmptyTrimmed
        destinationDraft = session.selectedDestination ?? ""
        await saveAndReplace(session)
    }

    func runReadinessCheck() async {
        guard var session = selectedSession else { return }
        await beginSecurityScope(for: session)
        let gitStatus = await runner.gitStatus(session: session)
        await persistToolEvent(gitStatus, sessionID: session.id)
        session.lastKnownGitState = WorkspaceGitState(
            branch: Self.branchName(from: gitStatus.output),
            statusSummary: gitStatus.output.nonEmptyTrimmed ?? gitStatus.summary
        )

        let (xcodeResult, schemes) = await runner.xcodebuildList(session: session)
        await persistToolEvent(xcodeResult, sessionID: session.id)
        if !schemes.isEmpty {
            availableSchemes = schemes
            if var project = session.selectedProject {
                project.schemes = schemes
                session.selectedProject = project
            }
            if session.selectedScheme == nil || !schemes.contains(session.selectedScheme ?? "") {
                session.selectedScheme = schemes.first
            }
        }
        await saveAndReplace(session)
        await refreshGitDiff()
    }

    func refreshGitDiff() async {
        guard let session = selectedSession else { return }
        isRefreshingDiff = true
        defer { isRefreshingDiff = false }
        await beginSecurityScope(for: session)
        let result = await runner.gitDiff(session: session)
        gitDiffText = result.output
    }

    func sendDraft() {
        guard !isSending, let session = selectedSession else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        draft = ""
        isSending = true
        bannerText = nil
        sendTask = Task { [weak self] in
            guard let self else { return }
            await self.beginSecurityScope(for: session)
            let provider = self.provider(for: session)
            let runtime = WorkspaceAgentRuntime(store: self.store, runner: self.runner, provider: provider)
            do {
                let result = try await runtime.runTurn(
                    session: session,
                    userText: text,
                    existingMessages: self.messages
                )
                self.messages.append(contentsOf: result.messages)
                self.toolEvents.append(contentsOf: result.toolResults)
                self.toolEvents.sort { $0.finishedAt > $1.finishedAt }
                self.changeRecords.insert(contentsOf: result.changeRecords, at: 0)
                await self.refreshGitDiff()
            } catch {
                self.bannerText = "LoomX couldn’t finish that request."
                self.draft = text
            }
            self.isSending = false
        }
    }

    func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
    }

    func buildSelectedWorkspace() async {
        guard let session = await selectedSessionReadyForXcodeAction() else { return }
        await beginSecurityScope(for: session)
        let result = await runner.build(session: session)
        await persistToolEvent(result, sessionID: session.id)
    }

    func testSelectedWorkspace() async {
        guard let session = await selectedSessionReadyForXcodeAction() else { return }
        await beginSecurityScope(for: session)
        let result = await runner.test(session: session)
        await persistToolEvent(result, sessionID: session.id)
    }

    func openSelectedWorkspaceInXcode() async {
        guard let session = selectedSession else { return }
        await beginSecurityScope(for: session)
        let result = await runner.openInXcode(session: session)
        await persistToolEvent(result, sessionID: session.id)
    }

    private func loadSelectedSessionDetails() async {
        guard let session = selectedSession else {
            messages = []
            toolEvents = []
            changeRecords = []
            availableProjects = []
            availableSchemes = []
            gitDiffText = ""
            destinationDraft = ""
            return
        }

        await beginSecurityScope(for: session)
        availableProjects = WorkspaceProjectDetector.detectProjects(in: session.rootURL)
        availableSchemes = session.selectedProject?.schemes ?? []
        destinationDraft = session.selectedDestination ?? ""
        messages = Self.visibleChatMessages(from: (try? await store.loadMessages(sessionID: session.id)) ?? [])
        toolEvents = ((try? await store.loadToolEvents(sessionID: session.id)) ?? []).sorted { $0.finishedAt > $1.finishedAt }
        changeRecords = (try? await store.loadChangeRecords(sessionID: session.id)) ?? []
        if session.selectedProject != nil, session.selectedScheme == nil {
            await runReadinessCheck()
        } else {
            await refreshGitDiff()
        }
    }

    private func saveAndReplace(_ session: WorkspaceSession) async {
        do {
            try await store.saveSession(session)
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            }
            bannerText = nil
        } catch {
            bannerText = "Loom couldn’t save LoomX settings."
        }
    }

    private func persistToolEvent(_ result: DeveloperToolResult, sessionID: UUID) async {
        toolEvents.insert(result, at: 0)
        do {
            try await store.appendToolEvent(result, sessionID: sessionID)
        } catch {
            bannerText = "Loom couldn’t save a tool result."
        }
    }

    private func selectedSessionReadyForXcodeAction() async -> WorkspaceSession? {
        guard let session = selectedSession else { return nil }
        guard session.selectedScheme == nil else { return session }
        await runReadinessCheck()
        return selectedSession
    }

    private func provider(for session: WorkspaceSession) -> any WorkspaceAgentProviding {
        switch session.providerMode {
        case .localOllama:
            return LocalOllamaWorkspaceAgentProvider(
                modelTag: defaults.string(forKey: LoomPreferenceKeys.activeModelTag),
                chatClient: OllamaChatClient()
            )
        case .cloud:
            return CloudWorkspaceAgentProvider()
        }
    }

    private func beginSecurityScope(for session: WorkspaceSession) async {
        guard activeSecurityScopedRoots[session.id] == nil,
              let bookmarkData = session.rootBookmarkData else {
            return
        }

        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            _ = url.startAccessingSecurityScopedResource()
            activeSecurityScopedRoots[session.id] = url
        }
    }

    private static func branchName(from status: String) -> String? {
        guard let firstLine = status.split(separator: "\n").first,
              firstLine.hasPrefix("## ") else {
            return nil
        }
        let branch = firstLine.dropFirst(3).split(separator: ".").first.map(String.init)
        return branch?.nonEmptyTrimmed
    }

    private static func visibleChatMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { message in
            switch message.role {
            case .assistant, .user:
                return true
            case .system, .tool:
                return false
            }
        }
    }
}

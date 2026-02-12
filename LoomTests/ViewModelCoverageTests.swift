import Foundation
import Testing
@testable import Loom

private enum StubFailure: Error, Sendable {
    case failed
}

private actor StubOllamaClient: OllamaStatusProviding {
    var diagnosis: OllamaDiagnosis
    var modelsResult: Result<[OllamaModel], StubFailure>
    var deleteResult: Result<Void, StubFailure>
    var pullResult: Result<Void, StubFailure>
    var deleteThrownError: (any Error)?
    var pullThrownError: (any Error)?
    var pullProgressEvents: [PullProgress]
    var pullWaitsForCancellation: Bool
    var pullCompletionDelay: Duration?
    private var deletedModelNames: [String] = []
    private var pulledModelNames: [String] = []

    init(
        diagnosis: OllamaDiagnosis,
        modelsResult: Result<[OllamaModel], StubFailure> = .success([]),
        deleteResult: Result<Void, StubFailure> = .success(()),
        pullResult: Result<Void, StubFailure> = .success(()),
        deleteThrownError: (any Error)? = nil,
        pullThrownError: (any Error)? = nil,
        pullProgressEvents: [PullProgress] = [PullProgress(status: "Pulling manifest", completed: nil, total: nil)],
        pullWaitsForCancellation: Bool = false,
        pullCompletionDelay: Duration? = nil
    ) {
        self.diagnosis = diagnosis
        self.modelsResult = modelsResult
        self.deleteResult = deleteResult
        self.pullResult = pullResult
        self.deleteThrownError = deleteThrownError
        self.pullThrownError = pullThrownError
        self.pullProgressEvents = pullProgressEvents
        self.pullWaitsForCancellation = pullWaitsForCancellation
        self.pullCompletionDelay = pullCompletionDelay
    }

    func diagnose() async -> OllamaDiagnosis {
        diagnosis
    }

    func listModels() async throws -> [OllamaModel] {
        try modelsResult.get()
    }

    func deleteModel(name: String) async throws {
        deletedModelNames.append(name)
        if let deleteThrownError {
            throw deleteThrownError
        }
        try deleteResult.get()
    }

    func pullModel(name: String, onProgress: @Sendable (PullProgress) -> Void) async throws {
        pulledModelNames.append(name)

        for progress in pullProgressEvents {
            onProgress(progress)
        }

        if pullWaitsForCancellation {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
            }
            throw CancellationError()
        }

        if let pullCompletionDelay {
            try? await Task.sleep(for: pullCompletionDelay)
        }

        if let pullThrownError {
            throw pullThrownError
        }

        try pullResult.get()
    }

    func readDeletedModelNames() -> [String] {
        deletedModelNames
    }

    func readPulledModelNames() -> [String] {
        pulledModelNames
    }
}

private actor ScriptedChatClient: OllamaChatStreaming {
    enum Step: Sendable {
        case complete([String])
        case fail([String], OllamaChatClient.StreamError)
        case waitForCancellation([String])
    }

    private var steps: [Step]

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func streamChat(
        model: String,
        messages: [ChatMessage],
        onDelta: @Sendable (String) async -> Void
    ) async throws {
        guard !steps.isEmpty else { return }
        let step = steps.removeFirst()

        switch step {
        case .complete(let deltas):
            for delta in deltas {
                await onDelta(delta)
            }

        case .fail(let deltas, let error):
            for delta in deltas {
                await onDelta(delta)
            }
            throw error

        case .waitForCancellation(let deltas):
            for delta in deltas {
                await onDelta(delta)
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
            }
            throw CancellationError()
        }
    }
}

private actor ActivityCounter {
    private var count: Int = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private func makeDiagnosis(isInstalled: Bool, isRunning: Bool) -> OllamaDiagnosis {
    OllamaDiagnosis(
        isInstalled: isInstalled,
        isRunning: isRunning,
        reachableBaseURL: isRunning ? URL(string: "http://localhost:11434") : nil,
        summary: isRunning ? "Ready" : (isInstalled ? "Ollama is installed but not running" : "Ollama is not installed yet"),
        nextStep: isRunning ? .ready : (isInstalled ? .startOllama : .installOllama)
    )
}

private func cleanupSessionFolder(id: UUID) {
    guard let folder = try? LoomPaths.sessionFolder(for: id) else { return }
    guard FileManager.default.fileExists(atPath: folder.path) else { return }
    try? FileManager.default.removeItem(at: folder)
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while !condition() && clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
private func clearModelSelectionPreference() {
    UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.activeModelTag)
}

@MainActor
private func sendDraftWithModelRetry(
    _ viewModel: SessionMessagesViewModel,
    draft: String,
    modelTag: String = "llama3",
    maxAttempts: Int = 3
) async {
    viewModel.draft = draft

    for _ in 0..<maxAttempts {
        UserDefaults.standard.set(modelTag, forKey: LoomPreferenceKeys.activeModelTag)
        await viewModel.sendDraft()

        if viewModel.banner?.action != .browseModels {
            return
        }
    }
}

@Suite(.serialized)
struct StatusViewModelCoverageTests {
    @Test
    @MainActor
    func refreshBuildsSnapshotWhenReachable() async {
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: "llama3"), OllamaModel(tag: "phi4")])
        )
        let vm = StatusViewModel(client: client)

        await vm.refresh()

        #expect(vm.snapshot.ollamaReachable)
        #expect(vm.snapshot.installedModelCount == 2)
        #expect(vm.ollamaActionTitle == "Ollama is running")
    }

    @Test
    @MainActor
    func ollamaActionTitleShowsInstallWhenNotInstalled() async {
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: false, isRunning: false)
        )
        let vm = StatusViewModel(client: client)

        await vm.refresh()

        #expect(vm.ollamaActionTitle == "Install Ollama…")
    }

    @Test
    @MainActor
    func ollamaActionTitleShowsStartWhenInstalledButStopped() async {
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: false)
        )
        let vm = StatusViewModel(client: client)

        await vm.refresh()

        #expect(vm.ollamaActionTitle == "Start Ollama")
    }

    @Test
    @MainActor
    func refreshWhenOllamaIsNotRunningClearsModels() async {
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: false),
            modelsResult: .success([OllamaModel(tag: "llama3")])
        )
        let vm = ModelsViewModel(client: client)
        vm.models = [OllamaModel(tag: "stale")]

        await vm.refresh()

        #expect(vm.isInstalled)
        #expect(!vm.isRunning)
        #expect(vm.models.isEmpty)
        #expect(vm.lastRefreshAt != nil)
    }

    @Test
    @MainActor
    func refreshLoadsModels() async {
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: "llama3"), OllamaModel(tag: "phi4")])
        )
        let vm = ModelsViewModel(client: client)

        await vm.refresh()

        #expect(vm.models.count == 2)
    }

    @Test
    @MainActor
    func refreshHandlesListModelsFailure() async {
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .failure(.failed)
        )
        let vm = ModelsViewModel(client: client)
        vm.models = [OllamaModel(tag: "existing")]

        await vm.refresh()

        #expect(vm.models.isEmpty)
        #expect(vm.lastRefreshAt != nil)
    }

    @Test
    @MainActor
    func requestDeleteBlocksDeletingActiveModel() async {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }
        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: "llama3"), OllamaModel(tag: "phi4")])
        )
        let vm = ModelsViewModel(client: client)
        await vm.refresh()

        vm.requestDelete(modelTag: "llama3")

        #expect(vm.selectedModelToDelete == nil)
        #expect(vm.deleteAlertMessage == "This model is currently active. Choose another model before deleting.")
        #expect(await client.readDeletedModelNames().isEmpty)
    }

    @Test
    @MainActor
    func confirmDeleteRemovesNonActiveModel() async {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }
        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: "llama3"), OllamaModel(tag: "phi4")]),
            deleteResult: .success(())
        )
        let vm = ModelsViewModel(client: client)
        await vm.refresh()
        vm.requestDelete(modelTag: "phi4")

        let didDelete = await vm.confirmDelete()

        #expect(didDelete)
        #expect(vm.selectedModelToDelete == nil)
        #expect(vm.deleteAlertMessage == nil)
        #expect(await client.readDeletedModelNames() == ["phi4"])
    }

    @Test
    @MainActor
    func confirmDeleteSurfacesDeleteServerMessage() async {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }
        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: "llama3"), OllamaModel(tag: "phi4")]),
            deleteThrownError: DeleteModelError.httpStatus(500, "model not found")
        )
        let vm = ModelsViewModel(client: client)
        await vm.refresh()
        vm.requestDelete(modelTag: "phi4")

        let didDelete = await vm.confirmDelete()

        #expect(!didDelete)
        #expect(vm.deleteAlertMessage == "model not found")
    }

    @Test
    @MainActor
    func beginInstallDoesNothingForAlreadyInstalledModel() async {
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: "qwen2.5:7b")])
        )
        let vm = ModelsViewModel(client: client)
        await vm.refresh()

        vm.beginInstall(tag: "qwen2.5:7b")

        #expect(vm.installingTag == nil)
        #expect(await client.readPulledModelNames().isEmpty)
    }

    @Test
    @MainActor
    func activeModelTagSetterTrimsAndClearsValue() async {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        let vm = ModelsViewModel(client: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)))
        vm.activeModelTag = "  llama3.2:3b  "
        #expect(vm.activeModelTag == "llama3.2:3b")

        vm.activeModelTag = "   "
        #expect(vm.activeModelTag == nil)
    }

    @Test
    @MainActor
    func beginInstallOnLowDiskRequiresConfirmationBeforePull() async {
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            pullWaitsForCancellation: true
        )
        let vm = ModelsViewModel(client: client)
        vm.diskSpaceSnapshot = DiskSpaceSnapshot(totalBytes: 100, availableBytes: 5)

        vm.beginInstall(tag: "phi4:latest")

        #expect(vm.pendingLowSpaceInstallTag == "phi4:latest")
        #expect(vm.installingTag == nil)
        #expect(await client.readPulledModelNames().isEmpty)
    }

    @Test
    @MainActor
    func continueInstallAfterLowSpaceConfirmationStartsInstall() async {
        let tag = "phi4:latest"
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            pullWaitsForCancellation: true
        )
        let vm = ModelsViewModel(client: client)
        vm.diskSpaceSnapshot = DiskSpaceSnapshot(totalBytes: 100, availableBytes: 5)

        vm.beginInstall(tag: tag)
        vm.continueInstallAfterLowSpaceConfirmation()

        await waitUntil { vm.installingTag == tag }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while await client.readPulledModelNames() != [tag], clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(vm.pendingLowSpaceInstallTag == nil)
        #expect(await client.readPulledModelNames() == [tag])

        vm.cancelInstall()
        await waitUntil { vm.installingTag == nil }
    }

    @Test
    @MainActor
    func beginInstallTracksProgressAndClearsWhenDone() async {
        let tag = "phi4:latest"
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            pullResult: .success(()),
            pullProgressEvents: [
                PullProgress(status: "Downloading", completed: 50, total: 100)
            ],
            pullCompletionDelay: .milliseconds(250)
        )
        let vm = ModelsViewModel(client: client)

        vm.beginInstall(tag: tag)
        #expect(vm.installingTag == tag)

        await waitUntil {
            vm.pullProgress(for: tag)?.status == "Downloading"
        }

        #expect(vm.pullProgress(for: tag)?.fraction == 0.5)
        #expect(await client.readPulledModelNames() == [tag])

        await waitUntil {
            vm.installingTag == nil
        }

        #expect(vm.pullProgress(for: tag) == nil)
    }

    @Test
    @MainActor
    func cancelInstallClearsInstallState() async {
        let tag = "mistral:7b"
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            pullWaitsForCancellation: true
        )
        let vm = ModelsViewModel(client: client)

        vm.beginInstall(tag: tag)
        await waitUntil { vm.installingTag == tag }

        vm.cancelInstall()

        await waitUntil { vm.installingTag == nil }

        #expect(vm.pullProgress(for: tag) == nil)
        #expect(vm.installErrorMessage == nil)
        #expect(await client.readPulledModelNames() == [tag])
    }

    @Test
    @MainActor
    func beginInstallSurfacesPullErrorMessage() async {
        let tag = "qwen2.5:7b"
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            pullThrownError: PullModelError.httpStatus(500, "download failed")
        )
        let vm = ModelsViewModel(client: client)

        vm.beginInstall(tag: tag)

        await waitUntil { vm.installingTag == nil }

        #expect(vm.installErrorMessage == "download failed")
    }

    @Test
    @MainActor
    func confirmDeleteShowsNetworkMessageWhenOllamaUnreachable() async {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }
        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: "llama3"), OllamaModel(tag: "phi4")]),
            deleteThrownError: URLError(.cannotConnectToHost)
        )
        let vm = ModelsViewModel(client: client)
        await vm.refresh()
        vm.requestDelete(modelTag: "phi4")

        let didDelete = await vm.confirmDelete()

        #expect(!didDelete)
        #expect(vm.deleteAlertMessage == "Loom can’t reach Ollama. Start it to continue.")
    }
}

@Suite(.serialized)
struct SessionMessagesViewModelCoverageTests {
    @Test
    @MainActor
    func sendDraftShowsOllamaNotRunningBanner() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Needs Ollama")
        defer { cleanupSessionFolder(id: session.id) }

        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: false)),
            chatClient: ScriptedChatClient([.complete(["ignored"])])
        )

        await sendDraftWithModelRetry(vm, draft: "Hello")

        #expect(vm.banner != nil)
        #expect(vm.messages.isEmpty)
        #expect(!vm.isGenerating)
    }

    @Test
    @MainActor
    func sendDraftStreamsAndPersistsAssistantMessage() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Stream Success")
        defer { cleanupSessionFolder(id: session.id) }

        let activityCounter = ActivityCounter()
        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            onActivity: { await activityCounter.increment() },
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: ScriptedChatClient([.complete(["Hi", " there"])])
        )

        await sendDraftWithModelRetry(vm, draft: "Hello")
        await waitUntil { !vm.isGenerating }

        #expect(vm.messages.count == 2)
        if vm.messages.count == 2 {
            #expect(vm.messages[0].role == .user)
            #expect(vm.messages[1].role == .assistant)
            #expect(vm.messages[1].content == "Hi there")
        }

        let persisted = try await store.loadMessages(sessionID: session.id)
        #expect(persisted.count == 2)
        if persisted.count == 2 {
            #expect(persisted[1].content == "Hi there")
        }
        #expect(await activityCounter.value() == 2)
    }

    @Test
    @MainActor
    func stopGeneratingPersistsPartialAssistantContent() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Cancel Stream")
        defer { cleanupSessionFolder(id: session.id) }

        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: ScriptedChatClient([.waitForCancellation(["Partial"])])
        )

        await sendDraftWithModelRetry(vm, draft: "Hello")
        await waitUntil { vm.messages.count == 2 && vm.messages[1].content == "Partial" }
        vm.stopGenerating()
        await waitUntil { !vm.isGenerating }

        let persisted = try await store.loadMessages(sessionID: session.id)
        #expect(persisted.count == 2)
        if persisted.count == 2 {
            #expect(persisted[1].content == "Partial")
        }
    }

    @Test
    @MainActor
    func retryLastReplyReplacesFailedPlaceholderAndStreamsAgain() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Retry Flow")
        defer { cleanupSessionFolder(id: session.id) }

        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: ScriptedChatClient([
                .fail(["Oops"], .serverError("Connection lost.")),
                .complete(["Recovered"])
            ])
        )

        await sendDraftWithModelRetry(vm, draft: "Hello")
        await waitUntil { !vm.isGenerating }

        #expect(vm.banner?.action == .retryLastReply)
        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.content == "Oops")

        await vm.retryLastReply()
        await waitUntil { !vm.isGenerating }

        #expect(vm.banner == nil)
        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.content == "Recovered")
    }

    @Test
    @MainActor
    func sendDraftKeepsDraftWhenUserMessagePersistenceFails() async {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let missingSessionID = UUID()

        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: missingSessionID,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: ScriptedChatClient([.complete(["unused"])])
        )

        await sendDraftWithModelRetry(vm, draft: "Keep me")

        #expect(vm.draft == "Keep me")
        #expect(vm.banner?.text == "Loom couldn’t save your message. Try again.")
        #expect(vm.messages.isEmpty)
        #expect(!vm.isGenerating)
    }
}

@Suite(.serialized)
struct RootViewModelCoverageTests {
    @Test
    @MainActor
    func loadFiltersAndSelectsMostRecentSession() async throws {
        let store = SessionStore()
        let uniqueTag = "design-\(UUID().uuidString)"
        let first = try await store.createSession(title: "Design Notes")
        let second = try await store.createSession(title: "Roadmap")
        defer {
            cleanupSessionFolder(id: first.id)
            cleanupSessionFolder(id: second.id)
        }

        var firstMeta = first.metadata
        firstMeta.tags = [uniqueTag, "ux"]
        firstMeta.updatedAt = Date(timeIntervalSinceNow: -3600)
        try await store.updateMetadata(firstMeta, for: first.id)

        var secondMeta = second.metadata
        secondMeta.tags = ["planning"]
        secondMeta.updatedAt = Date()
        try await store.updateMetadata(secondMeta, for: second.id)

        let vm = RootViewModel(store: store)
        await vm.load()

        vm.searchQuery = uniqueTag
        #expect(vm.filteredSessions.contains(where: { $0.id == first.id }))
        #expect(!vm.filteredSessions.contains(where: { $0.id == second.id }))
    }

    @Test
    @MainActor
    func renamePinAndTagsPersistThroughStore() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Original")
        defer { cleanupSessionFolder(id: session.id) }

        let vm = RootViewModel(store: store)
        await vm.load()
        vm.selectedSessionID = session.id

        await vm.renameSession(id: session.id, to: "Renamed")
        await vm.togglePinned(id: session.id)
        await vm.updateTags(id: session.id, tags: ["alpha", "beta"])
        await vm.load()

        let updated = vm.session(for: session.id)
        #expect(updated?.metadata.title == "Renamed")
        #expect(updated?.metadata.isPinned == true)
        #expect(updated?.metadata.tags == ["alpha", "beta"])
    }

    @Test
    @MainActor
    func deleteSelectedRemovesSessionAndKeepsSelectionValid() async throws {
        let store = SessionStore()
        let first = try await store.createSession(title: "First")
        let second = try await store.createSession(title: "Second")
        defer {
            cleanupSessionFolder(id: first.id)
            cleanupSessionFolder(id: second.id)
        }

        let vm = RootViewModel(store: store)
        await vm.load()
        vm.selectedSessionID = first.id

        await vm.deleteSelected()

        #expect(vm.session(for: first.id) == nil)
        #expect(vm.selectedSessionID != first.id)

        let firstFolder = try LoomPaths.sessionFolder(for: first.id)
        #expect(!FileManager.default.fileExists(atPath: firstFolder.path))
    }
}

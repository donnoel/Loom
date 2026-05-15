import Foundation
import Testing
@testable import Loom

private enum StubFailure: Error, Sendable {
    case failed
}

private actor StubOllamaClient: OllamaStatusProviding {
    var diagnosis: OllamaDiagnosis
    var diagnosisDelay: Duration?
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
        diagnosisDelay: Duration? = nil,
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
        self.diagnosisDelay = diagnosisDelay
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
        if let diagnosisDelay {
            try? await Task.sleep(for: diagnosisDelay)
        }
        return diagnosis
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
    struct RecordedRequest: Sendable, Equatable {
        let model: String
        let messages: [ChatMessage]
    }

    enum Step: Sendable {
        case complete([String])
        case fail([String], OllamaChatClient.StreamError)
        case waitForCancellation([String])
    }

    private var steps: [Step]
    private var recordedRequests: [RecordedRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func streamChat(
        model: String,
        messages: [ChatMessage],
        onDelta: @Sendable (String) async -> Void
    ) async throws {
        recordedRequests.append(RecordedRequest(model: model, messages: messages))
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

    func readRecordedRequests() -> [RecordedRequest] {
        recordedRequests
    }
}

private actor StubAIChatbotStatusClient: AIChatbotStatusProviding {
    var snapshots: [AIChatbotServiceSnapshot]

    init(snapshots: [AIChatbotServiceSnapshot]) {
        self.snapshots = snapshots
    }

    func placeholderSnapshots() -> [AIChatbotServiceSnapshot] {
        snapshots
    }

    func fetchStatuses() async -> [AIChatbotServiceSnapshot] {
        snapshots
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

private func fixedDate(_ iso8601: String) -> Date {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: iso8601) else {
        Issue.record("Failed to build fixed test date: \(iso8601)")
        return Date(timeIntervalSince1970: 0)
    }
    return date
}

private func makeAIServiceSnapshot(
    id: String,
    name: String,
    state: AIChatbotOperationalState = .operational
) -> AIChatbotServiceSnapshot {
    AIChatbotServiceSnapshot(
        id: id,
        name: name,
        homepageURL: URL(string: "https://example.com/\(id)")!,
        statusPageURL: URL(string: "https://status.example.com/\(id)")!,
        state: state,
        summary: state.label,
        knownIssues: [],
        checkedAt: fixedDate("2026-02-14T00:00:00Z")
    )
}

private func cleanupSessionFolder(id: UUID) {
    UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.sessionLastStreamModelKey(for: id))
    guard let folder = try? LoomPaths.sessionFolder(for: id) else { return }
    guard FileManager.default.fileExists(atPath: folder.path) else { return }
    try? FileManager.default.removeItem(at: folder)
}

private func makeTemporaryTextFile(contents: String, fileName: String) throws -> URL {
    try makeTemporaryFile(data: Data(contents.utf8), fileName: fileName)
}

private func makeTemporaryFile(data: Data, fileName: String) throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let folder = root.appendingPathComponent("loom-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let fileURL = folder.appendingPathComponent(fileName, isDirectory: false)
    try data.write(to: fileURL, options: [.atomic])
    return fileURL
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
private func clearModelLibraryOrderPreference() {
    UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.modelLibraryOrder)
}

@MainActor
private func clearComposerContextPreferences() {
    UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.composerHistoryContextLevel)
    UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.composerFileContextLevel)
}

@MainActor
private func clearAIStatusOrderPreference() {
    UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.aiStatusServiceOrder)
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
    func displayedReadinessStartsCheckingUntilFirstRefreshCompletes() async {
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: false)
        )
        let vm = StatusViewModel(client: client)

        #expect(vm.displayedReadiness == .checking)

        await vm.refresh()

        #expect(vm.displayedReadiness == .notReady)
    }

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
    func refreshRecordsRecentRuntimeHealth() async {
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: "llama3")])
        )
        let vm = StatusViewModel(client: client)

        await vm.refresh()

        #expect(vm.recentRuntimeHealth.count == 1)
        #expect(vm.recentRuntimeHealth.first?.ollamaReachable == true)
        #expect(vm.recentRuntimeHealth.first?.installedModelCount == 1)
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
    func moveInstalledModelPersistsOrderAcrossRefreshes() async {
        clearModelLibraryOrderPreference()
        defer { clearModelLibraryOrderPreference() }

        let alpha = "alpha:latest"
        let bravo = "bravo:latest"
        let charlie = "charlie:latest"
        let listedModels = [
            OllamaModel(tag: alpha),
            OllamaModel(tag: bravo),
            OllamaModel(tag: charlie)
        ]
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success(listedModels)
        )

        let vm = ModelsViewModel(client: client)
        await vm.refresh()
        vm.moveInstalledModel(tag: charlie, before: alpha)

        #expect(vm.models.map(\.tag) == [charlie, alpha, bravo])
        #expect((UserDefaults.standard.array(forKey: LoomPreferenceKeys.modelLibraryOrder) as? [String]) == [charlie, alpha, bravo])

        let reloadedVM = ModelsViewModel(client: client)
        await reloadedVM.refresh()

        #expect(reloadedVM.models.map(\.tag) == [charlie, alpha, bravo])
    }

    @Test
    @MainActor
    func refreshAppliesStoredOrderAndPrunesMissingTags() async {
        clearModelLibraryOrderPreference()
        defer { clearModelLibraryOrderPreference() }

        UserDefaults.standard.set(
            ["missing:latest", "phi4:latest", "llama3:latest"],
            forKey: LoomPreferenceKeys.modelLibraryOrder
        )

        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: "llama3:latest"), OllamaModel(tag: "phi4:latest")])
        )
        let vm = ModelsViewModel(client: client)

        await vm.refresh()

        #expect(vm.models.map(\.tag) == ["phi4:latest", "llama3:latest"])
        #expect((UserDefaults.standard.array(forKey: LoomPreferenceKeys.modelLibraryOrder) as? [String]) == ["phi4:latest", "llama3:latest"])
    }

    @Test
    @MainActor
    func moveAIStatusServicePersistsOrderAcrossRefreshes() async {
        clearAIStatusOrderPreference()
        defer { clearAIStatusOrderPreference() }

        let snapshots = [
            makeAIServiceSnapshot(id: "chatgpt", name: "ChatGPT"),
            makeAIServiceSnapshot(id: "claude", name: "Claude"),
            makeAIServiceSnapshot(id: "grok", name: "Grok")
        ]

        let client = StubAIChatbotStatusClient(snapshots: snapshots)
        let vm = AIChatbotStatusViewModel(client: client)

        await vm.refresh()
        vm.moveService(id: "grok", before: "chatgpt")

        #expect(vm.services.map(\.id) == ["grok", "chatgpt", "claude"])
        #expect((UserDefaults.standard.array(forKey: LoomPreferenceKeys.aiStatusServiceOrder) as? [String]) == ["grok", "chatgpt", "claude"])

        let reloadedVM = AIChatbotStatusViewModel(client: client)
        await reloadedVM.refresh()

        #expect(reloadedVM.services.map(\.id) == ["grok", "chatgpt", "claude"])
    }

    @Test
    @MainActor
    func refreshAIStatusAppliesStoredOrderAndPrunesMissingIDs() async {
        clearAIStatusOrderPreference()
        defer { clearAIStatusOrderPreference() }

        UserDefaults.standard.set(
            ["missing", "grok", "chatgpt"],
            forKey: LoomPreferenceKeys.aiStatusServiceOrder
        )

        let snapshots = [
            makeAIServiceSnapshot(id: "chatgpt", name: "ChatGPT"),
            makeAIServiceSnapshot(id: "claude", name: "Claude"),
            makeAIServiceSnapshot(id: "grok", name: "Grok")
        ]
        let vm = AIChatbotStatusViewModel(client: StubAIChatbotStatusClient(snapshots: snapshots))

        await vm.refresh()

        #expect(vm.services.map(\.id) == ["grok", "chatgpt", "claude"])
        #expect((UserDefaults.standard.array(forKey: LoomPreferenceKeys.aiStatusServiceOrder) as? [String]) == ["grok", "chatgpt", "claude"])
    }

    @Test
    @MainActor
    func totalInstalledSizeTextSumsInstalledModelSizes() {
        let vm = ModelsViewModel(client: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)))
        vm.models = [
            OllamaModel(tag: "llama3", sizeBytes: 1_024),
            OllamaModel(tag: "phi4", sizeBytes: 2_048),
            OllamaModel(tag: "qwen2.5", sizeBytes: nil)
        ]

        #expect(vm.totalInstalledSizeText == DiskSpaceSnapshot.formattedBytes(3_072))
    }

    @Test
    @MainActor
    func totalInstalledSizeTextClampsWhenByteSumOverflows() {
        let vm = ModelsViewModel(client: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)))
        vm.models = [
            OllamaModel(tag: "huge-1", sizeBytes: Int64.max),
            OllamaModel(tag: "huge-2", sizeBytes: 1)
        ]

        #expect(vm.totalInstalledSizeText == DiskSpaceSnapshot.formattedBytes(Int64.max))
    }

    @Test
    @MainActor
    func installedModelBestForTextUsesCatalogHighlights() {
        let vm = ModelsViewModel(client: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)))
        let model = OllamaModel(tag: "qwen3:8b")

        #expect(vm.installedModelBestForText(for: model) == "Good for: Coding help, Reasoning.")
    }

    @Test
    @MainActor
    func installedModelBestForTextFallsBackForUnknownModel() {
        let vm = ModelsViewModel(client: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)))
        let model = OllamaModel(tag: "custom-model:latest")

        #expect(vm.installedModelBestForText(for: model) == "Good for everyday questions, writing help, and summaries.")
    }

    @Test
    @MainActor
    func installedModelCompanyCountryTextUsesCatalogData() {
        let vm = ModelsViewModel(client: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)))
        let model = OllamaModel(tag: "qwen3:8b")

        #expect(vm.installedModelCompanyCountryText(for: model) == "Made by Qwen in China.")
    }

    @Test
    @MainActor
    func installedModelCompanyCountryTextFallsBackForUnknownModel() {
        let vm = ModelsViewModel(client: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)))
        let model = OllamaModel(tag: "custom-model:latest")

        #expect(vm.installedModelCompanyCountryText(for: model) == "Maker and country details aren’t listed for this model.")
    }

    @Test
    @MainActor
    func installedModelLastTrainedTextUsesCatalogData() {
        let vm = ModelsViewModel(client: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)))
        let model = OllamaModel(tag: "qwen3:8b")

        #expect(vm.installedModelLastTrainedText(for: model) == "Last trained: 2025.")
    }

    @Test
    @MainActor
    func installedModelLastTrainedTextFallsBackForUnknownModel() {
        let vm = ModelsViewModel(client: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)))
        let model = OllamaModel(tag: "custom-model:latest")

        #expect(vm.installedModelLastTrainedText(for: model) == "Last trained date isn’t listed for this model.")
    }

    @Test
    @MainActor
    func unverifiedModelShowsUpdateStatus() async {
        let tag = "llama3"
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: tag)])
        )
        let vm = ModelsViewModel(client: client)
        await vm.refresh()

        #expect(!vm.isModelCurrent(tag: tag))
        #expect(vm.updateStatusText(for: tag) == "Update")
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
    func updateInstalledModelPullsAndMarksModelChecked() async {
        let tag = "qwen2.5:7b"
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: tag)]),
            pullResult: .success(())
        )
        let vm = ModelsViewModel(client: client)
        await vm.refresh()

        let didUpdate = await vm.updateInstalledModel(tag: tag)

        #expect(didUpdate)
        #expect(await client.readPulledModelNames() == [tag])
        #expect(vm.lastUpdateCheckAt != nil)
        #expect(vm.isModelCurrent(tag: tag))
        #expect(vm.updateStatusText(for: tag) == "Current")
    }

    @Test
    @MainActor
    func checkForUpdatesPullsEachInstalledModel() async {
        let firstTag = "llama3.2:3b"
        let secondTag = "phi4:latest"
        let client = StubOllamaClient(
            diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
            modelsResult: .success([OllamaModel(tag: firstTag), OllamaModel(tag: secondTag)]),
            pullResult: .success(())
        )
        let vm = ModelsViewModel(client: client)
        await vm.refresh()

        await vm.checkForUpdates()

        let pulled = await client.readPulledModelNames()
        #expect(Set(pulled) == Set([firstTag, secondTag]))
        #expect(pulled.count == 2)
        #expect(vm.lastUpdateCheckAt != nil)
        #expect(vm.isModelCurrent(tag: firstTag))
        #expect(vm.isModelCurrent(tag: secondTag))
        #expect(vm.updateStatusText(for: firstTag) == "Current")
        #expect(vm.updateStatusText(for: secondTag) == "Current")
        #expect(!vm.isCheckingUpdates)
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
    func confirmDeleteUsesExplicitTagWhenSelectionWasCleared() async {
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

        // Mirrors confirmationDialog dismissal clearing selection state before the button task runs.
        vm.cancelDeleteRequest()
        let didDelete = await vm.confirmDelete(modelTag: "phi4")

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
    func loadRefreshesInstalledModelsAndRespectsPreferredOrder() async throws {
        clearModelSelectionPreference()
        clearModelLibraryOrderPreference()
        defer {
            clearModelSelectionPreference()
            clearModelLibraryOrderPreference()
        }

        UserDefaults.standard.set(
            ["phi4:latest", "qwen3:8b"],
            forKey: LoomPreferenceKeys.modelLibraryOrder
        )
        UserDefaults.standard.set("qwen3:8b", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Session Model Ordering")
        defer { cleanupSessionFolder(id: session.id) }

        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(
                diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
                modelsResult: .success([
                    OllamaModel(tag: "qwen3:8b"),
                    OllamaModel(tag: "mistral:7b"),
                    OllamaModel(tag: "phi4:latest")
                ])
            ),
            chatClient: ScriptedChatClient([])
        )

        await vm.load()

        #expect(vm.availableModelTags == ["phi4:latest", "qwen3:8b", "mistral:7b"])
        #expect(vm.activeModelSelectionLabel == "Qwen 3 (8B)")
    }

    @Test
    @MainActor
    func activeModelTagSetterTrimsAndClearsValueForSessionPicker() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        let store = SessionStore()
        let session = try await store.createSession(title: "Session Model Picker")
        defer { cleanupSessionFolder(id: session.id) }

        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(
                diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)
            ),
            chatClient: ScriptedChatClient([])
        )

        vm.activeModelTag = "  qwen3:8b  "
        #expect(vm.activeModelTag == "qwen3:8b")
        #expect(
            UserDefaults.standard.string(forKey: LoomPreferenceKeys.activeModelTag) == "qwen3:8b"
        )
        #expect(vm.activeModelSelectionLabel == "Qwen 3 (8B) (Unavailable)")

        vm.activeModelTag = "   "
        #expect(vm.activeModelTag == nil)
        #expect(UserDefaults.standard.string(forKey: LoomPreferenceKeys.activeModelTag) == nil)
        #expect(vm.activeModelSelectionLabel == "Choose Model")
    }

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
    func sendDraftConcurrentCallsSubmitOnlyOnce() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Concurrent Send")
        defer { cleanupSessionFolder(id: session.id) }

        let chatClient = ScriptedChatClient([.complete(["Hi"])])
        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(
                diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
                diagnosisDelay: .milliseconds(120)
            ),
            chatClient: chatClient
        )

        vm.draft = "Hello"

        async let firstSend: Void = vm.sendDraft()
        async let secondSend: Void = vm.sendDraft()
        _ = await (firstSend, secondSend)
        await waitUntil { !vm.isGenerating }

        #expect(vm.messages.count == 2)
        #expect(vm.messages.filter { $0.role == .user }.count == 1)
        #expect(vm.messages.filter { $0.role == .assistant }.count == 1)

        let requests = await chatClient.readRecordedRequests()
        #expect(requests.count == 1)

        let persisted = try await store.loadMessages(sessionID: session.id)
        #expect(persisted.count == 2)
        #expect(persisted.filter { $0.role == .user }.count == 1)
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

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while try await store.loadMessages(sessionID: session.id).count < 2 && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        let persisted = try await store.loadMessages(sessionID: session.id)
        #expect(persisted.count == 2)
        if persisted.count == 2 {
            #expect(persisted[1].content == "Partial")
        }
    }

    @Test
    @MainActor
    func retryLastReplyConcurrentCallsSubmitOnlyOnce() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Concurrent Retry")
        defer { cleanupSessionFolder(id: session.id) }

        let chatClient = ScriptedChatClient([
            .fail(["Partial"], .serverError("Connection lost.")),
            .complete(["Recovered"])
        ])
        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(
                diagnosis: makeDiagnosis(isInstalled: true, isRunning: true),
                diagnosisDelay: .milliseconds(120)
            ),
            chatClient: chatClient
        )

        await sendDraftWithModelRetry(vm, draft: "Hello")
        await waitUntil { !vm.isGenerating }
        #expect(vm.banner?.action == .retryLastReply)

        async let firstRetry: Void = vm.retryLastReply()
        async let secondRetry: Void = vm.retryLastReply()
        _ = await (firstRetry, secondRetry)
        await waitUntil { !vm.isGenerating }

        #expect(vm.banner == nil)
        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.content == "Recovered")

        let requests = await chatClient.readRecordedRequests()
        #expect(requests.count == 2)
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
    func retryLastReplyWithoutContextShowsHelpfulGuidance() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        let store = SessionStore()
        let session = try await store.createSession(title: "Retry Guidance")
        defer { cleanupSessionFolder(id: session.id) }

        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: ScriptedChatClient([.complete(["unused"])])
        )

        await vm.retryLastReply()

        #expect(vm.banner?.text == "There isn’t a previous reply to retry yet.")
        #expect(vm.banner?.actionTitle == nil)
        #expect(vm.banner?.action == nil)
    }

    @Test
    @MainActor
    func sendDraftWhenModelIsUnavailableShowsChooseModelRecovery() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Missing Model Recovery")
        defer { cleanupSessionFolder(id: session.id) }

        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: ScriptedChatClient([.fail([], .serverError("model 'llama3' not found"))])
        )

        vm.draft = "Hello"
        await vm.sendDraft()
        await waitUntil { !vm.isGenerating }

        #expect(vm.banner?.text == "Loom can’t use this model right now. Choose another model.")
        #expect(vm.banner?.actionTitle == "Choose Model")
        #expect(vm.banner?.action == .browseModels)
    }

    @Test
    @MainActor
    func sendDraftWhenModelIsLoadingShowsRetryGuidance() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Model Loading Recovery")
        defer { cleanupSessionFolder(id: session.id) }

        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: ScriptedChatClient([.fail([], .serverError("model is loading"))])
        )

        vm.draft = "Hello"
        await vm.sendDraft()
        await waitUntil { !vm.isGenerating }

        #expect(vm.banner?.text == "That model is still loading. Try again in a moment.")
        #expect(vm.banner?.actionTitle == "Retry")
        #expect(vm.banner?.action == .retryLastReply)
    }

    @Test
    @MainActor
    func sendDraftWithAttachedFileShowsGuidanceWhenModelDoesNotSupportUploads() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Attachment Capability Guard")
        defer { cleanupSessionFolder(id: session.id) }

        let attachmentURL = try makeTemporaryTextFile(contents: "Private project notes.", fileName: "notes.txt")
        defer { try? FileManager.default.removeItem(at: attachmentURL.deletingLastPathComponent()) }

        let chatClient = ScriptedChatClient([.complete(["unused"])])
        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: chatClient,
            catalog: ModelCatalog(all: [
                CatalogModel(
                    id: "llama3",
                    tag: "llama3",
                    displayName: "Llama 3",
                    vendor: "Meta",
                    country: nil,
                    lastTrained: nil,
                    summary: "Test model",
                    bestAt: ["Chat"],
                    approxDownloadBytes: nil,
                    approxDiskBytes: nil,
                    notes: nil,
                    recommended: true,
                    capabilities: CatalogModelCapabilities(
                        speechInput: true,
                        speechOutput: true,
                        fileUploads: false
                    )
                )
            ])
        )

        await vm.importAttachments(from: [attachmentURL])
        vm.draft = "Summarize this file"
        await vm.sendDraft()

        #expect(vm.banner?.text == "This model can’t use uploaded files yet. Choose one with file upload support.")
        #expect(vm.banner?.action == .browseModels)
        #expect(vm.messages.isEmpty)
        #expect((await chatClient.readRecordedRequests()).isEmpty)
    }

    @Test
    @MainActor
    func importAttachmentsShowsTooManyFilesGuidanceWhenLimitExceeded() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Attachment Count Guard")
        defer { cleanupSessionFolder(id: session.id) }

        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: ScriptedChatClient([.complete(["unused"])])
        )

        var attachmentURLs: [URL] = []
        for index in 1...10 {
            let fileName = String(format: "bulk-%02d.txt", index)
            let url = try makeTemporaryTextFile(contents: "Attachment \(index)", fileName: fileName)
            attachmentURLs.append(url)
        }
        defer {
            for url in attachmentURLs {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }

        await vm.importAttachments(from: attachmentURLs)

        #expect(vm.pendingAttachments.count == 8)
        #expect(vm.banner?.text.contains("too many files") == true)
    }

    @Test
    @MainActor
    func importAttachmentsRejectsOversizedPDFWithHelpfulMessage() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Oversized PDF Guard")
        defer { cleanupSessionFolder(id: session.id) }

        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: ScriptedChatClient([.complete(["unused"])])
        )

        let oversizedPDF = try makeTemporaryFile(
            data: Data(repeating: 0x20, count: 5_100_000),
            fileName: "oversized.pdf"
        )
        defer { try? FileManager.default.removeItem(at: oversizedPDF.deletingLastPathComponent()) }

        await vm.importAttachments(from: [oversizedPDF])

        #expect(vm.pendingAttachments.isEmpty)
        #expect(vm.banner?.text.contains("file is too large") == true)
    }

    @Test
    @MainActor
    func sendDraftWithAttachedFileInjectsSystemContextForSupportedModel() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("qwen2.5:7b", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Attachment Context")
        defer { cleanupSessionFolder(id: session.id) }

        let attachmentURL = try makeTemporaryTextFile(
            contents: "Weather station calibration requires daily checks.",
            fileName: "field-notes.txt"
        )
        defer { try? FileManager.default.removeItem(at: attachmentURL.deletingLastPathComponent()) }

        let chatClient = ScriptedChatClient([.complete(["Loaded attachment context"])])
        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: chatClient
        )

        await vm.importAttachments(from: [attachmentURL])
        vm.draft = "What does the file say?"
        await vm.sendDraft()
        await waitUntil { !vm.isGenerating }

        let requests = await chatClient.readRecordedRequests()
        #expect(requests.count == 1)
        #expect(vm.pendingAttachments.isEmpty)

        if let request = requests.first {
            let systemMessages = request.messages.filter { $0.role == .system }
            #expect(systemMessages.count == 1)
            #expect(systemMessages.first?.content.contains("[field-notes.txt]") == true)
            #expect(systemMessages.first?.content.contains("calibration requires daily checks") == true)
        }
    }

    @Test
    @MainActor
    func sendDraftWithLargeAttachmentsTrimsSystemContextToBudget() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        UserDefaults.standard.set("qwen2.5:7b", forKey: LoomPreferenceKeys.activeModelTag)

        let store = SessionStore()
        let session = try await store.createSession(title: "Attachment Context Budget")
        defer { cleanupSessionFolder(id: session.id) }

        let firstURL = try makeTemporaryTextFile(
            contents: String(repeating: "ALPHA ", count: 1_300),
            fileName: "attachment-1.txt"
        )
        let secondURL = try makeTemporaryTextFile(
            contents: String(repeating: "BRAVO ", count: 1_300),
            fileName: "attachment-2.txt"
        )
        let thirdURL = try makeTemporaryTextFile(
            contents: String(repeating: "CHARLIE ", count: 1_300),
            fileName: "attachment-3.txt"
        )
        defer {
            try? FileManager.default.removeItem(at: firstURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: secondURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: thirdURL.deletingLastPathComponent())
        }

        let chatClient = ScriptedChatClient([.complete(["Budgeted attachment context"])])
        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: chatClient
        )

        await vm.importAttachments(from: [firstURL, secondURL, thirdURL])
        vm.draft = "Use all attachments"
        await vm.sendDraft()
        await waitUntil { !vm.isGenerating }

        let requests = await chatClient.readRecordedRequests()
        #expect(requests.count == 1)

        if let request = requests.first {
            let systemMessages = request.messages.filter { $0.role == .system }
            #expect(systemMessages.count == 1)
            #expect(systemMessages.first?.content.contains("[attachment-1.txt]") == true)
            #expect(systemMessages.first?.content.contains("[attachment-2.txt]") == true)
            #expect(systemMessages.first?.content.contains("[attachment-3.txt]") == false)
            #expect(systemMessages.first?.content.contains("ALPHA") == true)
            #expect(systemMessages.first?.content.contains("BRAVO") == true)
            #expect(systemMessages.first?.content.contains("CHARLIE") == false)
            #expect(systemMessages.first?.content.contains("trimmed attachment excerpts") == true)
        }
    }

    @Test
    @MainActor
    func sendDraftAfterModelChangeAndViewReloadUsesUserOnlyContext() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        let store = SessionStore()
        let session = try await store.createSession(title: "Reloaded Model Switch")
        defer { cleanupSessionFolder(id: session.id) }

        let chatClient = ScriptedChatClient([
            .complete(["Old model answer"]),
            .complete(["New model answer"])
        ])
        let ollamaClient = StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true))

        let firstViewModel = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: ollamaClient,
            chatClient: chatClient
        )

        await sendDraftWithModelRetry(firstViewModel, draft: "Question one", modelTag: "llama3")
        await waitUntil { !firstViewModel.isGenerating }

        let reloadedViewModel = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: ollamaClient,
            chatClient: chatClient
        )
        await reloadedViewModel.load()

        await sendDraftWithModelRetry(reloadedViewModel, draft: "Question two", modelTag: "phi4")
        await waitUntil { !reloadedViewModel.isGenerating }

        let requests = await chatClient.readRecordedRequests()
        #expect(requests.count == 2)
        #expect(requests.map(\.model) == ["llama3", "phi4"])

        if requests.count == 2 {
            #expect(requests[1].messages.allSatisfy { $0.role == .user })
            #expect(requests[1].messages.map(\.content) == ["Question one", "Question two"])
        }
    }

    @Test
    @MainActor
    func sendDraftAfterViewReloadWithSameModelKeepsAssistantContext() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        let store = SessionStore()
        let session = try await store.createSession(title: "Reloaded Same Model Context")
        defer { cleanupSessionFolder(id: session.id) }

        let chatClient = ScriptedChatClient([
            .complete(["Old model answer"]),
            .complete(["Follow-up answer"])
        ])
        let ollamaClient = StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true))

        let firstViewModel = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: ollamaClient,
            chatClient: chatClient
        )

        await sendDraftWithModelRetry(firstViewModel, draft: "Question one", modelTag: "llama3")
        await waitUntil { !firstViewModel.isGenerating }

        let reloadedViewModel = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: ollamaClient,
            chatClient: chatClient
        )
        await reloadedViewModel.load()

        await sendDraftWithModelRetry(reloadedViewModel, draft: "Question two", modelTag: "llama3")
        await waitUntil { !reloadedViewModel.isGenerating }

        let requests = await chatClient.readRecordedRequests()
        #expect(requests.count == 2)
        #expect(requests.map(\.model) == ["llama3", "llama3"])

        if requests.count == 2 {
            #expect(requests[1].messages.contains(where: { $0.role == .assistant }))
            #expect(requests[1].messages.map(\.content) == ["Question one", "Old model answer", "Question two"])
        }
    }

    @Test
    @MainActor
    func retryLastReplyAfterModelSwitchUsesUserOnlyContext() async throws {
        clearModelSelectionPreference()
        defer { clearModelSelectionPreference() }

        let store = SessionStore()
        let session = try await store.createSession(title: "Retry Model Switch Context")
        defer { cleanupSessionFolder(id: session.id) }

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)

        let chatClient = ScriptedChatClient([
            .fail(["Old partial"], .serverError("Connection lost.")),
            .complete(["Recovered on new model"])
        ])
        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: chatClient
        )

        await sendDraftWithModelRetry(vm, draft: "Hello", modelTag: "llama3")
        await waitUntil { !vm.isGenerating }
        #expect(vm.banner?.action == .retryLastReply)

        UserDefaults.standard.set("phi4", forKey: LoomPreferenceKeys.activeModelTag)
        await vm.retryLastReply()
        await waitUntil { !vm.isGenerating }

        let requests = await chatClient.readRecordedRequests()
        #expect(requests.count == 2)
        #expect(requests.map(\.model) == ["llama3", "phi4"])

        if requests.count == 2 {
            #expect(requests[1].messages.allSatisfy { $0.role == .user })
            #expect(requests[1].messages.map(\.content) == ["Hello"])
        }
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

    @Test
    @MainActor
    func conciseHistoryContextCapsOutgoingWindow() async throws {
        clearModelSelectionPreference()
        clearComposerContextPreferences()
        defer {
            clearModelSelectionPreference()
            clearComposerContextPreferences()
        }

        let store = SessionStore()
        let session = try await store.createSession(title: "History Limit Test")
        defer { cleanupSessionFolder(id: session.id) }

        for index in 1...10 {
            try await store.appendMessage(
                ChatMessage(role: .user, content: "Question \(index)"),
                sessionID: session.id
            )
            try await store.appendMessage(
                ChatMessage(role: .assistant, content: "Answer \(index)"),
                sessionID: session.id
            )
        }

        let chatClient = ScriptedChatClient([.complete(["ok"])])
        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: chatClient
        )
        await vm.load()
        vm.historyContextLevel = .concise

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)
        vm.draft = "Newest question"
        await vm.sendDraft()
        await waitUntil { !vm.isGenerating }

        let requests = await chatClient.readRecordedRequests()
        #expect(requests.count == 1)
        if let request = requests.first {
            #expect(request.messages.count == 8)
            #expect(request.messages.last?.content == "Newest question")
        }
    }

    @Test
    @MainActor
    func fileContextOffSkipsAttachmentInjection() async throws {
        clearModelSelectionPreference()
        clearComposerContextPreferences()
        defer {
            clearModelSelectionPreference()
            clearComposerContextPreferences()
        }

        let attachmentURL = try makeTemporaryTextFile(contents: "Private roadmap notes", fileName: "notes.txt")
        defer { try? FileManager.default.removeItem(at: attachmentURL.deletingLastPathComponent()) }

        let store = SessionStore()
        let session = try await store.createSession(title: "Attachment Context Off")
        defer { cleanupSessionFolder(id: session.id) }

        let chatClient = ScriptedChatClient([.complete(["done"])])
        let vm = SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            ollamaClient: StubOllamaClient(diagnosis: makeDiagnosis(isInstalled: true, isRunning: true)),
            chatClient: chatClient
        )
        await vm.load()
        vm.fileContextLevel = .off
        await vm.importAttachments(from: [attachmentURL])
        #expect(!vm.pendingAttachments.isEmpty)

        UserDefaults.standard.set("llama3", forKey: LoomPreferenceKeys.activeModelTag)
        vm.draft = "Summarize please"
        await vm.sendDraft()
        await waitUntil { !vm.isGenerating }

        let requests = await chatClient.readRecordedRequests()
        #expect(requests.count == 1)
        if let request = requests.first {
            #expect(!request.messages.contains(where: { $0.role == .system }))
        }
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

    @Test
    @MainActor
    func touchSessionRefreshesInMemoryTitleFromStore() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: Session.Metadata.defaultTitle)
        defer { cleanupSessionFolder(id: session.id) }

        let vm = RootViewModel(store: store)
        await vm.load()
        #expect(vm.session(for: session.id)?.metadata.title == Session.Metadata.defaultTitle)

        try await store.appendMessage(
            ChatMessage(role: .user, content: "Plan my weekend trip", createdAt: Date()),
            sessionID: session.id
        )

        await vm.touchSession(id: session.id)

        #expect(vm.session(for: session.id)?.metadata.title == "Weekend Trip")
    }
}

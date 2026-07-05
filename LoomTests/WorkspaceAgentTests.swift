import Foundation
import Testing
@testable import Loom

private actor ScriptedWorkspaceProvider: WorkspaceAgentProviding {
    private var responses: [WorkspaceAgentProviderResponse]

    init(_ responses: [WorkspaceAgentProviderResponse]) {
        self.responses = responses
    }

    func respond(to request: WorkspaceAgentRequest) async throws -> WorkspaceAgentProviderResponse {
        guard !responses.isEmpty else {
            return WorkspaceAgentProviderResponse(message: "Done.")
        }
        return responses.removeFirst()
    }
}

private actor ScriptedDeveloperToolRunner: DeveloperToolRunning {
    var xcodebuildListCalls = 0

    func readFile(session: WorkspaceSession, relativePath: String) async -> DeveloperToolResult {
        DeveloperToolResult(tool: .readFile, status: .success, summary: "Read file", output: "")
    }

    func search(session: WorkspaceSession, pattern: String) async -> DeveloperToolResult {
        DeveloperToolResult(tool: .search, status: .success, summary: "Searched", output: "")
    }

    func listFiles(session: WorkspaceSession) async -> (DeveloperToolResult, WorkspaceFileList) {
        (
            DeveloperToolResult(tool: .listFiles, status: .success, summary: "Listed files", output: ""),
            WorkspaceFileList(files: [], source: .fileSystem)
        )
    }

    func writeFile(session: WorkspaceSession, relativePath: String, contents: String) async -> DeveloperToolResult {
        DeveloperToolResult(tool: .writeFile, status: .success, summary: "Wrote file", output: "")
    }

    func applyPatch(session: WorkspaceSession, patch: String) async -> DeveloperToolResult {
        DeveloperToolResult(tool: .applyPatch, status: .success, summary: "Applied patch", output: "")
    }

    func gitDiff(session: WorkspaceSession) async -> DeveloperToolResult {
        DeveloperToolResult(tool: .gitDiff, status: .success, summary: "Loaded diff", output: "")
    }

    func gitStatus(session: WorkspaceSession) async -> DeveloperToolResult {
        DeveloperToolResult(tool: .gitStatus, status: .success, summary: "Loaded git status", output: "## main")
    }

    func xcodebuildList(session: WorkspaceSession) async -> (DeveloperToolResult, [String]) {
        xcodebuildListCalls += 1
        return (
            DeveloperToolResult(tool: .xcodebuildList, status: .success, summary: "Loaded Xcode project metadata.", output: ""),
            ["Loom"]
        )
    }

    func build(session: WorkspaceSession) async -> DeveloperToolResult {
        DeveloperToolResult(tool: .build, status: .success, summary: "Built", output: "")
    }

    func test(session: WorkspaceSession) async -> DeveloperToolResult {
        DeveloperToolResult(tool: .test, status: .success, summary: "Tested", output: "")
    }

    func openInXcode(session: WorkspaceSession) async -> DeveloperToolResult {
        DeveloperToolResult(tool: .openInXcode, status: .success, summary: "Opened", output: "")
    }
}

private func makeTemporaryDirectory(prefix: String = "loom-workspace-tests") throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(prefix, isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Workspace Agent")
struct WorkspaceAgentTests {
    @Test
    @MainActor
    func workspaceViewModelRefreshesMissingSchemeOnLoad() async throws {
        let storeRoot = try makeTemporaryDirectory()
        let workspaceRoot = try makeTemporaryDirectory(prefix: "loom-source-workspace")
        let store = WorkspaceStore(workspacesRoot: storeRoot)
        let session = try await store.createSession(
            displayName: "Loom",
            rootURL: workspaceRoot,
            bookmarkData: nil,
            detectedProject: WorkspaceSession.ProjectSelection(kind: .xcodeProject, relativePath: "Loom.xcodeproj")
        )
        let runner = ScriptedDeveloperToolRunner()
        let viewModel = WorkspaceViewModel(
            store: store,
            runner: runner,
            defaults: UserDefaults(suiteName: "workspace-view-model-\(UUID().uuidString)") ?? .standard
        )

        await viewModel.load()

        let xcodebuildListCalls = await runner.xcodebuildListCalls
        #expect(viewModel.selectedSessionID == session.id)
        #expect(viewModel.availableSchemes == ["Loom"])
        #expect(viewModel.selectedSession?.selectedScheme == "Loom")
        #expect(xcodebuildListCalls == 1)
    }

    @Test
    func workspaceStorePersistsMetadataMessagesToolsAndChanges() async throws {
        let storeRoot = try makeTemporaryDirectory()
        let workspaceRoot = try makeTemporaryDirectory(prefix: "loom-source-workspace")
        let store = WorkspaceStore(workspacesRoot: storeRoot)

        var session = try await store.createSession(
            displayName: "Demo App",
            rootURL: workspaceRoot,
            bookmarkData: nil,
            detectedProject: WorkspaceSession.ProjectSelection(kind: .xcodeProject, relativePath: "Demo.xcodeproj")
        )
        session.providerMode = .cloud
        session.selectedScheme = "Demo"
        try await store.saveSession(session)

        try await store.appendMessage(ChatMessage(role: .user, content: "Inspect the app"), sessionID: session.id)
        let toolResult = DeveloperToolResult(tool: .gitStatus, status: .success, summary: "Clean", output: "## main")
        try await store.appendToolEvent(toolResult, sessionID: session.id)
        let change = try await store.saveChangePatch("diff --git a/A.swift b/A.swift", toolResultID: toolResult.id, sessionID: session.id)

        let sessions = try await store.listSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].providerMode == .cloud)
        #expect(sessions[0].selectedScheme == "Demo")

        let messages = try await store.loadMessages(sessionID: session.id)
        #expect(messages.map(\.content) == ["Inspect the app"])

        let tools = try await store.loadToolEvents(sessionID: session.id)
        #expect(tools.first?.summary == "Clean")

        let changes = try await store.loadChangeRecords(sessionID: session.id)
        #expect(changes.first?.id == change.id)
    }

    @Test
    func workspaceIndexerSkipsBuildCachesAndPrefersUsefulTextFiles() async throws {
        let root = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("DerivedData/Build", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("struct App {}".utf8).write(to: root.appendingPathComponent("Sources/App.swift"), options: [.atomic])
        try Data("ignored".utf8).write(to: root.appendingPathComponent("DerivedData/Build/Generated.swift"), options: [.atomic])
        try Data([0, 1, 2]).write(to: root.appendingPathComponent("image.bin"), options: [.atomic])

        let session = WorkspaceSession(displayName: "Fixture", rootPath: root.path)
        let snapshot = await WorkspaceIndexer.snapshot(for: session, runner: DeveloperToolRunner())

        #expect(snapshot.files.contains("Sources/App.swift"))
        #expect(!snapshot.files.contains("DerivedData/Build/Generated.swift"))
        #expect(!snapshot.files.contains("image.bin"))
    }

    @Test
    func developerToolRunnerConstrainsPathsAndSearchesText() async throws {
        let root = try makeTemporaryDirectory()
        let session = WorkspaceSession(displayName: "Fixture", rootPath: root.path)
        let runner = DeveloperToolRunner()

        let write = await runner.writeFile(session: session, relativePath: "Sources/Feature.swift", contents: "let workspaceAgent = true\n")
        #expect(write.status == .success)

        let read = await runner.readFile(session: session, relativePath: "Sources/Feature.swift")
        #expect(read.output.contains("workspaceAgent"))

        let search = await runner.search(session: session, pattern: "workspaceAgent")
        #expect(search.output.contains("Sources/Feature.swift:1"))

        let escaped = await runner.readFile(session: session, relativePath: "../outside.txt")
        #expect(escaped.status == .failure)
    }

    @Test
    func agentRuntimeExecutesTypedToolCallsAndPersistsActivity() async throws {
        let storeRoot = try makeTemporaryDirectory()
        let workspaceRoot = try makeTemporaryDirectory(prefix: "loom-source-workspace")
        let store = WorkspaceStore(workspacesRoot: storeRoot)
        let session = try await store.createSession(
            displayName: "Runtime",
            rootURL: workspaceRoot,
            bookmarkData: nil,
            detectedProject: nil
        )
        let provider = ScriptedWorkspaceProvider([
            WorkspaceAgentProviderResponse(
                message: "I’ll write the note.",
                toolCalls: [
                    WorkspaceAgentToolCall(
                        tool: .writeFile,
                        relativePath: "notes.txt",
                        contents: "workspace agent note"
                    )
                ]
            ),
            WorkspaceAgentProviderResponse(message: "Done.")
        ])
        let runtime = WorkspaceAgentRuntime(store: store, runner: DeveloperToolRunner(), provider: provider)

        let result = try await runtime.runTurn(session: session, userText: "Create a note", existingMessages: [])

        #expect(result.toolResults.map(\.tool) == [.writeFile])
        #expect(try String(contentsOf: workspaceRoot.appendingPathComponent("notes.txt"), encoding: .utf8) == "workspace agent note")
        #expect((try await store.loadToolEvents(sessionID: session.id)).count == 1)
        #expect(!(try await store.loadMessages(sessionID: session.id)).contains { $0.role == .tool })
    }

    @Test
    func agentRuntimeRunsDirectToolIntentBeforeProviderResponse() async throws {
        let storeRoot = try makeTemporaryDirectory()
        let workspaceRoot = try makeTemporaryDirectory(prefix: "loom-source-workspace")
        try Data("struct RootView {}".utf8).write(to: workspaceRoot.appendingPathComponent("RootView.swift"), options: [.atomic])
        let store = WorkspaceStore(workspacesRoot: storeRoot)
        let session = try await store.createSession(
            displayName: "Runtime",
            rootURL: workspaceRoot,
            bookmarkData: nil,
            detectedProject: nil
        )
        let provider = ScriptedWorkspaceProvider([
            WorkspaceAgentProviderResponse(message: "I found the matching file.")
        ])
        let runtime = WorkspaceAgentRuntime(store: store, runner: DeveloperToolRunner(), provider: provider)

        let result = try await runtime.runTurn(session: session, userText: "search for RootView", existingMessages: [])

        #expect(result.toolResults.map(\.tool) == [.search])
        #expect(result.toolResults.first?.output.contains("RootView.swift:1") == true)
        #expect(!(try await store.loadMessages(sessionID: session.id)).contains { $0.role == .tool })
    }

    @Test
    func agentRuntimeRetriesImplementationMessageThatHasNoToolCalls() async throws {
        let storeRoot = try makeTemporaryDirectory()
        let workspaceRoot = try makeTemporaryDirectory(prefix: "loom-source-workspace")
        try FileManager.default.createDirectory(
            at: workspaceRoot.appendingPathComponent("LoomX", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("struct ContentView {}\n".utf8).write(
            to: workspaceRoot.appendingPathComponent("LoomX/ContentView.swift"),
            options: [.atomic]
        )
        let store = WorkspaceStore(workspacesRoot: storeRoot)
        let session = try await store.createSession(
            displayName: "Runtime",
            rootURL: workspaceRoot,
            bookmarkData: nil,
            detectedProject: nil
        )
        let provider = ScriptedWorkspaceProvider([
            WorkspaceAgentProviderResponse(
                message: "Checking current LoomX app structure before implementing MVVM gradient app",
                toolCalls: [
                    WorkspaceAgentToolCall(tool: .readFile, relativePath: "LoomX/ContentView.swift")
                ]
            ),
            WorkspaceAgentProviderResponse(
                message: "Creating MVVM gradient app - implementing ViewModel + updating ContentView"
            ),
            WorkspaceAgentProviderResponse(
                message: "Writing the MVVM view model.",
                toolCalls: [
                    WorkspaceAgentToolCall(
                        tool: .writeFile,
                        relativePath: "LoomX/ViewModel.swift",
                        contents: "final class ViewModel {}\n"
                    )
                ]
            )
        ])
        let runtime = WorkspaceAgentRuntime(store: store, runner: DeveloperToolRunner(), provider: provider)

        let result = try await runtime.runTurn(
            session: session,
            userText: "please implement the MVVM gradient app directly in Xcode",
            existingMessages: []
        )

        #expect(result.toolResults.map(\.tool) == [.readFile, .writeFile])
        #expect(try String(contentsOf: workspaceRoot.appendingPathComponent("LoomX/ViewModel.swift"), encoding: .utf8) == "final class ViewModel {}\n")
        #expect((try await store.loadMessages(sessionID: session.id)).map(\.content).contains("Creating MVVM gradient app - implementing ViewModel + updating ContentView") == false)
    }

    @Test
    func agentRuntimeTurnsIncompleteWriteFileIntoToolFailure() async throws {
        let storeRoot = try makeTemporaryDirectory()
        let workspaceRoot = try makeTemporaryDirectory(prefix: "loom-source-workspace")
        let store = WorkspaceStore(workspacesRoot: storeRoot)
        let session = try await store.createSession(
            displayName: "Runtime",
            rootURL: workspaceRoot,
            bookmarkData: nil,
            detectedProject: nil
        )
        let provider = ScriptedWorkspaceProvider([
            WorkspaceToolCallParser.parse(
                """
                {"message":"Creating MVVM gradient app.","toolCalls":[{"writeFile"},{"relativePath":"LoomX/ViewModels/CircleButtonColorViewModel.swift"}]}
                """
            )
        ])
        let runtime = WorkspaceAgentRuntime(store: store, runner: DeveloperToolRunner(), provider: provider)

        let result = try await runtime.runTurn(session: session, userText: "please implement the plan", existingMessages: [])

        #expect(result.toolResults.map(\.tool) == [.writeFile])
        #expect(result.toolResults.first?.status == .failure)
        #expect(result.toolResults.first?.summary.contains("without file contents") == true)
        #expect(!FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("LoomX/ViewModels/CircleButtonColorViewModel.swift").path))
    }

    @Test
    func agentRuntimeKeepsGoingAfterRepeatedInvalidWriteFileCalls() async throws {
        let storeRoot = try makeTemporaryDirectory()
        let workspaceRoot = try makeTemporaryDirectory(prefix: "loom-source-workspace")
        try FileManager.default.createDirectory(
            at: workspaceRoot.appendingPathComponent("LoomX", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("struct ContentView {}\n".utf8).write(
            to: workspaceRoot.appendingPathComponent("LoomX/ContentView.swift"),
            options: [.atomic]
        )
        let store = WorkspaceStore(workspacesRoot: storeRoot)
        let session = try await store.createSession(
            displayName: "Runtime",
            rootURL: workspaceRoot,
            bookmarkData: nil,
            detectedProject: nil
        )
        let invalidWrite = WorkspaceToolCallParser.parse(
            """
            {"message":"Creating ViewModel first then ContentView update","toolCalls":[{"writeFile"},{"relativePath":"LoomX/ViewModels/CircleColorViewModel.swift"}]}
            """
        )
        let provider = ScriptedWorkspaceProvider([
            WorkspaceAgentProviderResponse(
                message: "Reading ContentView before changing it.",
                toolCalls: [WorkspaceAgentToolCall(tool: .readFile, relativePath: "LoomX/ContentView.swift")]
            ),
            invalidWrite,
            invalidWrite,
            WorkspaceAgentProviderResponse(
                message: "Writing the missing file with full contents.",
                toolCalls: [
                    WorkspaceAgentToolCall(
                        tool: .writeFile,
                        relativePath: "LoomX/ViewModels/CircleColorViewModel.swift",
                        contents: "final class CircleColorViewModel {}\n"
                    )
                ]
            )
        ])
        let runtime = WorkspaceAgentRuntime(store: store, runner: DeveloperToolRunner(), provider: provider)

        let result = try await runtime.runTurn(
            session: session,
            userText: "please implement the MVVM gradient app directly in Xcode",
            existingMessages: []
        )

        #expect(result.toolResults.map(\.status) == [.success, .failure, .failure, .success])
        #expect(try String(
            contentsOf: workspaceRoot.appendingPathComponent("LoomX/ViewModels/CircleColorViewModel.swift"),
            encoding: .utf8
        ) == "final class CircleColorViewModel {}\n")
    }

    @Test
    func toolIntentDetectorParsesCommonWorkspaceCommands() {
        #expect(WorkspaceToolIntentDetector.toolCalls(for: "git status").first?.tool == .gitStatus)
        #expect(WorkspaceToolIntentDetector.toolCalls(for: "run build").first?.tool == .build)
        #expect(WorkspaceToolIntentDetector.toolCalls(for: "read Loom/App.swift").first?.relativePath == "Loom/App.swift")
        #expect(WorkspaceToolIntentDetector.toolCalls(for: "find WorkspaceView").first?.pattern == "WorkspaceView")
    }

    @Test
    func toolIntentDetectorDoesNotTreatAppCreationPromptAsBuildCommand() {
        let prompt = """
        I want to build an iOS app that when launched simply opens and shows a nice gradient background. Please build out the whole app.
        """

        #expect(WorkspaceToolIntentDetector.toolCalls(for: prompt).isEmpty)
    }

    @Test
    func toolCallParserReadsFencedJSON() {
        let response = WorkspaceToolCallParser.parse(
            """
            ```json
            {"message":"Checking files","toolCalls":[{"tool":"search","pattern":"RootView"}]}
            ```
            """
        )

        #expect(response.message == "Checking files")
        #expect(response.toolCalls.count == 1)
        #expect(response.toolCalls.first?.tool == .search)
        #expect(response.toolCalls.first?.pattern == "RootView")
    }

    @Test
    func toolCallParserRecoversMalformedLocalToolShape() {
        let response = WorkspaceToolCallParser.parse(
            """
            I’ll help inspect this first.
            {"message":"Reading current project structure...","toolCalls":[{"readFile","relativePath":"LoomX/LoomXApp.swift"},{"readFile","relativePath":"LoomX/ContentView.swift"}]}
            """
        )

        #expect(response.message == "I’ll help inspect this first.")
        #expect(response.toolCalls.map(\.tool) == [.readFile, .readFile])
        #expect(response.toolCalls.map(\.relativePath) == ["LoomX/LoomXApp.swift", "LoomX/ContentView.swift"])
    }

    @Test
    func toolCallParserRecoversSplitMalformedWriteFileShape() {
        let response = WorkspaceToolCallParser.parse(
            """
            {"message":"Creating MVVM gradient app.","toolCalls":[{"writeFile"},{"relativePath":"LoomX/ViewModels/CircleButtonColorViewModel.swift"}]}
            """
        )

        #expect(response.message == "Creating MVVM gradient app.")
        #expect(response.toolCalls.count == 1)
        #expect(response.toolCalls.first?.tool == .writeFile)
        #expect(response.toolCalls.first?.relativePath == "LoomX/ViewModels/CircleButtonColorViewModel.swift")
        #expect(response.toolCalls.first?.contents == nil)
    }

    @Test
    func xcodebuildSchemeParserToleratesLogLinesAroundJSON() {
        let output = """
        2026-06-25 12:00:00.000 xcodebuild[123:456] DVT warning before JSON
        {"project":{"name":"Demo","schemes":["DemoTests","Demo"]}}
        trailing note
        """

        #expect(DeveloperToolRunner.parseSchemes(from: output) == ["Demo", "DemoTests"])
    }

    @Test
    func xcodebuildLicenseFailureGetsSpecificSummary() {
        let output = """
        You have not agreed to the Xcode license agreements.
        Please run 'sudo xcodebuild -license' from within a Terminal window.
        """

        #expect(DeveloperToolRunner.xcodeMetadataFailureSummary(for: output) == "Accept the Xcode license to load project schemes.")
    }
}

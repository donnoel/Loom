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
        #expect((try await store.loadMessages(sessionID: session.id)).contains { $0.role == .tool })
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
}

import Foundation

actor HelperBackedDeveloperToolRunner: DeveloperToolRunning {
    private let localRunner: any DeveloperToolRunning
    private let helperClient: LoomXHelperClient

    init(
        localRunner: any DeveloperToolRunning = DeveloperToolRunner(),
        helperClient: LoomXHelperClient = LoomXHelperClient()
    ) {
        self.localRunner = localRunner
        self.helperClient = helperClient
    }

    func readFile(session: WorkspaceSession, relativePath: String) async -> DeveloperToolResult {
        await localRunner.readFile(session: session, relativePath: relativePath)
    }

    func search(session: WorkspaceSession, pattern: String) async -> DeveloperToolResult {
        await localRunner.search(session: session, pattern: pattern)
    }

    func listFiles(session: WorkspaceSession) async -> (DeveloperToolResult, WorkspaceFileList) {
        if let helperResult = await helperClient.run(.listFiles, session: session) {
            let source = helperResult.fileSource == "git" ? WorkspaceFileList.Source.git : .fileSystem
            return (
                helperResult.result,
                WorkspaceFileList(files: helperResult.files, source: source)
            )
        }
        return await localRunner.listFiles(session: session)
    }

    func writeFile(session: WorkspaceSession, relativePath: String, contents: String) async -> DeveloperToolResult {
        await localRunner.writeFile(session: session, relativePath: relativePath, contents: contents)
    }

    func applyPatch(session: WorkspaceSession, patch: String) async -> DeveloperToolResult {
        await helperClient.run(.applyPatch, session: session, patch: patch)?.result ?? helperUnavailableResult(.applyPatch)
    }

    func gitDiff(session: WorkspaceSession) async -> DeveloperToolResult {
        await helperClient.run(.gitDiff, session: session)?.result ?? helperUnavailableResult(.gitDiff)
    }

    func gitStatus(session: WorkspaceSession) async -> DeveloperToolResult {
        await helperClient.run(.gitStatus, session: session)?.result ?? helperUnavailableResult(.gitStatus)
    }

    func xcodebuildList(session: WorkspaceSession) async -> (DeveloperToolResult, [String]) {
        guard let response = await helperClient.run(.xcodebuildList, session: session) else {
            return (helperUnavailableResult(.xcodebuildList), [])
        }
        return (response.result, response.schemes)
    }

    func build(session: WorkspaceSession) async -> DeveloperToolResult {
        await helperClient.run(.build, session: session)?.result ?? helperUnavailableResult(.build)
    }

    func test(session: WorkspaceSession) async -> DeveloperToolResult {
        await helperClient.run(.test, session: session)?.result ?? helperUnavailableResult(.test)
    }

    func openInXcode(session: WorkspaceSession) async -> DeveloperToolResult {
        await helperClient.run(.openInXcode, session: session)?.result ?? helperUnavailableResult(.openInXcode)
    }

    private func helperUnavailableResult(_ tool: DeveloperToolName) -> DeveloperToolResult {
        DeveloperToolResult(
            tool: tool,
            status: .failure,
            summary: "Start LoomX Helper to use git and Xcode tools.",
            output: LoomXHelperClient.startInstructions
        )
    }
}

actor LoomXHelperClient {
    struct ToolResponse: Sendable {
        let result: DeveloperToolResult
        let schemes: [String]
        let files: [String]
        let fileSource: String?
    }

    private struct ToolRequest: Encodable {
        let tool: DeveloperToolName
        let rootPath: String
        let projectKind: WorkspaceProjectKind?
        let projectPath: String?
        let scheme: String?
        let destination: String?
        let relativePath: String?
        let contents: String?
        let pattern: String?
        let patch: String?
    }

    private struct HelperResponse: Decodable {
        let tool: DeveloperToolName
        let status: DeveloperToolStatus
        let summary: String
        let output: String
        let schemes: [String]
        let files: [String]
        let fileSource: String?
    }

    static let port = 7347
    static let startInstructions = """
    In Terminal, run:
    cd /Users/donnoel/Development/Loom/LoomXHelper
    swift run LoomXHelper
    """

    private let endpoint = URL(string: "http://127.0.0.1:\(LoomXHelperClient.port)/tool")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func run(
        _ tool: DeveloperToolName,
        session workspaceSession: WorkspaceSession,
        relativePath: String? = nil,
        contents: String? = nil,
        pattern: String? = nil,
        patch: String? = nil
    ) async -> ToolResponse? {
        guard let token = Self.loadOrCreateToken() else {
            return nil
        }

        let startedAt = Date()
        let body = ToolRequest(
            tool: tool,
            rootPath: workspaceSession.rootPath,
            projectKind: workspaceSession.selectedProject?.kind,
            projectPath: workspaceSession.selectedProject?.relativePath,
            scheme: workspaceSession.selectedScheme,
            destination: workspaceSession.selectedDestination,
            relativePath: relativePath,
            contents: contents,
            pattern: pattern,
            patch: patch
        )

        do {
            var request = URLRequest(url: endpoint, timeoutInterval: 3600)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-LoomX-Token")
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let helperResponse = try JSONDecoder().decode(HelperResponse.self, from: data)
            let result = DeveloperToolResult(
                tool: helperResponse.tool,
                status: helperResponse.status,
                summary: helperResponse.summary,
                output: helperResponse.output,
                startedAt: startedAt,
                finishedAt: Date()
            )
            return ToolResponse(
                result: result,
                schemes: helperResponse.schemes,
                files: helperResponse.files,
                fileSource: helperResponse.fileSource
            )
        } catch {
            return nil
        }
    }

    private static func loadOrCreateToken() -> String? {
        guard let tokenURL = helperTokenURL() else { return nil }
        if let token = try? String(contentsOf: tokenURL, encoding: .utf8).nonEmptyTrimmed {
            return token
        }

        let token = UUID().uuidString + UUID().uuidString
        do {
            try Data(token.utf8).write(to: tokenURL, options: [.atomic])
            return token
        } catch {
            return nil
        }
    }

    private static func helperTokenURL() -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Loom/LoomX", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root.appendingPathComponent("helper-token")
        } catch {
            return nil
        }
    }
}

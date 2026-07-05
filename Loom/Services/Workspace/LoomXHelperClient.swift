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
        if let response = await helperClient.run(.applyPatch, session: session, patch: patch) {
            return response.result
        }
        return await localRunner.applyPatch(session: session, patch: patch)
    }

    func gitDiff(session: WorkspaceSession) async -> DeveloperToolResult {
        if let response = await helperClient.run(.gitDiff, session: session) {
            return response.result
        }
        return await localRunner.gitDiff(session: session)
    }

    func gitStatus(session: WorkspaceSession) async -> DeveloperToolResult {
        if let response = await helperClient.run(.gitStatus, session: session) {
            return response.result
        }
        return await localRunner.gitStatus(session: session)
    }

    func xcodebuildList(session: WorkspaceSession) async -> (DeveloperToolResult, [String]) {
        if let response = await helperClient.run(.xcodebuildList, session: session) {
            return (response.result, response.schemes)
        }
        return await localRunner.xcodebuildList(session: session)
    }

    func build(session: WorkspaceSession) async -> DeveloperToolResult {
        if let response = await helperClient.run(.build, session: session) {
            return response.result
        }
        return await localRunner.build(session: session)
    }

    func test(session: WorkspaceSession) async -> DeveloperToolResult {
        if let response = await helperClient.run(.test, session: session) {
            return response.result
        }
        return await localRunner.test(session: session)
    }

    func openInXcode(session: WorkspaceSession) async -> DeveloperToolResult {
        if let response = await helperClient.run(.openInXcode, session: session) {
            return response.result
        }
        return await localRunner.openInXcode(session: session)
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

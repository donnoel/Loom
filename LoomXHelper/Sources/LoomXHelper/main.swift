import Foundation
import Dispatch
import Network

private let helperPort: UInt16 = 7347
private let maxOutputCharacters = 24_000

private enum HelperTool: String, Codable {
    case readFile
    case search
    case listFiles
    case writeFile
    case applyPatch
    case gitDiff
    case gitStatus
    case xcodebuildList
    case build
    case test
    case openInXcode
}

private enum HelperStatus: String, Codable {
    case success
    case failure
    case skipped
}

private struct HelperRequest: Decodable {
    let tool: HelperTool
    let rootPath: String
    let projectKind: String?
    let projectPath: String?
    let scheme: String?
    let destination: String?
    let relativePath: String?
    let contents: String?
    let pattern: String?
    let patch: String?
}

private struct HelperResponse: Encodable {
    let tool: HelperTool
    let status: HelperStatus
    let summary: String
    let output: String
    let schemes: [String]
    let files: [String]
    let fileSource: String?
}

private struct ProcessCommandResult {
    let exitCode: Int32
    let output: String
}

private final class LoomXHelperServer: @unchecked Sendable {
    private let token: String
    private let runner = HelperRunner()
    private var listener: NWListener?

    init(token: String) {
        self.token = token
    }

    func start() throws {
        let port = NWEndpoint.Port(rawValue: helperPort)!
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: .main)
        self.listener = listener
        print("LoomXHelper listening on http://127.0.0.1:\(helperPort)")
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, data: Data())
    }

    private func receive(on connection: NWConnection, data existingData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.send(error: "Connection failed: \(error.localizedDescription)", status: 500, on: connection)
                return
            }

            var receivedData = existingData
            if let data {
                receivedData.append(data)
            }

            if let request = HTTPRequest(data: receivedData) {
                self.handle(request, on: connection)
                return
            }

            if isComplete {
                self.send(error: "Invalid HTTP request.", status: 400, on: connection)
            } else {
                self.receive(on: connection, data: receivedData)
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        guard request.path == "/tool" else {
            send(error: "Unknown endpoint.", status: 404, on: connection)
            return
        }
        guard request.headers["x-loomx-token"] == token else {
            send(error: "Unauthorized.", status: 401, on: connection)
            return
        }

        do {
            let toolRequest = try JSONDecoder().decode(HelperRequest.self, from: request.body)
            let response = runner.run(toolRequest)
            send(response, on: connection)
        } catch {
            send(error: "Could not decode tool request: \(error.localizedDescription)", status: 400, on: connection)
        }
    }

    private func send(_ response: HelperResponse, on connection: NWConnection) {
        do {
            let data = try JSONEncoder().encode(response)
            send(data: data, status: 200, contentType: "application/json", on: connection)
        } catch {
            send(error: "Could not encode helper response.", status: 500, on: connection)
        }
    }

    private func send(error: String, status: Int, on connection: NWConnection) {
        let body = Data("{\"error\":\"\(error.httpEscaped)\"}".utf8)
        send(data: body, status: status, contentType: "application/json", on: connection)
    }

    private func send(data: Data, status: Int, contentType: String, on connection: NWConnection) {
        let reason = status == 200 ? "OK" : "Error"
        var response = Data("HTTP/1.1 \(status) \(reason)\r\n".utf8)
        response.append(Data("Content-Type: \(contentType)\r\n".utf8))
        response.append(Data("Content-Length: \(data.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private struct HTTPRequest {
    let path: String
    let headers: [String: String]
    let body: Data

    init?(data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }
        path = String(requestParts[1])

        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            parsedHeaders[name] = value
        }
        headers = parsedHeaders

        let bodyStart = headerEnd.upperBound
        let expectedLength = Int(headers["content-length"] ?? "0") ?? 0
        guard data.count >= bodyStart + expectedLength else {
            return nil
        }
        body = data[bodyStart..<(bodyStart + expectedLength)]
    }
}

private final class HelperRunner {
    private let gitExecutablePath = executablePath(
        preferred: "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
        fallback: "/usr/bin/git"
    )
    private let xcodebuildExecutablePath = executablePath(
        preferred: "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild",
        fallback: "/usr/bin/xcodebuild"
    )

    func run(_ request: HelperRequest) -> HelperResponse {
        switch request.tool {
        case .readFile:
            return readFile(request)
        case .search:
            return search(request)
        case .listFiles:
            return listFiles(request)
        case .writeFile:
            return writeFile(request)
        case .applyPatch:
            return applyPatch(request)
        case .gitDiff:
            return gitCommand(request, tool: .gitDiff, arguments: ["diff", "--"], successSummary: "Loaded current diff.")
        case .gitStatus:
            return gitCommand(request, tool: .gitStatus, arguments: ["status", "--short", "--branch"], successSummary: "Loaded git status.")
        case .xcodebuildList:
            return xcodebuildList(request)
        case .build:
            return xcodebuildAction(request, action: "build", tool: .build)
        case .test:
            return xcodebuildAction(request, action: "test", tool: .test)
        case .openInXcode:
            return openInXcode(request)
        }
    }

    private func readFile(_ request: HelperRequest) -> HelperResponse {
        do {
            let path = try resolvedURL(for: request.relativePath ?? "", rootPath: request.rootPath)
            let data = try Data(contentsOf: path)
            guard let text = String(data: data, encoding: .utf8) else {
                return response(.readFile, .failure, "That file is not readable as text.")
            }
            return response(.readFile, .success, "Read \(request.relativePath ?? "")", text)
        } catch {
            return response(.readFile, .failure, "LoomX Helper could not read that file.", error.localizedDescription)
        }
    }

    private func search(_ request: HelperRequest) -> HelperResponse {
        guard let pattern = request.pattern?.nonEmptyTrimmed else {
            return response(.search, .failure, "Enter a search pattern.")
        }
        let files = listedFiles(request).files
        var matches: [String] = []
        for file in files.prefix(800) {
            guard matches.count < 120,
                  let url = try? resolvedURL(for: file, rootPath: request.rootPath),
                  let data = try? Data(contentsOf: url),
                  !data.contains(0),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where line.localizedCaseInsensitiveContains(pattern) {
                matches.append("\(file):\(index + 1): \(line)")
                if matches.count >= 120 { break }
            }
        }
        return response(.search, .success, "Searched for \(pattern)", matches.isEmpty ? "No matches." : matches.joined(separator: "\n"))
    }

    private func listFiles(_ request: HelperRequest) -> HelperResponse {
        let list = listedFiles(request)
        return response(
            .listFiles,
            .success,
            "Listed \(list.files.count) files.",
            list.files.prefix(300).joined(separator: "\n"),
            files: list.files,
            fileSource: list.source
        )
    }

    private func writeFile(_ request: HelperRequest) -> HelperResponse {
        guard let relativePath = request.relativePath?.nonEmptyTrimmed else {
            return response(.writeFile, .failure, "No file path was provided.")
        }
        guard let contents = request.contents else {
            return response(.writeFile, .failure, "No file contents were provided.")
        }
        do {
            let url = try resolvedURL(for: relativePath, rootPath: request.rootPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url, options: [.atomic])
            return response(.writeFile, .success, "Wrote \(relativePath)")
        } catch {
            return response(.writeFile, .failure, "LoomX Helper could not write that file.", error.localizedDescription)
        }
    }

    private func applyPatch(_ request: HelperRequest) -> HelperResponse {
        guard let patch = request.patch?.nonEmptyTrimmed else {
            return response(.applyPatch, .failure, "No patch was provided.")
        }
        do {
            let rootURL = URL(fileURLWithPath: request.rootPath, isDirectory: true)
            let check = try runProcess(
                executablePath: gitExecutablePath,
                arguments: ["apply", "--check", "--whitespace=nowarn", "-"],
                currentDirectory: rootURL,
                input: patch
            )
            guard check.exitCode == 0 else {
                return response(.applyPatch, .failure, "The patch did not apply cleanly.", check.output)
            }
            let apply = try runProcess(
                executablePath: gitExecutablePath,
                arguments: ["apply", "--whitespace=nowarn", "-"],
                currentDirectory: rootURL,
                input: patch
            )
            guard apply.exitCode == 0 else {
                return response(.applyPatch, .failure, "LoomX Helper could not apply the patch.", apply.output)
            }
            return response(.applyPatch, .success, "Applied patch.", apply.output)
        } catch {
            return response(.applyPatch, .failure, "LoomX Helper could not apply the patch.", error.localizedDescription)
        }
    }

    private func gitCommand(_ request: HelperRequest, tool: HelperTool, arguments: [String], successSummary: String) -> HelperResponse {
        do {
            let command = try runProcess(
                executablePath: gitExecutablePath,
                arguments: arguments,
                currentDirectory: URL(fileURLWithPath: request.rootPath, isDirectory: true)
            )
            let status: HelperStatus = command.exitCode == 0 ? .success : .failure
            return response(tool, status, status == .success ? successSummary : "Git command failed.", command.output)
        } catch {
            return response(tool, .failure, "Git command failed.", error.localizedDescription)
        }
    }

    private func xcodebuildList(_ request: HelperRequest) -> HelperResponse {
        do {
            var arguments = try xcodeProjectArguments(for: request)
            arguments.append(contentsOf: ["-list", "-json"])
            let command = try runProcess(
                executablePath: xcodebuildExecutablePath,
                arguments: arguments,
                currentDirectory: URL(fileURLWithPath: request.rootPath, isDirectory: true)
            )
            let schemes = Self.parseSchemes(from: command.output)
            let status: HelperStatus = command.exitCode == 0 ? .success : .failure
            return response(
                .xcodebuildList,
                status,
                status == .success ? "Loaded Xcode project metadata." : "Xcode project metadata failed.",
                command.output,
                schemes: schemes
            )
        } catch {
            return response(.xcodebuildList, .failure, "Choose an Xcode project or workspace first.", error.localizedDescription)
        }
    }

    private func xcodebuildAction(_ request: HelperRequest, action: String, tool: HelperTool) -> HelperResponse {
        guard let scheme = request.scheme?.nonEmptyTrimmed else {
            return response(tool, .failure, "Choose a scheme before running \(action).")
        }
        do {
            var arguments = try xcodeProjectArguments(for: request)
            arguments.append(contentsOf: ["-scheme", scheme])
            if let destination = request.destination?.nonEmptyTrimmed {
                arguments.append(contentsOf: ["-destination", destination])
            }
            arguments.append(action)
            let command = try runProcess(
                executablePath: xcodebuildExecutablePath,
                arguments: arguments,
                currentDirectory: URL(fileURLWithPath: request.rootPath, isDirectory: true)
            )
            let status: HelperStatus = command.exitCode == 0 ? .success : .failure
            return response(tool, status, status == .success ? "Xcode \(action) succeeded." : "Xcode \(action) failed.", command.output)
        } catch {
            return response(tool, .failure, "Xcode \(action) failed.", error.localizedDescription)
        }
    }

    private func openInXcode(_ request: HelperRequest) -> HelperResponse {
        do {
            let targetURL: URL
            if let projectPath = request.projectPath?.nonEmptyTrimmed {
                targetURL = try resolvedURL(for: projectPath, rootPath: request.rootPath)
            } else {
                targetURL = URL(fileURLWithPath: request.rootPath, isDirectory: true)
            }
            let command = try runProcess(
                executablePath: "/usr/bin/open",
                arguments: [targetURL.path],
                currentDirectory: URL(fileURLWithPath: request.rootPath, isDirectory: true)
            )
            let status: HelperStatus = command.exitCode == 0 ? .success : .failure
            return response(.openInXcode, status, status == .success ? "Opened LoomX project in Xcode." : "Could not open LoomX project.", command.output)
        } catch {
            return response(.openInXcode, .failure, "Could not open LoomX project.", error.localizedDescription)
        }
    }

    private func listedFiles(_ request: HelperRequest) -> (files: [String], source: String) {
        let rootURL = URL(fileURLWithPath: request.rootPath, isDirectory: true)
        if let command = try? runProcess(executablePath: gitExecutablePath, arguments: ["ls-files"], currentDirectory: rootURL),
           command.exitCode == 0 {
            let files = command.output
                .split(separator: "\n")
                .map(String.init)
                .filter(shouldInclude)
                .sorted()
            if !files.isEmpty {
                return (files, "git")
            }
        }
        return ((try? fileSystemFiles(in: rootURL)) ?? [], "fileSystem")
    }

    private func xcodeProjectArguments(for request: HelperRequest) throws -> [String] {
        guard let projectPath = request.projectPath?.nonEmptyTrimmed,
              let projectKind = request.projectKind?.nonEmptyTrimmed else {
            throw CocoaError(.fileNoSuchFile)
        }
        let projectURL = try resolvedURL(for: projectPath, rootPath: request.rootPath)
        if projectKind == "xcodeWorkspace" {
            return ["-workspace", projectURL.path]
        }
        return ["-project", projectURL.path]
    }

    private func resolvedURL(for relativePath: String, rootPath: String) throws -> URL {
        guard let normalized = relativePath.nonEmptyTrimmed,
              !normalized.hasPrefix("/"),
              !normalized.split(separator: "/").contains("..") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let resolved = root.appendingPathComponent(normalized).standardizedFileURL
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            throw CocoaError(.fileReadNoPermission)
        }
        return resolved
    }

    private func fileSystemFiles(in rootURL: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [String] = []
        for case let url as URL in enumerator {
            let relativePath = Self.relativePath(for: url, rootURL: rootURL)
            if !shouldDescend(into: relativePath) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  shouldInclude(relativePath) else {
                continue
            }
            files.append(relativePath)
        }
        return files.sorted()
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        currentDirectory: URL,
        input: String? = nil
    ) throws -> ProcessCommandResult {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomx-helper-\(UUID().uuidString).out")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        let inputPipe: Pipe?
        if input != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            inputPipe = pipe
        } else {
            inputPipe = nil
        }

        try process.run()
        if let input, let inputPipe {
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inputPipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()

        try outputHandle.synchronize()
        let data = try Data(contentsOf: outputURL)
        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessCommandResult(exitCode: process.terminationStatus, output: trimmedOutput(output))
    }

    private func response(
        _ tool: HelperTool,
        _ status: HelperStatus,
        _ summary: String,
        _ output: String = "",
        schemes: [String] = [],
        files: [String] = [],
        fileSource: String? = nil
    ) -> HelperResponse {
        HelperResponse(
            tool: tool,
            status: status,
            summary: summary,
            output: trimmedOutput(output),
            schemes: schemes,
            files: files,
            fileSource: fileSource
        )
    }

    private func trimmedOutput(_ output: String) -> String {
        guard output.count > maxOutputCharacters else { return output }
        return String(output.prefix(maxOutputCharacters)) + "\n\n[Output trimmed by LoomX Helper.]"
    }

    private static func parseSchemes(from output: String) -> [String] {
        guard let jsonText = firstJSONObject(in: output),
              let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        for key in ["project", "workspace"] {
            if let container = object[key] as? [String: Any],
               let schemes = container["schemes"] as? [String] {
                return schemes.sorted()
            }
        }
        return []
    }

    private static func firstJSONObject(in output: String) -> String? {
        guard let startIndex = output.firstIndex(of: "{") else { return nil }
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = startIndex
        while index < output.endIndex {
            let character = output[index]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isInsideString.toggle()
            } else if !isInsideString {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(output[startIndex...index])
                    }
                }
            }
            index = output.index(after: index)
        }
        return nil
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }
}

private func shouldDescend(into relativePath: String) -> Bool {
    let blocked = [
        ".git",
        "DerivedData",
        "Build",
        ".build",
        "node_modules",
        "Pods",
        ".swiftpm"
    ]
    return !relativePath.split(separator: "/").contains { blocked.contains(String($0)) }
}

private func shouldInclude(_ relativePath: String) -> Bool {
    guard shouldDescend(into: relativePath) else { return false }
    let blockedExtensions = ["png", "jpg", "jpeg", "gif", "pdf", "zip", "app", "dSYM", "xcresult"]
    guard let ext = relativePath.split(separator: ".").last.map(String.init), relativePath.contains(".") else {
        return true
    }
    return !blockedExtensions.contains(ext)
}

private func executablePath(preferred: String, fallback: String) -> String {
    FileManager.default.isExecutableFile(atPath: preferred) ? preferred : fallback
}

private func helperTokenURL() throws -> URL {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Loom/LoomX", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("helper-token")
}

private func loadOrCreateToken() throws -> String {
    let url = try helperTokenURL()
    if let token = try? String(contentsOf: url, encoding: .utf8).nonEmptyTrimmed {
        return token
    }
    let token = UUID().uuidString + UUID().uuidString
    try Data(token.utf8).write(to: url, options: [.atomic])
    return token
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var httpEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

do {
    let server = try LoomXHelperServer(token: loadOrCreateToken())
    try server.start()
    dispatchMain()
} catch {
    fputs("LoomXHelper failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

import Foundation

protocol DeveloperToolRunning: Actor {
    func readFile(session: WorkspaceSession, relativePath: String) async -> DeveloperToolResult
    func search(session: WorkspaceSession, pattern: String) async -> DeveloperToolResult
    func listFiles(session: WorkspaceSession) async -> (DeveloperToolResult, WorkspaceFileList)
    func writeFile(session: WorkspaceSession, relativePath: String, contents: String) async -> DeveloperToolResult
    func applyPatch(session: WorkspaceSession, patch: String) async -> DeveloperToolResult
    func gitDiff(session: WorkspaceSession) async -> DeveloperToolResult
    func gitStatus(session: WorkspaceSession) async -> DeveloperToolResult
    func xcodebuildList(session: WorkspaceSession) async -> (DeveloperToolResult, [String])
    func build(session: WorkspaceSession) async -> DeveloperToolResult
    func test(session: WorkspaceSession) async -> DeveloperToolResult
    func openInXcode(session: WorkspaceSession) async -> DeveloperToolResult
}

actor DeveloperToolRunner: DeveloperToolRunning {
    private struct ProcessCommandResult: Sendable {
        let exitCode: Int32
        let output: String
    }

    private let maxReadBytes = 1_000_000
    private let maxSearchFileBytes = 300_000
    private let maxOutputCharacters = 24_000

    func readFile(session: WorkspaceSession, relativePath: String) async -> DeveloperToolResult {
        let startedAt = Date()
        do {
            let url = try resolvedURL(for: relativePath, in: session)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                return result(.readFile, .failure, "That path is not a file.", "", startedAt)
            }
            guard (values.fileSize ?? 0) <= maxReadBytes else {
                return result(.readFile, .failure, "That file is too large to read into the agent context.", "", startedAt)
            }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                return result(.readFile, .failure, "That file is not readable as text.", "", startedAt)
            }
            return result(.readFile, .success, "Read \(relativePath)", text, startedAt)
        } catch {
            return result(.readFile, .failure, "Loom could not read that file.", error.localizedDescription, startedAt)
        }
    }

    func search(session: WorkspaceSession, pattern: String) async -> DeveloperToolResult {
        let startedAt = Date()
        guard let needle = pattern.nonEmptyTrimmed else {
            return result(.search, .failure, "Enter a search pattern.", "", startedAt)
        }

        let (_, list) = await listFiles(session: session)
        var matches: [String] = []
        for file in list.files.prefix(800) {
            guard matches.count < 120 else { break }
            guard let url = try? resolvedURL(for: file, in: session),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) <= maxSearchFileBytes,
                  let data = try? Data(contentsOf: url),
                  !data.contains(0),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }

            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where line.localizedCaseInsensitiveContains(needle) {
                matches.append("\(file):\(index + 1): \(line)")
                if matches.count >= 120 { break }
            }
        }

        let output = matches.isEmpty ? "No matches." : matches.joined(separator: "\n")
        return result(.search, .success, "Searched for \(needle)", output, startedAt)
    }

    func listFiles(session: WorkspaceSession) async -> (DeveloperToolResult, WorkspaceFileList) {
        let startedAt = Date()
        if let gitList = try? await gitTrackedFiles(in: session), !gitList.isEmpty {
            let fileList = WorkspaceFileList(files: gitList, source: .git)
            return (
                result(.listFiles, .success, "Listed \(gitList.count) git-tracked files.", gitList.prefix(300).joined(separator: "\n"), startedAt),
                fileList
            )
        }

        do {
            let files = try fileSystemFiles(in: session.rootURL)
            let fileList = WorkspaceFileList(files: files, source: .fileSystem)
            return (
                result(.listFiles, .success, "Listed \(files.count) files.", files.prefix(300).joined(separator: "\n"), startedAt),
                fileList
            )
        } catch {
            let empty = WorkspaceFileList(files: [], source: .fileSystem)
            return (
                result(.listFiles, .failure, "Loom could not list files.", error.localizedDescription, startedAt),
                empty
            )
        }
    }

    func writeFile(session: WorkspaceSession, relativePath: String, contents: String) async -> DeveloperToolResult {
        let startedAt = Date()
        do {
            let url = try resolvedURL(for: relativePath, in: session)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url, options: [.atomic])
            return result(.writeFile, .success, "Wrote \(relativePath)", "", startedAt)
        } catch {
            return result(.writeFile, .failure, "Loom could not write that file.", error.localizedDescription, startedAt)
        }
    }

    func applyPatch(session: WorkspaceSession, patch: String) async -> DeveloperToolResult {
        let startedAt = Date()
        guard patch.nonEmptyTrimmed != nil else {
            return result(.applyPatch, .failure, "No patch was provided.", "", startedAt)
        }

        do {
            let check = try await runProcess(
                executablePath: "/usr/bin/git",
                arguments: ["apply", "--check", "--whitespace=nowarn", "-"],
                currentDirectory: session.rootURL,
                input: patch
            )
            guard check.exitCode == 0 else {
                return result(.applyPatch, .failure, "The patch did not apply cleanly.", check.output, startedAt)
            }

            let apply = try await runProcess(
                executablePath: "/usr/bin/git",
                arguments: ["apply", "--whitespace=nowarn", "-"],
                currentDirectory: session.rootURL,
                input: patch
            )
            guard apply.exitCode == 0 else {
                return result(.applyPatch, .failure, "Loom could not apply the patch.", apply.output, startedAt)
            }
            return result(.applyPatch, .success, "Applied patch.", apply.output, startedAt)
        } catch {
            return result(.applyPatch, .failure, "Loom could not apply the patch.", error.localizedDescription, startedAt)
        }
    }

    func gitDiff(session: WorkspaceSession) async -> DeveloperToolResult {
        await gitCommand(session: session, tool: .gitDiff, arguments: ["diff", "--"], successSummary: "Loaded current diff.")
    }

    func gitStatus(session: WorkspaceSession) async -> DeveloperToolResult {
        await gitCommand(session: session, tool: .gitStatus, arguments: ["status", "--short", "--branch"], successSummary: "Loaded git status.")
    }

    func xcodebuildList(session: WorkspaceSession) async -> (DeveloperToolResult, [String]) {
        let startedAt = Date()
        do {
            var arguments = try xcodeProjectArguments(for: session)
            arguments.append(contentsOf: ["-list", "-json"])
            let command = try await runProcess(
                executablePath: "/usr/bin/xcodebuild",
                arguments: arguments,
                currentDirectory: session.rootURL
            )
            let schemes = Self.parseSchemes(from: command.output)
            let status: DeveloperToolStatus = command.exitCode == 0 ? .success : .failure
            let summary = command.exitCode == 0 ? "Loaded Xcode project metadata." : "Xcode project metadata failed."
            return (result(.xcodebuildList, status, summary, command.output, startedAt), schemes)
        } catch {
            return (result(.xcodebuildList, .failure, "Choose an Xcode project or workspace first.", error.localizedDescription, startedAt), [])
        }
    }

    func build(session: WorkspaceSession) async -> DeveloperToolResult {
        await xcodebuildAction(session: session, action: "build", tool: .build)
    }

    func test(session: WorkspaceSession) async -> DeveloperToolResult {
        await xcodebuildAction(session: session, action: "test", tool: .test)
    }

    func openInXcode(session: WorkspaceSession) async -> DeveloperToolResult {
        let startedAt = Date()
        do {
            let targetURL: URL
            if let relativePath = session.selectedProject?.relativePath {
                targetURL = try resolvedURL(for: relativePath, in: session)
            } else {
                targetURL = session.rootURL
            }
            let command = try await runProcess(
                executablePath: "/usr/bin/open",
                arguments: [targetURL.path],
                currentDirectory: session.rootURL
            )
            let status: DeveloperToolStatus = command.exitCode == 0 ? .success : .failure
            return result(.openInXcode, status, status == .success ? "Opened LoomX project in Xcode." : "Could not open LoomX project.", command.output, startedAt)
        } catch {
            return result(.openInXcode, .failure, "Could not open LoomX project.", error.localizedDescription, startedAt)
        }
    }

    private func gitCommand(
        session: WorkspaceSession,
        tool: DeveloperToolName,
        arguments: [String],
        successSummary: String
    ) async -> DeveloperToolResult {
        let startedAt = Date()
        do {
            let command = try await runProcess(
                executablePath: "/usr/bin/git",
                arguments: arguments,
                currentDirectory: session.rootURL
            )
            let status: DeveloperToolStatus = command.exitCode == 0 ? .success : .failure
            return result(tool, status, status == .success ? successSummary : "Git command failed.", command.output, startedAt)
        } catch {
            return result(tool, .failure, "Git command failed.", error.localizedDescription, startedAt)
        }
    }

    private func xcodebuildAction(session: WorkspaceSession, action: String, tool: DeveloperToolName) async -> DeveloperToolResult {
        let startedAt = Date()
        guard let scheme = session.selectedScheme?.nonEmptyTrimmed else {
            return result(tool, .failure, "Choose a scheme before running \(action).", "", startedAt)
        }

        do {
            var arguments = try xcodeProjectArguments(for: session)
            arguments.append(contentsOf: ["-scheme", scheme])
            if let destination = session.selectedDestination?.nonEmptyTrimmed {
                arguments.append(contentsOf: ["-destination", destination])
            }
            arguments.append(action)
            let command = try await runProcess(
                executablePath: "/usr/bin/xcodebuild",
                arguments: arguments,
                currentDirectory: session.rootURL
            )
            let status: DeveloperToolStatus = command.exitCode == 0 ? .success : .failure
            return result(tool, status, status == .success ? "Xcode \(action) succeeded." : "Xcode \(action) failed.", command.output, startedAt)
        } catch {
            return result(tool, .failure, "Xcode \(action) failed.", error.localizedDescription, startedAt)
        }
    }

    private func xcodeProjectArguments(for session: WorkspaceSession) throws -> [String] {
        guard let project = session.selectedProject else {
            throw CocoaError(.fileNoSuchFile)
        }
        let url = try resolvedURL(for: project.relativePath, in: session)
        switch project.kind {
        case .xcodeProject:
            return ["-project", url.path]
        case .xcodeWorkspace:
            return ["-workspace", url.path]
        }
    }

    private func gitTrackedFiles(in session: WorkspaceSession) async throws -> [String] {
        let command = try await runProcess(
            executablePath: "/usr/bin/git",
            arguments: ["ls-files"],
            currentDirectory: session.rootURL
        )
        guard command.exitCode == 0 else { return [] }
        return command.output
            .split(separator: "\n")
            .map(String.init)
            .filter { WorkspaceIndexer.shouldInclude(relativePath: $0) }
            .sorted()
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
            if !WorkspaceIndexer.shouldDescend(into: relativePath) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  WorkspaceIndexer.shouldInclude(relativePath: relativePath) else {
                continue
            }
            files.append(relativePath)
        }
        return files.sorted()
    }

    private func resolvedURL(for relativePath: String, in session: WorkspaceSession) throws -> URL {
        guard let normalized = relativePath.nonEmptyTrimmed,
              !normalized.hasPrefix("/"),
              !normalized.split(separator: "/").contains("..") else {
            throw CocoaError(.fileReadInvalidFileName)
        }

        let root = session.rootURL.standardizedFileURL
        let resolved = root.appendingPathComponent(normalized, isDirectory: false).standardizedFileURL
        let rootPath = root.path
        let resolvedPath = resolved.path
        guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/") else {
            throw CocoaError(.fileReadNoPermission)
        }
        return resolved
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        currentDirectory: URL,
        input: String? = nil
    ) async throws -> ProcessCommandResult {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-tool-\(UUID().uuidString).out", isDirectory: false)
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

    private func result(
        _ tool: DeveloperToolName,
        _ status: DeveloperToolStatus,
        _ summary: String,
        _ output: String,
        _ startedAt: Date
    ) -> DeveloperToolResult {
        DeveloperToolResult(
            tool: tool,
            status: status,
            summary: summary,
            output: trimmedOutput(output),
            startedAt: startedAt,
            finishedAt: Date()
        )
    }

    private func trimmedOutput(_ output: String) -> String {
        guard output.count > maxOutputCharacters else {
            return output
        }
        return String(output.prefix(maxOutputCharacters)) + "\n\n[Output trimmed by Loom.]"
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func parseSchemes(from output: String) -> [String] {
        guard let data = output.data(using: .utf8),
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
}

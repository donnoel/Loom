import Foundation
import OSLog

actor WorkspaceStore {
    private let log = Logger(subsystem: "com.loom.app", category: "WorkspaceStore")
    private let workspacesRootOverride: URL?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let lineEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let lineDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(workspacesRoot: URL? = nil) {
        self.workspacesRootOverride = workspacesRoot
    }

    func bootstrap() throws {
        try FileManager.default.createDirectory(at: try workspacesRoot(), withIntermediateDirectories: true)
    }

    func listSessions() throws -> [WorkspaceSession] {
        try bootstrap()
        let root = try workspacesRoot()
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var sessions: [WorkspaceSession] = []
        for url in urls {
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true,
                      let id = UUID(uuidString: url.lastPathComponent) else {
                    continue
                }
                let metadataURL = try workspaceMetadataURL(for: id)
                guard FileManager.default.fileExists(atPath: metadataURL.path) else { continue }
                let data = try Data(contentsOf: metadataURL)
                sessions.append(try decoder.decode(WorkspaceSession.self, from: data))
            } catch {
                log.error("Failed to load workspace session \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func createSession(
        displayName: String,
        rootURL: URL,
        bookmarkData: Data?,
        detectedProject: WorkspaceSession.ProjectSelection?
    ) throws -> WorkspaceSession {
        try bootstrap()
        let session = WorkspaceSession(
            displayName: displayName.nonEmptyTrimmed ?? rootURL.lastPathComponent,
            rootPath: rootURL.path,
            rootBookmarkData: bookmarkData,
            selectedProject: detectedProject,
            selectedScheme: detectedProject?.schemes.first
        )
        try saveSession(session)
        return session
    }

    func saveSession(_ session: WorkspaceSession) throws {
        try bootstrap()
        let folder = try workspaceFolder(for: session.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metadataURL = try workspaceMetadataURL(for: session.id)
        var updated = session
        updated.updatedAt = Date()
        let data = try encoder.encode(updated)
        try data.write(to: metadataURL, options: [.atomic])
        try ensureLineFilesExist(for: updated.id)
    }

    func deleteSession(id: UUID) throws {
        let folder = try workspaceFolder(for: id)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    func appendMessage(_ message: ChatMessage, sessionID: UUID) throws {
        try appendLine(message, to: try workspaceMessagesURL(for: sessionID))
    }

    func loadMessages(sessionID: UUID) throws -> [ChatMessage] {
        try decodeLines(ChatMessage.self, from: try workspaceMessagesURL(for: sessionID))
    }

    func appendToolEvent(_ result: DeveloperToolResult, sessionID: UUID) throws {
        try appendLine(result, to: try workspaceToolEventsURL(for: sessionID))
    }

    func loadToolEvents(sessionID: UUID) throws -> [DeveloperToolResult] {
        try decodeLines(DeveloperToolResult.self, from: try workspaceToolEventsURL(for: sessionID))
    }

    func saveChangePatch(_ patch: String, toolResultID: UUID, sessionID: UUID) throws -> WorkspaceChangeRecord {
        let folder = try workspaceChangesFolder(for: sessionID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let record = WorkspaceChangeRecord(toolResultID: toolResultID, patch: patch)
        let data = try encoder.encode(record)
        let url = folder.appendingPathComponent("\(record.id.uuidString).json", isDirectory: false)
        try data.write(to: url, options: [.atomic])
        return record
    }

    func loadChangeRecords(sessionID: UUID) throws -> [WorkspaceChangeRecord] {
        let folder = try workspaceChangesFolder(for: sessionID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(WorkspaceChangeRecord.self, from: data) else {
                return nil
            }
            return record
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func workspacesRoot() throws -> URL {
        if let workspacesRootOverride {
            return workspacesRootOverride
        }
        return try LoomPaths.workspacesRoot()
    }

    private func workspaceFolder(for id: UUID) throws -> URL {
        try workspacesRoot().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func workspaceMetadataURL(for id: UUID) throws -> URL {
        try workspaceFolder(for: id).appendingPathComponent(LoomPaths.metadataFileName, isDirectory: false)
    }

    private func workspaceMessagesURL(for id: UUID) throws -> URL {
        try workspaceFolder(for: id).appendingPathComponent(LoomPaths.messagesFileName, isDirectory: false)
    }

    private func workspaceToolEventsURL(for id: UUID) throws -> URL {
        try workspaceFolder(for: id).appendingPathComponent(LoomPaths.toolEventsFileName, isDirectory: false)
    }

    private func workspaceChangesFolder(for id: UUID) throws -> URL {
        try workspaceFolder(for: id).appendingPathComponent(LoomPaths.changesFolderName, isDirectory: true)
    }

    private func ensureLineFilesExist(for id: UUID) throws {
        for url in [try workspaceMessagesURL(for: id), try workspaceToolEventsURL(for: id)] where !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    private func appendLine<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        var data = try lineEncoder.encode(value)
        data.append(0x0A)

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func decodeLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return [] }

        return text.split(separator: "\n").compactMap { line in
            guard let lineData = String(line).data(using: .utf8) else { return nil }
            return try? lineDecoder.decode(type, from: lineData)
        }
    }
}

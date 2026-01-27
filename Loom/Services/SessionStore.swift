import Foundation
import OSLog

actor SessionStore {
    private let log = Logger(subsystem: "com.loom.app", category: "SessionStore")

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    
    private let messageEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let messageDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func bootstrap() throws {
        let root = try LoomPaths.sessionsRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func listSessions() throws -> [Session] {
        try bootstrap()

        let root = try LoomPaths.sessionsRoot()
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var sessions: [Session] = []

        for url in urls {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }

            let metaURL = try LoomPaths.sessionMetadataURL(for: id)
            guard FileManager.default.fileExists(atPath: metaURL.path) else { continue }

            do {
                let data = try Data(contentsOf: metaURL)
                let metadata = try decoder.decode(Session.Metadata.self, from: data)
                sessions.append(Session(id: id, metadata: metadata))
            } catch {
                log.error("Failed to load session \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        // Most recently updated first
        sessions.sort { $0.metadata.updatedAt > $1.metadata.updatedAt }
        return sessions
    }

    func createSession(title: String) throws -> Session {
        try bootstrap()

        let session = Session(metadata: .init(title: title))
        let folder = try LoomPaths.sessionFolder(for: session.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try writeMetadata(session.metadata, for: session.id)

        // 3B: Ensure an empty messages.jsonl exists for this session.
        let messagesURL = try LoomPaths.sessionMessagesURL(for: session.id)
        if !FileManager.default.fileExists(atPath: messagesURL.path) {
            FileManager.default.createFile(atPath: messagesURL.path, contents: nil)
        }

        return session
    }

    func updateMetadata(_ metadata: Session.Metadata, for id: UUID) throws {
        try writeMetadata(metadata, for: id)
    }

    func deleteSession(id: UUID) throws {
        let folder = try LoomPaths.sessionFolder(for: id)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    // 3C: JSONL message storage (append-only)
    func appendMessage(_ message: ChatMessage, sessionID: UUID) throws {
        let url = try LoomPaths.sessionMessagesURL(for: sessionID)

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        var data = try messageEncoder.encode(message)
        data.append(0x0A) // newline

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    func loadMessages(sessionID: UUID) throws -> [ChatMessage] {
        let url = try LoomPaths.sessionMessagesURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }

        // Split by newline, decode each JSON object
        let lines = data.split(separator: 0x0A)
        var messages: [ChatMessage] = []
        messages.reserveCapacity(lines.count)

        for line in lines {
            do {
                let msg = try messageDecoder.decode(ChatMessage.self, from: Data(line))
                messages.append(msg)
            } catch {
                log.error("Failed to decode message line: \(String(describing: error), privacy: .public)")
            }
        }

        return messages
    }

    private func writeMetadata(_ metadata: Session.Metadata, for id: UUID) throws {
        let metaURL = try LoomPaths.sessionMetadataURL(for: id)
        var copy = metadata
        copy.updatedAt = Date()

        let data = try encoder.encode(copy)
        try data.write(to: metaURL, options: [.atomic])
    }
}

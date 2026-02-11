import Foundation
import OSLog
import os.signpost

actor SessionStore {
    private let log = Logger(subsystem: "com.loom.app", category: "SessionStore")
    private let signposter = OSSignposter(subsystem: "com.loom.app", category: "SessionStore")

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
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("bootstrap", id: spID)
        defer { signposter.endInterval("bootstrap", state) }
        let root = try LoomPaths.sessionsRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func listSessions() throws -> [Session] {
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("listSessions", id: spID)
        defer { signposter.endInterval("listSessions", state) }
        try bootstrap()

        let root = try LoomPaths.sessionsRoot()
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var sessions: [Session] = []

        for url in urls {
            autoreleasepool {
                do {
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                    guard values.isDirectory == true else { return }

                    guard let id = UUID(uuidString: url.lastPathComponent) else { return }

                    let metaURL = try LoomPaths.sessionMetadataURL(for: id)
                    guard FileManager.default.fileExists(atPath: metaURL.path) else { return }

                    let data = try Data(contentsOf: metaURL)
                    let metadata = try decoder.decode(Session.Metadata.self, from: data)
                    sessions.append(Session(id: id, metadata: metadata))
                } catch {
                    // Keep going on failure
                    log.error("Failed to load session from \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }

        // Most recently updated first
        sessions.sort { $0.metadata.updatedAt > $1.metadata.updatedAt }
        return sessions
    }

    func createSession(title: String) throws -> Session {
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("createSession", id: spID)
        defer { signposter.endInterval("createSession", state) }
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
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("updateMetadata", id: spID)
        defer { signposter.endInterval("updateMetadata", state) }
        try writeMetadata(metadata, for: id)
    }

    func deleteSession(id: UUID) throws {
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("deleteSession", id: spID)
        defer { signposter.endInterval("deleteSession", state) }
        let folder = try LoomPaths.sessionFolder(for: id)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    // 3C: JSONL message storage (append-only)
    func appendMessage(_ message: ChatMessage, sessionID: UUID) throws {
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("appendMessage", id: spID)
        defer { signposter.endInterval("appendMessage", state) }
        let url = try LoomPaths.sessionMessagesURL(for: sessionID)

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        var data = try messageEncoder.encode(message)
        data.append(0x0A) // newline

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        try handle.seekToEnd()
        try handle.write(contentsOf: data)

        // Keep session ordering in sync with latest activity.
        do {
            var metadata = try loadMetadata(for: sessionID)
            metadata.updatedAt = max(metadata.updatedAt, Date())
            try writeMetadata(metadata, for: sessionID, touchUpdatedAt: false)
        } catch {
            log.error("Failed to update metadata after append: \(String(describing: error), privacy: .public)")
        }
    }

    func loadMessages(sessionID: UUID) throws -> [ChatMessage] {
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("loadMessages", id: spID)
        defer { signposter.endInterval("loadMessages", state) }
        let url = try LoomPaths.sessionMessagesURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }

        return decodeMessages(from: data)
    }

    func loadRecentMessages(sessionID: UUID, limit: Int = 200) throws -> [ChatMessage] {
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("loadRecentMessages", id: spID)
        defer { signposter.endInterval("loadRecentMessages", state) }

        guard limit > 0 else { return [] }

        let url = try LoomPaths.sessionMessagesURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let endOffset = try handle.seekToEnd()
        guard endOffset > 0 else { return [] }
        guard endOffset <= UInt64(Int64.max) else {
            log.error("messages.jsonl too large to tail-read safely (offset=\(endOffset, privacy: .public))")
            return []
        }

        let endOffsetI64 = Int64(endOffset)

        // Read from the end in chunks until we have enough newline boundaries.
        let chunkSize: Int64 = 64 * 1024
        var cursor: Int64 = endOffsetI64
        var buffer = Data()
        var newlineCount = 0

        while cursor > 0 && newlineCount <= limit {
            let readSize = min(chunkSize, cursor)
            cursor -= readSize
            try handle.seek(toOffset: UInt64(cursor))
            let chunk = try handle.read(upToCount: Int(readSize)) ?? Data()

            if chunk.isEmpty { break }

            // Prepend chunk to buffer (we're reading backwards).
            buffer.insert(contentsOf: chunk, at: 0)

            // Count newlines in the accumulated buffer. This is O(n) per loop, but loops are few (chunked).
            newlineCount = buffer.reduce(into: 0) { acc, byte in
                if byte == 0x0A { acc += 1 }
            }

            // If the file is small, avoid looping too much.
            if cursor == 0 { break }
        }

        // Split and decode only the last `limit` lines.
        let lines = buffer.split(separator: 0x0A)
        if lines.isEmpty { return [] }

        let slice = lines.suffix(limit)
        var messages: [ChatMessage] = []
        messages.reserveCapacity(slice.count)

        for line in slice {
            do {
                let msg = try messageDecoder.decode(ChatMessage.self, from: Data(line))
                messages.append(msg)
            } catch {
                log.error("Failed to decode message line (recent): \(String(describing: error), privacy: .public)")
            }
        }

        return messages
    }

    private func decodeMessages(from data: Data) -> [ChatMessage] {
        guard !data.isEmpty else { return [] }

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

    private func writeMetadata(_ metadata: Session.Metadata, for id: UUID, touchUpdatedAt: Bool = true) throws {
        let metaURL = try LoomPaths.sessionMetadataURL(for: id)
        var copy = metadata
        if touchUpdatedAt {
            copy.updatedAt = Date()
        }

        let data = try encoder.encode(copy)
        try data.write(to: metaURL, options: [.atomic])
    }

    private func loadMetadata(for id: UUID) throws -> Session.Metadata {
        let metaURL = try LoomPaths.sessionMetadataURL(for: id)
        let data = try Data(contentsOf: metaURL)
        return try decoder.decode(Session.Metadata.self, from: data)
    }
}

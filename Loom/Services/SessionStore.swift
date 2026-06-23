import Foundation
import OSLog
import os.signpost

actor SessionStore {
    private let log = Logger(subsystem: "com.loom.app", category: "SessionStore")
    private let signposter = OSSignposter(subsystem: "com.loom.app", category: "SessionStore")
    private let sessionsRootOverride: URL?

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

    init(sessionsRoot: URL? = nil) {
        self.sessionsRootOverride = sessionsRoot
    }

    func bootstrap() throws {
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("bootstrap", id: spID)
        defer { signposter.endInterval("bootstrap", state) }
        let root = try sessionsRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func listSessions() throws -> [Session] {
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("listSessions", id: spID)
        defer { signposter.endInterval("listSessions", state) }
        try bootstrap()

        let root = try sessionsRoot()
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

                    let metaURL = try sessionMetadataURL(for: id)
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
        let folder = try sessionFolder(for: session.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try writeMetadata(session.metadata, for: session.id)

        // 3B: Ensure an empty messages.jsonl exists for this session.
        let messagesURL = try sessionMessagesURL(for: session.id)
        if !FileManager.default.fileExists(atPath: messagesURL.path) {
            FileManager.default.createFile(atPath: messagesURL.path, contents: nil)
        }

        return session
    }

    func loadSession(id: UUID) throws -> Session? {
        do {
            let metadata = try loadMetadata(for: id)
            return Session(id: id, metadata: metadata)
        } catch {
            if Self.isMissingFileError(error) {
                return nil
            }
            throw error
        }
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
        let folder = try sessionFolder(for: id)
        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
        } catch {
            if !Self.isMissingFileError(error) {
                throw error
            }
        }
        UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.sessionLastStreamModelKey(for: id))
    }

    func deleteAllSessions() throws {
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("deleteAllSessions", id: spID)
        defer { signposter.endInterval("deleteAllSessions", state) }
        try bootstrap()

        let root = try sessionsRoot()
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in urls {
            if let id = UUID(uuidString: url.lastPathComponent) {
                UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.sessionLastStreamModelKey(for: id))
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                if !Self.isMissingFileError(error) {
                    throw error
                }
            }
        }
    }

    // 3C: JSONL message storage (append-only)
    func appendMessage(_ message: ChatMessage, sessionID: UUID) throws {
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("appendMessage", id: spID)
        defer { signposter.endInterval("appendMessage", state) }
        let url = try sessionMessagesURL(for: sessionID)

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let isFirstAppendedMessage = isMessageFileEmpty(at: url)

        var data = try messageEncoder.encode(message)
        data.append(0x0A) // newline

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        try handle.seekToEnd()
        try handle.write(contentsOf: data)

        // Keep session ordering in sync with latest activity.
        do {
            var metadata = try loadMetadata(for: sessionID)
            if isFirstAppendedMessage,
               message.role == .user,
               Self.isDefaultSessionTitle(metadata.title),
               let autoTitle = Self.suggestedSessionTitle(from: message.content) {
                metadata.title = autoTitle
            }
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
        let url = try sessionMessagesURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }

        return decodeMessages(from: data)
    }

    func loadScratchpad(sessionID: UUID) throws -> String {
        let url = try sessionScratchpadURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }

        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
    }

    func saveScratchpad(_ text: String, sessionID: UUID) throws {
        let url = try sessionScratchpadURL(for: sessionID)
        let data = Data(text.utf8)
        try data.write(to: url, options: [.atomic])
    }

    func loadSessionMemory(sessionID: UUID) throws -> SessionMemory {
        let url = try sessionMemoryURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }

        let data = try Data(contentsOf: url)
        return try decoder.decode(SessionMemory.self, from: data).normalized()
    }

    func saveSessionMemory(_ memory: SessionMemory, sessionID: UUID) throws {
        let url = try sessionMemoryURL(for: sessionID)
        let data = try encoder.encode(memory.normalized())
        try data.write(to: url, options: [.atomic])
    }

    func loadRecentMessages(sessionID: UUID, limit: Int = 200) throws -> [ChatMessage] {
        let spID = signposter.makeSignpostID()
        let state = signposter.beginInterval("loadRecentMessages", id: spID)
        defer { signposter.endInterval("loadRecentMessages", state) }

        guard limit > 0 else { return [] }

        let url = try sessionMessagesURL(for: sessionID)
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
        var chunks: [Data] = []
        chunks.reserveCapacity(32)
        var newlineCount = 0

        while cursor > 0 && newlineCount <= limit {
            let readSize = min(chunkSize, cursor)
            cursor -= readSize
            try handle.seek(toOffset: UInt64(cursor))
            let chunk = try handle.read(upToCount: Int(readSize)) ?? Data()

            if chunk.isEmpty { break }

            // Collect chunks while reading backwards; assemble once at the end to avoid O(n^2) prepends.
            chunks.append(chunk)

            // Count newlines incrementally to avoid rescanning the whole buffer each loop.
            let chunkNewlines = chunk.reduce(into: 0) { acc, byte in
                if byte == 0x0A { acc += 1 }
            }
            newlineCount += chunkNewlines

            // If the file is small, avoid looping too much.
            if cursor == 0 { break }
        }

        // Assemble buffer in forward order.
        let buffer = Data(chunks.reversed().joined())

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
        let metaURL = try sessionMetadataURL(for: id)
        var copy = metadata
        if touchUpdatedAt {
            copy.updatedAt = Date()
        }

        let data = try encoder.encode(copy)
        try data.write(to: metaURL, options: [.atomic])
    }

    private func loadMetadata(for id: UUID) throws -> Session.Metadata {
        let metaURL = try sessionMetadataURL(for: id)
        let data = try Data(contentsOf: metaURL)
        return try decoder.decode(Session.Metadata.self, from: data)
    }

    private func isMessageFileEmpty(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return false
        }
        return fileSize == 0
    }

    private func sessionsRoot() throws -> URL {
        if let sessionsRootOverride {
            return sessionsRootOverride
        }
        return try LoomPaths.sessionsRoot()
    }

    private func sessionFolder(for id: UUID) throws -> URL {
        try sessionsRoot().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func sessionMetadataURL(for id: UUID) throws -> URL {
        try sessionFolder(for: id).appendingPathComponent(LoomPaths.metadataFileName, isDirectory: false)
    }

    private func sessionMessagesURL(for id: UUID) throws -> URL {
        try sessionFolder(for: id).appendingPathComponent(LoomPaths.messagesFileName, isDirectory: false)
    }

    private func sessionScratchpadURL(for id: UUID) throws -> URL {
        try sessionFolder(for: id).appendingPathComponent(LoomPaths.scratchpadFileName, isDirectory: false)
    }

    private func sessionMemoryURL(for id: UUID) throws -> URL {
        try sessionFolder(for: id).appendingPathComponent(LoomPaths.memoryFileName, isDirectory: false)
    }

    private nonisolated static func isDefaultSessionTitle(_ title: String) -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) == Session.Metadata.defaultTitle
    }

    private nonisolated static func suggestedSessionTitle(from request: String) -> String? {
        let normalized = request
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let firstLine = normalized
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !firstLine.isEmpty else {
            return nil
        }

        let collapsed = firstLine
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else {
            return nil
        }

        let sentence = mainSentence(in: collapsed)
        let topicTokens = topicTokens(from: sentence)
        if !topicTokens.isEmpty {
            let summary = topicTokens
                .prefix(maxTopicWordCount)
                .map { formattedTopicToken($0) }
                .joined(separator: " ")
            if let title = summary.nonEmptyTrimmed {
                return truncatedTitle(title, maximumLength: 56, minimumWordBoundary: 18)
            }
        }

        return truncatedTitle(collapsed, maximumLength: 72, minimumWordBoundary: 24)
    }

    private nonisolated static func mainSentence(in text: String) -> String {
        guard let end = text.firstIndex(where: { sentenceTerminatorCharacters.contains($0) }) else {
            return text
        }
        let sentence = String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? text : sentence
    }

    private nonisolated static func topicTokens(from text: String) -> [String] {
        let words = text
            .split(whereSeparator: \.isWhitespace)
            .compactMap { normalizedTopicToken(from: String($0)) }
        guard !words.isEmpty else {
            return []
        }

        let droppedLeadingPrompt = Array(words.drop { leadingPromptWords.contains($0.lowercased()) })
        let candidateWords = droppedLeadingPrompt.isEmpty ? words : droppedLeadingPrompt

        let filteredWords = candidateWords.filter { !topicStopWords.contains($0.lowercased()) }
        if !filteredWords.isEmpty {
            return filteredWords
        }
        return candidateWords
    }

    private nonisolated static func normalizedTopicToken(from raw: String) -> String? {
        var cleaned = raw.trimmingCharacters(in: titleEdgeTrimCharacters)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard let token = cleaned.nonEmptyTrimmed else {
            return nil
        }
        guard token.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
            return nil
        }
        return token
    }

    private nonisolated static func formattedTopicToken(_ token: String) -> String {
        if token == token.lowercased() {
            return token
                .split(separator: "-", omittingEmptySubsequences: false)
                .map { segment in
                    guard let first = segment.first else { return "" }
                    return String(first).uppercased() + segment.dropFirst()
                }
                .joined(separator: "-")
        }
        return token
    }

    private nonisolated static func truncatedTitle(
        _ text: String,
        maximumLength: Int,
        minimumWordBoundary: Int
    ) -> String {
        guard text.count > maximumLength else {
            return text
        }

        var truncated = String(text.prefix(maximumLength))
        if let lastSpace = truncated.lastIndex(of: " "),
           truncated.distance(from: truncated.startIndex, to: lastSpace) >= minimumWordBoundary {
            truncated = String(truncated[..<lastSpace])
        }
        return truncated + "..."
    }

    private nonisolated static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == ENOENT {
            return true
        }
        return false
    }

    private nonisolated static let maxTopicWordCount = 6
    private nonisolated static let sentenceTerminatorCharacters: Set<Character> = [".", "!", "?"]
    private nonisolated static let titleEdgeTrimCharacters = CharacterSet(charactersIn: "\"'`.,!?;:()[]{}<>")
    private nonisolated static let leadingPromptWords: Set<String> = [
        "a", "an", "can", "could", "create", "describe", "do", "draft", "explain", "generate",
        "give", "help", "how", "i", "let", "lets", "list", "make", "me", "my", "need", "plan",
        "please", "provide", "show", "summarize", "tell", "to", "want", "what", "would", "write", "you"
    ]
    private nonisolated static let topicStopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "can", "could", "did", "do", "does",
        "for", "from", "help", "how", "i", "in", "include", "including", "into", "is", "it",
        "me", "my", "of", "on", "or", "our", "please", "show", "tell", "that", "the", "these",
        "this", "to", "us", "was", "we", "were", "what", "when", "where", "which", "who", "why",
        "with", "without", "would", "you", "your"
    ]
}

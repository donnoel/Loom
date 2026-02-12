import Foundation
import Testing
@testable import Loom

private func cleanupSessionFolder(id: UUID) {
    guard let folder = try? LoomPaths.sessionFolder(for: id) else { return }
    guard FileManager.default.fileExists(atPath: folder.path) else { return }
    try? FileManager.default.removeItem(at: folder)
}

private func appendRawJSONLLine(_ line: String, to url: URL) throws {
    let payload = Data("\(line)\n".utf8)

    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }

    try handle.seekToEnd()
    try handle.write(contentsOf: payload)
}

private func decodeMetadata(at url: URL) throws -> Session.Metadata {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(Session.Metadata.self, from: data)
}

private func fixedDate(_ iso8601: String) -> Date {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: iso8601) else {
        Issue.record("Failed to build fixed test date: \(iso8601)")
        return Date(timeIntervalSince1970: 0)
    }
    return date
}

struct SessionStoreTests {
    @Test
    func createSessionCreatesMetadataAndMessagesFiles() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Test \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        let metadataURL = try LoomPaths.sessionMetadataURL(for: session.id)
        let messagesURL = try LoomPaths.sessionMessagesURL(for: session.id)

        #expect(FileManager.default.fileExists(atPath: metadataURL.path))
        #expect(FileManager.default.fileExists(atPath: messagesURL.path))

        let loaded = try await store.loadMessages(sessionID: session.id)
        #expect(loaded.isEmpty)
    }

    @Test
    func appendAndLoadMessagesPreservesAppendOrder() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Append \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        let user = ChatMessage(
            role: .user,
            content: "Hello",
            createdAt: fixedDate("2026-01-01T00:00:00Z")
        )
        let assistant = ChatMessage(
            role: .assistant,
            content: "Hi there",
            createdAt: fixedDate("2026-01-01T00:00:01Z")
        )

        try await store.appendMessage(user, sessionID: session.id)
        try await store.appendMessage(assistant, sessionID: session.id)

        let loaded = try await store.loadMessages(sessionID: session.id)
        #expect(loaded == [user, assistant])
    }

    @Test
    func loadMessagesSkipsMalformedJSONLLines() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Malformed \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        let first = ChatMessage(
            role: .user,
            content: "First",
            createdAt: fixedDate("2026-01-01T00:00:00Z")
        )
        let second = ChatMessage(
            role: .assistant,
            content: "Second",
            createdAt: fixedDate("2026-01-01T00:00:01Z")
        )

        try await store.appendMessage(first, sessionID: session.id)
        let messagesURL = try LoomPaths.sessionMessagesURL(for: session.id)
        try appendRawJSONLLine("not-json", to: messagesURL)
        try await store.appendMessage(second, sessionID: session.id)

        let loaded = try await store.loadMessages(sessionID: session.id)
        #expect(loaded == [first, second])
    }

    @Test
    func updateMetadataPersistsTitleChange() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Original \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        var metadata = session.metadata
        let updatedTitle = "Renamed \(UUID().uuidString)"
        metadata.title = updatedTitle

        try await store.updateMetadata(metadata, for: session.id)

        let metadataURL = try LoomPaths.sessionMetadataURL(for: session.id)
        let updated = try decodeMetadata(at: metadataURL)
        #expect(updated.title == updatedTitle)
    }

    @Test
    func deleteSessionRemovesSessionFolder() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Delete \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        let folderURL = try LoomPaths.sessionFolder(for: session.id)
        #expect(FileManager.default.fileExists(atPath: folderURL.path))

        try await store.deleteSession(id: session.id)
        #expect(!FileManager.default.fileExists(atPath: folderURL.path))
    }
}

struct LoomStatusSnapshotTests {
    @Test
    func readinessIsNotReadyWhenOllamaIsUnavailable() {
        let snapshot = LoomStatusSnapshot(
            ollamaReachable: false,
            installedModelCount: 2,
            activeModelTag: "llama3.2",
            offlineAvailable: false
        )

        #expect(snapshot.readiness == .notReady)
        #expect(snapshot.issues == [.ollamaNotRunning])
    }

    @Test
    func readinessNeedsSetupWhenModelMissing() {
        let snapshot = LoomStatusSnapshot(
            ollamaReachable: true,
            installedModelCount: 1,
            activeModelTag: nil,
            offlineAvailable: false
        )

        #expect(snapshot.readiness == .needsSetup)
        #expect(snapshot.issues == [.noModelSelected])
    }

    @Test
    func readinessIsReadyWhenOllamaAndModelAreAvailable() {
        let snapshot = LoomStatusSnapshot(
            ollamaReachable: true,
            installedModelCount: 2,
            activeModelTag: "llama3.2",
            offlineAvailable: true
        )

        #expect(snapshot.readiness == .ready)
        #expect(snapshot.issues.isEmpty)
    }
}

struct StringTrimmingTests {
    @Test
    func nonEmptyTrimmedReturnsNilForWhitespaceOnlyValues() {
        #expect("   \n\t".nonEmptyTrimmed == nil)
    }

    @Test
    func nonEmptyTrimmedReturnsTrimmedContent() {
        #expect("  hello  ".nonEmptyTrimmed == "hello")
    }
}

struct ChatDisplayFormatterTests {
    @Test
    func formatAddsParagraphBreaksForShortPlainText() {
        let input = "Loom helps you chat locally. It keeps your data on this Mac. You can choose a model and start quickly."
        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("\n\n"))
        #expect(formatted.contains("Loom helps you chat locally."))
        #expect(formatted.contains("You can choose a model and start quickly."))
    }

    @Test
    func formatNormalizesInlineNumberedLists() {
        let input = "To get started, follow these steps. 1) Open Models. 2) Choose llama3. 3) Send a message."
        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("\n1. Open Models."))
        #expect(formatted.contains("\n2. Choose llama3."))
        #expect(formatted.contains("\n3. Send a message."))
    }

    @Test
    func formatRepairsSentenceSpacingWithoutBreakingTechnicalTokens() {
        let input = "First sentence.Second sentence references v1.2.3 and example.com."
        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("First sentence. Second sentence"))
        #expect(formatted.contains("v1.2.3"))
        #expect(formatted.contains("example.com"))
        #expect(!formatted.contains("example. com"))
        #expect(!formatted.contains("v1. 2. 3"))
    }

    @Test
    func formatImprovesDenseSectionedOutput() {
        let input = """
        Determining which scientific discipline is the most fundamental can be a matter of perspective and often depends on how one defines "fundamental." Each discipline plays a crucial role and contributes to our understanding of the world in unique ways. However, some might argue that physics holds a foundational position due to its focus on the basic laws governing matter, energy, space, and time.Why Physics isConsidered Fundamental:Basic Laws: Physics seeks to understand the fundamental forces that govern the behavior of all matter in the universe.Building Blocks: Many other sciences rely on physics principles.OtherSciences:Chemistry: While chemistry is incredibly important, it builds upon the principles of physics.Conclusion:While all scientific disciplines are essential, physics often stands out as the most fundamental.
        """

        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("Why Physics is Considered Fundamental:"))
        #expect(formatted.contains("Basic Laws:"))
        #expect(formatted.contains("Building Blocks:"))
        #expect(formatted.contains("Other Sciences:"))
        #expect(formatted.contains("\n\nChemistry:"))
        #expect(formatted.contains("Conclusion:\n\nWhile all scientific disciplines are essential"))
        #expect(!formatted.contains("isConsidered"))
        #expect(!formatted.contains("OtherSciences"))
    }
}

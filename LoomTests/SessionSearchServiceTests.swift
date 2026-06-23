import Foundation
import Testing
@testable import Loom

@Suite(.serialized)
struct SessionSearchServiceTests {
    private func withTemporarySessionsRoot(_ body: @escaping (SessionStore, SessionSearchService) async throws -> Void) async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoomSearchTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = SessionStore(sessionsRoot: tempRoot)
        let service = SessionSearchService(store: store)
        try await body(store, service)
    }

    @Test
    func searchFindsSessionTitleMatches() async throws {
        try await withTemporarySessionsRoot { store, service in
            let session = try await store.createSession(title: "Roadmap Planning")

            let results = await service.search(query: "roadmap", in: [session])

            #expect(results.count == 1)
            #expect(results[0].source == .title)
            #expect(results[0].sessionID == session.id)
            #expect(results[0].messageID == nil)
        }
    }

    @Test
    func searchFindsMessageContentMatches() async throws {
        try await withTemporarySessionsRoot { store, service in
            let session = try await store.createSession(title: "General")
            let message = ChatMessage(role: .assistant, content: "The release checklist needs one final approval.")
            try await store.appendMessage(message, sessionID: session.id)

            let results = await service.search(query: "checklist", in: [session])

            #expect(results.count == 1)
            #expect(results[0].source == .message)
            #expect(results[0].sessionID == session.id)
            #expect(results[0].messageID == message.id)
            #expect(results[0].messageRole == .assistant)
        }
    }

    @Test
    func searchReturnsNoResultsForEmptyQuery() async throws {
        try await withTemporarySessionsRoot { store, service in
            let session = try await store.createSession(title: "Anything")
            try await store.appendMessage(ChatMessage(role: .user, content: "Hello"), sessionID: session.id)

            let results = await service.search(query: "   ", in: [session])

            #expect(results.isEmpty)
        }
    }

    @Test
    func searchReturnsNoResultsWhenNothingMatches() async throws {
        try await withTemporarySessionsRoot { store, service in
            let session = try await store.createSession(title: "Garden Notes")
            try await store.appendMessage(ChatMessage(role: .user, content: "Tomatoes need more sun."), sessionID: session.id)

            let results = await service.search(query: "invoice", in: [session])

            #expect(results.isEmpty)
        }
    }
}

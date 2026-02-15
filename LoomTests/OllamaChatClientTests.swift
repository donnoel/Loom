import Foundation
import Testing
@testable import Loom

private struct MockHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

private typealias MockHTTPHandler = @Sendable (URLRequest) throws -> MockHTTPResponse

private actor MockURLProtocolState {
    private var handlers: [String: MockHTTPHandler] = [:]
    private var requestsByToken: [String: [URLRequest]] = [:]

    func configure(token: String, handler: @escaping MockHTTPHandler) {
        handlers[token] = handler
        requestsByToken[token] = []
    }

    func currentHandler(for token: String) -> MockHTTPHandler? {
        handlers[token]
    }

    func record(_ request: URLRequest, token: String) {
        requestsByToken[token, default: []].append(request)
    }

    func recordedRequests(for token: String) -> [URLRequest] {
        requestsByToken[token] ?? []
    }
}

private final class MockURLProtocol: URLProtocol {
    private static let state = MockURLProtocolState()
    static let tokenHeader = "X-Loom-Mock-Token"

    static func configure(token: String, handler: @escaping MockHTTPHandler) async {
        await state.configure(token: token, handler: handler)
    }

    static func recordedRequests(token: String) async -> [URLRequest] {
        await state.recordedRequests(for: token)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Task {
            do {
                guard let token = request.value(forHTTPHeaderField: Self.tokenHeader) else {
                    throw URLError(.unsupportedURL)
                }

                await Self.state.record(request, token: token)

                guard let handler = await Self.state.currentHandler(for: token) else {
                    throw URLError(.unsupportedURL)
                }

                let mock = try handler(request)
                let responseURL = request.url ?? URL(string: "http://localhost:11434")!
                guard let response = HTTPURLResponse(
                    url: responseURL,
                    statusCode: mock.statusCode,
                    httpVersion: nil,
                    headerFields: mock.headers
                ) else {
                    throw URLError(.badServerResponse)
                }

                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                if !mock.body.isEmpty {
                    client?.urlProtocol(self, didLoad: mock.body)
                }
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private actor DeltaCollector {
    private var values: [String] = []

    func append(_ delta: String) {
        values.append(delta)
    }

    func snapshot() -> [String] {
        values
    }
}

private final class LockedPullProgresses: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [PullProgress] = []

    func append(_ progress: PullProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }

    func snapshot() -> [PullProgress] {
        lock.lock()
        let snapshot = values
        lock.unlock()
        return snapshot
    }
}

private func mockedSession(token: String) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpAdditionalHeaders = [MockURLProtocol.tokenHeader: token]
    return URLSession(configuration: configuration)
}

private func jsonResponse(statusCode: Int, body: String) -> MockHTTPResponse {
    MockHTTPResponse(
        statusCode: statusCode,
        headers: ["Content-Type": "application/json"],
        body: Data(body.utf8)
    )
}

private func textResponse(statusCode: Int, body: String) -> MockHTTPResponse {
    MockHTTPResponse(
        statusCode: statusCode,
        headers: ["Content-Type": "text/plain"],
        body: Data(body.utf8)
    )
}

private func makeClients(
    installed: Bool = true,
    handler: @escaping MockHTTPHandler
) async -> (OllamaClient, OllamaChatClient, String) {
    let token = UUID().uuidString
    await MockURLProtocol.configure(token: token, handler: handler)
    let session = mockedSession(token: token)
    let ollamaClient = OllamaClient(session: session, installedDetector: { installed })
    let chatClient = OllamaChatClient(ollamaClient: ollamaClient, session: session)
    return (ollamaClient, chatClient, token)
}

struct OllamaChatClientTests {
    @Test
    func parseStreamLineDelta() throws {
        let line = "{\"message\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"done\":false}"
        let event = try OllamaChatClient.parseStreamLine(line)

        #expect(event?.delta == "Hello")
        #expect(event?.done == false)
        #expect(event?.error == nil)
    }

    @Test
    func parseStreamLineDone() throws {
        let line = "{\"done\":true}"
        let event = try OllamaChatClient.parseStreamLine(line)

        #expect(event?.delta == "")
        #expect(event?.done == true)
        #expect(event?.error == nil)
    }

    @Test
    func parseStreamLineError() throws {
        let line = "{\"error\":\"model not found\",\"done\":true}"
        let event = try OllamaChatClient.parseStreamLine(line)

        #expect(event?.error == "model not found")
        #expect(event?.done == true)
    }

    @Test
    func parseStreamLineIgnoresWhitespace() throws {
        #expect(try OllamaChatClient.parseStreamLine("   ") == nil)
    }

    @Test
    func parseStreamLineTrimsOuterWhitespace() throws {
        let line = "  {\"message\":{\"content\":\"Hi\"},\"done\":false}  "
        let event = try OllamaChatClient.parseStreamLine(line)

        #expect(event?.delta == "Hi")
        #expect(event?.done == false)
        #expect(event?.error == nil)
    }

    @Test
    func parseStreamLineReturnsErrorAndDoneWhenServerSignalsFailure() throws {
        let line = "{\"message\":{\"content\":\"\"},\"error\":\"model is loading\",\"done\":true}"
        let event = try OllamaChatClient.parseStreamLine(line)

        #expect(event?.delta == "")
        #expect(event?.done == true)
        #expect(event?.error == "model is loading")
    }

    @Test
    func parseStreamLineThrowsOnMalformedJSON() {
        let malformed = "{\"message\":{\"content\":\"Hello\"},\"done\":false"

        var didThrow = false
        do {
            _ = try OllamaChatClient.parseStreamLine(malformed)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }
}

@Suite(.serialized)
struct OllamaChatClientTransportTests {
    @Test
    func streamChatRejectsEmptyModelBeforeNetworkCall() async {
        let (_, chatClient, token) = await makeClients { _ in
            jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
        }

        do {
            try await chatClient.streamChat(model: "   ", messages: []) { _ in }
            Issue.record("Expected streamChat to throw .invalidRequest")
        } catch let error as OllamaChatClient.StreamError {
            switch error {
            case .invalidRequest:
                #expect(true)
            default:
                Issue.record("Unexpected stream error: \(String(describing: error))")
            }
        } catch {
            Issue.record("Unexpected non-stream error: \(String(describing: error))")
        }

        let requests = await MockURLProtocol.recordedRequests(token: token)
        #expect(requests.isEmpty)
    }

    @Test
    func streamChatYieldsDeltasUntilDone() async throws {
        let (_, chatClient, _) = await makeClients { request in
            switch request.url?.path {
            case "/api/version":
                return jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
            case "/api/chat":
                let streamBody = """
                {"message":{"content":"Hello"},"done":false}
                {"message":{"content":" world"},"done":false}
                {"done":true}
                """
                return jsonResponse(statusCode: 200, body: streamBody)
            default:
                return textResponse(statusCode: 404, body: "not found")
            }
        }

        let collector = DeltaCollector()
        try await chatClient.streamChat(model: "llama3", messages: []) { delta in
            await collector.append(delta)
        }

        #expect(await collector.snapshot() == ["Hello", " world"])
    }

    @Test
    func streamChatThrowsOllamaUnavailableWhenNoReachableBaseURL() async {
        let (_, chatClient, _) = await makeClients(installed: true) { request in
            if request.url?.path == "/api/version" {
                return textResponse(statusCode: 503, body: "down")
            }
            return textResponse(statusCode: 404, body: "not found")
        }

        do {
            try await chatClient.streamChat(model: "llama3", messages: []) { _ in }
            Issue.record("Expected streamChat to throw .ollamaUnavailable")
        } catch let error as OllamaChatClient.StreamError {
            switch error {
            case .ollamaUnavailable:
                #expect(true)
            default:
                Issue.record("Unexpected stream error: \(String(describing: error))")
            }
        } catch {
            Issue.record("Unexpected non-stream error: \(String(describing: error))")
        }
    }

    @Test
    func streamChatMapsServerErrorFromHTTPBody() async {
        let (_, chatClient, _) = await makeClients { request in
            switch request.url?.path {
            case "/api/version":
                return jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
            case "/api/chat":
                return jsonResponse(statusCode: 404, body: #"{"error":"model 'llama3' not found"}"#)
            default:
                return textResponse(statusCode: 404, body: "not found")
            }
        }

        do {
            try await chatClient.streamChat(model: "llama3", messages: []) { _ in }
            Issue.record("Expected streamChat to throw .serverError")
        } catch let error as OllamaChatClient.StreamError {
            switch error {
            case .serverError(let message):
                #expect(message == "model 'llama3' not found")
            default:
                Issue.record("Unexpected stream error: \(String(describing: error))")
            }
        } catch {
            Issue.record("Unexpected non-stream error: \(String(describing: error))")
        }
    }

    @Test
    func streamChatFallsBackToHTTPStatusErrorWithoutServerMessage() async {
        let (_, chatClient, _) = await makeClients { request in
            switch request.url?.path {
            case "/api/version":
                return jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
            case "/api/chat":
                return textResponse(statusCode: 502, body: "gateway timeout")
            default:
                return textResponse(statusCode: 404, body: "not found")
            }
        }

        do {
            try await chatClient.streamChat(model: "llama3", messages: []) { _ in }
            Issue.record("Expected streamChat to throw .httpStatus")
        } catch let error as OllamaChatClient.StreamError {
            switch error {
            case .httpStatus(let code):
                #expect(code == 502)
            default:
                Issue.record("Unexpected stream error: \(String(describing: error))")
            }
        } catch {
            Issue.record("Unexpected non-stream error: \(String(describing: error))")
        }
    }

    @Test
    func streamChatThrowsServerErrorWhenChunkCarriesErrorField() async {
        let (_, chatClient, _) = await makeClients { request in
            switch request.url?.path {
            case "/api/version":
                return jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
            case "/api/chat":
                let streamBody = """
                {"message":{"content":""},"error":"model is loading","done":true}
                """
                return jsonResponse(statusCode: 200, body: streamBody)
            default:
                return textResponse(statusCode: 404, body: "not found")
            }
        }

        do {
            try await chatClient.streamChat(model: "llama3", messages: []) { _ in }
            Issue.record("Expected streamChat to throw .serverError")
        } catch let error as OllamaChatClient.StreamError {
            switch error {
            case .serverError(let message):
                #expect(message == "model is loading")
            default:
                Issue.record("Unexpected stream error: \(String(describing: error))")
            }
        } catch {
            Issue.record("Unexpected non-stream error: \(String(describing: error))")
        }
    }

    @Test
    func streamChatThrowsBadResponseWhenStreamEndsWithoutDoneChunk() async {
        let (_, chatClient, _) = await makeClients { request in
            switch request.url?.path {
            case "/api/version":
                return jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
            case "/api/chat":
                let streamBody = """
                {"message":{"content":"partial"},"done":false}
                """
                return jsonResponse(statusCode: 200, body: streamBody)
            default:
                return textResponse(statusCode: 404, body: "not found")
            }
        }

        do {
            try await chatClient.streamChat(model: "llama3", messages: []) { _ in }
            Issue.record("Expected streamChat to throw .badResponse")
        } catch let error as OllamaChatClient.StreamError {
            switch error {
            case .badResponse:
                #expect(true)
            default:
                Issue.record("Unexpected stream error: \(String(describing: error))")
            }
        } catch {
            Issue.record("Unexpected non-stream error: \(String(describing: error))")
        }
    }
}

@Suite(.serialized)
struct OllamaClientNetworkTests {
    @Test
    func diagnoseCachesLastReachableBaseURL() async {
        let (client, _, token) = await makeClients { request in
            if request.url?.path == "/api/version" {
                return jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
            }
            return textResponse(statusCode: 404, body: "not found")
        }

        let first = await client.diagnose()
        let second = await client.diagnose()

        #expect(first.isRunning)
        #expect(second.isRunning)
        #expect(first.reachableBaseURL == second.reachableBaseURL)

        let versionRequests = await MockURLProtocol.recordedRequests(token: token)
            .filter { $0.url?.path == "/api/version" }
        #expect(versionRequests.count == 2)
        #expect(Set(versionRequests.compactMap { $0.url?.host }) == Set(["localhost"]))
    }

    @Test
    func listModelsSortsByTagAndParsesMetadata() async throws {
        let (client, _, _) = await makeClients { request in
            switch request.url?.path {
            case "/api/version":
                return jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
            case "/api/tags":
                let payload = """
                {
                  "models": [
                    {
                      "name": "zeta:7b",
                      "size": 900,
                      "modified_at": "2026-02-12T10:11:12Z",
                      "details": { "parameter_size": "7B" }
                    },
                    {
                      "name": "alpha:3b",
                      "size": 300,
                      "modified_at": "2026-02-12T10:11:12.321Z",
                      "details": { "parameter_size": "3B" }
                    }
                  ]
                }
                """
                return jsonResponse(statusCode: 200, body: payload)
            default:
                return textResponse(statusCode: 404, body: "not found")
            }
        }

        let models = try await client.listModels()
        #expect(models.map(\.tag) == ["alpha:3b", "zeta:7b"])
        #expect(models[0].sizeBytes == 300)
        #expect(models[0].parameterSize == "3B")
        #expect(models[1].sizeBytes == 900)
        #expect(models[1].parameterSize == "7B")
        #expect(models[0].modifiedAt != nil)
        #expect(models[1].modifiedAt != nil)
    }

    @Test
    func deleteModelRejectsEmptyNameBeforeNetworkCall() async {
        let (client, _, token) = await makeClients { _ in
            jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
        }

        do {
            try await client.deleteModel(name: "   ")
            Issue.record("Expected deleteModel to throw .invalidRequest")
        } catch let error as DeleteModelError {
            switch error {
            case .invalidRequest:
                #expect(true)
            default:
                Issue.record("Unexpected delete error: \(String(describing: error))")
            }
        } catch {
            Issue.record("Unexpected non-delete error: \(String(describing: error))")
        }

        let requests = await MockURLProtocol.recordedRequests(token: token)
        #expect(requests.isEmpty)
    }

    @Test
    func deleteModelPropagatesHTTPStatusAndSnippet() async {
        let (client, _, _) = await makeClients { request in
            switch request.url?.path {
            case "/api/version":
                return jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
            case "/api/delete":
                return textResponse(statusCode: 500, body: "model not found")
            default:
                return textResponse(statusCode: 404, body: "not found")
            }
        }

        do {
            try await client.deleteModel(name: "phi4:latest")
            Issue.record("Expected deleteModel to throw .httpStatus")
        } catch let error as DeleteModelError {
            switch error {
            case .httpStatus(let code, let snippet):
                #expect(code == 500)
                #expect(snippet == "model not found")
            default:
                Issue.record("Unexpected delete error: \(String(describing: error))")
            }
        } catch {
            Issue.record("Unexpected non-delete error: \(String(describing: error))")
        }
    }

    @Test
    func pullModelReportsProgressFromStreamingChunks() async throws {
        let (client, _, _) = await makeClients { request in
            switch request.url?.path {
            case "/api/version":
                return jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
            case "/api/pull":
                let streamBody = """
                {"status":"Downloading","completed":50,"total":100}
                {"status":"Finalizing","completed":100,"total":100}
                """
                return jsonResponse(statusCode: 200, body: streamBody)
            default:
                return textResponse(statusCode: 404, body: "not found")
            }
        }

        let capturedProgress = LockedPullProgresses()
        try await client.pullModel(name: "phi4:latest") { progress in
            capturedProgress.append(progress)
        }

        let captured = capturedProgress.snapshot()
        #expect(captured.count == 2)
        #expect(captured.first?.status == "Downloading")
        #expect(captured.first?.fraction == 0.5)
        #expect(captured.last?.status == "Finalizing")
        #expect(captured.last?.fraction == 1.0)
    }

    @Test
    func pullModelRejectsEmptyNameBeforeNetworkCall() async {
        let (client, _, token) = await makeClients { _ in
            jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
        }

        do {
            try await client.pullModel(name: "  ") { _ in }
            Issue.record("Expected pullModel to throw .invalidRequest")
        } catch let error as PullModelError {
            switch error {
            case .invalidRequest:
                #expect(true)
            default:
                Issue.record("Unexpected pull error: \(String(describing: error))")
            }
        } catch {
            Issue.record("Unexpected non-pull error: \(String(describing: error))")
        }

        let requests = await MockURLProtocol.recordedRequests(token: token)
        #expect(requests.isEmpty)
    }

    @Test
    func pullModelThrowsServerErrorWhenChunkContainsErrorField() async {
        let (client, _, _) = await makeClients { request in
            switch request.url?.path {
            case "/api/version":
                return jsonResponse(statusCode: 200, body: #"{"version":"0.7.0"}"#)
            case "/api/pull":
                return jsonResponse(statusCode: 200, body: #"{"error":"disk full"}"#)
            default:
                return textResponse(statusCode: 404, body: "not found")
            }
        }

        do {
            try await client.pullModel(name: "phi4:latest") { _ in }
            Issue.record("Expected pullModel to throw .serverError")
        } catch let error as PullModelError {
            switch error {
            case .serverError(let message):
                #expect(message == "disk full")
            default:
                Issue.record("Unexpected pull error: \(String(describing: error))")
            }
        } catch {
            Issue.record("Unexpected non-pull error: \(String(describing: error))")
        }
    }
}

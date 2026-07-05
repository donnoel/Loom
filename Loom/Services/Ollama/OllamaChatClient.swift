import Foundation

nonisolated struct OllamaChatStreamEvent: Equatable, Sendable {
    let delta: String
    let done: Bool
    let error: String?
}

protocol OllamaChatStreaming: Actor {
    func streamChat(
        model: String,
        messages: [ChatMessage],
        onDelta: @Sendable (String) async -> Void
    ) async throws
}

nonisolated enum OllamaChatResponseFormat: String, Sendable {
    case json
}

protocol OllamaStructuredChatStreaming: OllamaChatStreaming {
    func streamChat(
        model: String,
        messages: [ChatMessage],
        responseFormat: OllamaChatResponseFormat,
        onDelta: @Sendable (String) async -> Void
    ) async throws
}

actor OllamaChatClient: OllamaChatStreaming {
    enum StreamError: LocalizedError, Sendable {
        case ollamaUnavailable
        case invalidRequest
        case badResponse
        case serverError(String)
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .ollamaUnavailable:
                return "Loom can’t reach Ollama. Start it to continue."
            case .invalidRequest:
                return "Loom couldn’t prepare this request."
            case .badResponse:
                return "Loom got an unexpected response."
            case .serverError(let message):
                return message
            case .httpStatus:
                return "Loom couldn’t stream a response right now."
            }
        }
    }

    private let ollamaClient: OllamaClient
    private let session: URLSession

    init(ollamaClient: OllamaClient = OllamaClient(), session: URLSession? = nil) {
        self.ollamaClient = ollamaClient

        if let session {
            self.session = session
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60 * 30
        self.session = URLSession(configuration: configuration)
    }

    func streamChat(
        model: String,
        messages: [ChatMessage],
        onDelta: @Sendable (String) async -> Void
    ) async throws {
        try await streamChat(model: model, messages: messages, responseFormat: nil, onDelta: onDelta)
    }
}

extension OllamaChatClient: OllamaStructuredChatStreaming {
    func streamChat(
        model: String,
        messages: [ChatMessage],
        responseFormat: OllamaChatResponseFormat,
        onDelta: @Sendable (String) async -> Void
    ) async throws {
        try await streamChat(model: model, messages: messages, responseFormat: Optional(responseFormat), onDelta: onDelta)
    }

    private func streamChat(
        model: String,
        messages: [ChatMessage],
        responseFormat: OllamaChatResponseFormat?,
        onDelta: @Sendable (String) async -> Void
    ) async throws {
        guard let selectedModel = model.nonEmptyTrimmed else {
            throw StreamError.invalidRequest
        }

        let diagnosis = await ollamaClient.diagnose()
        guard let baseURL = diagnosis.reachableBaseURL else {
            throw StreamError.ollamaUnavailable
        }

        let payload = ChatRequest(
            model: selectedModel,
            messages: messages.map { ChatRequest.Message(role: $0.role.rawValue, content: $0.content) },
            stream: true,
            format: responseFormat?.rawValue
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw StreamError.badResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let body = try await readBodySnippet(from: bytes)
            if let serverMessage = parseServerErrorMessage(from: body) {
                throw StreamError.serverError(serverMessage)
            }
            throw StreamError.httpStatus(http.statusCode)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard let event = try Self.parseStreamLine(line) else {
                continue
            }

            if let error = event.error?.nonEmptyTrimmed {
                throw StreamError.serverError(error)
            }

            if !event.delta.isEmpty {
                await onDelta(event.delta)
            }

            if event.done {
                return
            }
        }

        throw StreamError.badResponse
    }

    static func parseStreamLine(_ line: String) throws -> OllamaChatStreamEvent? {
        guard let trimmed = line.nonEmptyTrimmed,
              let data = trimmed.data(using: .utf8)
        else {
            return nil
        }

        let chunk = try JSONDecoder().decode(ChatStreamChunk.self, from: data)
        return OllamaChatStreamEvent(
            delta: chunk.message?.content ?? "",
            done: chunk.done ?? false,
            error: chunk.error
        )
    }

    private func readBodySnippet(from bytes: URLSession.AsyncBytes) async throws -> String {
        var body = ""

        for try await line in bytes.lines {
            if !body.isEmpty {
                body.append("\n")
            }

            body.append(line)

            if body.count >= 1_200 {
                break
            }
        }

        return body
    }

    private func parseServerErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ChatErrorBody.self, from: data)
        else {
            return nil
        }

        return payload.error.nonEmptyTrimmed
    }
}

nonisolated private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
    let format: String?
}

nonisolated private struct ChatStreamChunk: Decodable {
    struct Message: Decodable {
        let content: String?
    }

    let message: Message?
    let done: Bool?
    let error: String?
}

nonisolated private struct ChatErrorBody: Decodable {
    let error: String
}

import Foundation
import OSLog

nonisolated struct OllamaModel: Identifiable, Hashable, Sendable {
    let tag: String
    let sizeBytes: Int64?

    init(tag: String, sizeBytes: Int64? = nil) {
        self.tag = tag
        self.sizeBytes = sizeBytes
    }

    var id: String { tag }
}

nonisolated struct PullProgress: Equatable, Sendable {
    let status: String
    let completed: Int64?
    let total: Int64?

    var fraction: Double? {
        guard let total, total > 0, let completed else { return nil }
        return Double(completed) / Double(total)
    }
}

nonisolated enum PullModelError: LocalizedError, Sendable {
    case invalidRequest
    case badResponse
    case httpStatus(Int, String?)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Loom couldn’t prepare this model install request."
        case .badResponse:
            return "Loom got an unexpected response while installing."
        case .httpStatus(_, let snippet):
            return snippet?.nonEmptyTrimmed ?? "Loom couldn’t install this model right now."
        case .serverError(let message):
            return message
        }
    }
}

/// A plain-language diagnosis for guiding non-technical users.
nonisolated struct OllamaDiagnosis: Hashable, Sendable {
    enum NextStep: Hashable, Sendable {
        case ready
        case startOllama
        case installOllama
        case tryAgain
    }

    /// Whether Ollama appears installed (either the app bundle or the CLI binary exists).
    let isInstalled: Bool

    /// Whether Loom can reach the local Ollama server.
    let isRunning: Bool

    /// The base URL that responded successfully (if running).
    let reachableBaseURL: URL?

    /// A user-friendly one-liner explaining the state.
    let summary: String

    /// The most appropriate next step.
    let nextStep: NextStep
}

protocol OllamaStatusProviding: Actor {
    func diagnose() async -> OllamaDiagnosis
    func listModels() async throws -> [OllamaModel]
    func deleteModel(name: String) async throws
    func pullModel(name: String, onProgress: @Sendable (PullProgress) -> Void) async throws
}

actor OllamaClient: OllamaStatusProviding {
    private let log = Logger(subsystem: "com.loom.app", category: "OllamaClient")

    /// Try multiple localhost variants to be resilient across environments.
    private let candidateBaseURLs: [URL] = [
        URL(string: "http://localhost:11434")!,
        URL(string: "http://127.0.0.1:11434")!,
        URL(string: "http://[::1]:11434")!
    ]

    /// Slightly longer than 1.5s to avoid false negatives during cold starts.
    private let timeout: TimeInterval = 3.0

    /// Cache the last known good base URL to avoid re-probing on every call.
    private var cachedReachableBaseURL: URL?

    /// Returns a diagnosis that is suitable for a “brain-dead helpful” UI.
    func diagnose() async -> OllamaDiagnosis {
        let installed = Self.detectInstalled()

        // If we already have a working base URL, try it first.
        if let cached = cachedReachableBaseURL {
            if await canReach(baseURL: cached) {
                return OllamaDiagnosis(
                    isInstalled: installed,
                    isRunning: true,
                    reachableBaseURL: cached,
                    summary: "Ready",
                    nextStep: .ready
                )
            } else {
                cachedReachableBaseURL = nil
            }
        }

        // Probe all candidates and cache the first that responds.
        for base in candidateBaseURLs {
            if await canReach(baseURL: base) {
                cachedReachableBaseURL = base
                return OllamaDiagnosis(
                    isInstalled: installed,
                    isRunning: true,
                    reachableBaseURL: base,
                    summary: "Ready",
                    nextStep: .ready
                )
            }
        }

        // Not reachable.
        if installed {
            return OllamaDiagnosis(
                isInstalled: true,
                isRunning: false,
                reachableBaseURL: nil,
                summary: "Ollama is installed but not running",
                nextStep: .startOllama
            )
        } else {
            return OllamaDiagnosis(
                isInstalled: false,
                isRunning: false,
                reachableBaseURL: nil,
                summary: "Ollama is not installed yet",
                nextStep: .installOllama
            )
        }
    }

    /// Lists installed models via Ollama’s local API.
    func listModels() async throws -> [OllamaModel] {
        let baseURL = try await resolveReachableBaseURL()
        let response = try await fetchTags(baseURL: baseURL)
        let models = response.models.map { OllamaModel(tag: $0.name, sizeBytes: $0.size) }
        return models.sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    func deleteModel(name: String) async throws {
        guard let modelName = name.nonEmptyTrimmed else {
            throw URLError(.badURL)
        }

        let baseURL = try await resolveReachableBaseURL()
        var request = URLRequest(url: baseURL.appendingPathComponent("api/delete"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeleteModelRequest(model: modelName))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func pullModel(name: String, onProgress: @Sendable (PullProgress) -> Void) async throws {
        guard let modelName = name.nonEmptyTrimmed else {
            throw PullModelError.invalidRequest
        }

        let baseURL = try await resolveReachableBaseURL()
        var request = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PullModelRequest(model: modelName))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PullModelError.badResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let snippet = try await readBodySnippet(from: bytes)
            throw PullModelError.httpStatus(http.statusCode, snippet.nonEmptyTrimmed)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard let trimmed = line.nonEmptyTrimmed,
                  let data = trimmed.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(PullModelChunk.self, from: data) else {
                continue
            }

            if let error = chunk.error?.nonEmptyTrimmed {
                throw PullModelError.serverError(error)
            }

            onProgress(
                PullProgress(
                    status: chunk.status?.nonEmptyTrimmed ?? "Downloading…",
                    completed: chunk.completed,
                    total: chunk.total
                )
            )
        }
    }

    // MARK: - Reachability

    /// Resolves a base URL that is reachable, or throws if none are reachable.
    private func resolveReachableBaseURL() async throws -> URL {
        if let cached = cachedReachableBaseURL, await canReach(baseURL: cached) {
            return cached
        }

        for base in candidateBaseURLs {
            if await canReach(baseURL: base) {
                cachedReachableBaseURL = base
                return base
            }
        }

        throw URLError(.cannotConnectToHost)
    }

    /// Prefer /api/version for reachability (small payload, fast).
    private func canReach(baseURL: URL) async -> Bool {
        do {
            _ = try await fetchVersion(baseURL: baseURL)
            return true
        } catch {
            log.debug("Reachability failed for \(baseURL.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: - API calls

    private func fetchVersion(baseURL: URL) async throws -> VersionResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/version"))
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(VersionResponse.self, from: data)
    }

    private func fetchTags(baseURL: URL) async throws -> TagsResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(TagsResponse.self, from: data)
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

    // MARK: - Installation detection

    /// Detect installation without shelling out (App Store-safe).
    /// Supports both App installs and Homebrew/CLI installs.
    static func detectInstalled() -> Bool {
        let fm = FileManager.default

        // Ollama.app (common locations)
        let appPaths = [
            "/Applications/Ollama.app",
            "~/Applications/Ollama.app"
        ].map { ($0 as NSString).expandingTildeInPath }

        if appPaths.contains(where: { fm.fileExists(atPath: $0) }) {
            return true
        }

        // Homebrew / CLI binary locations
        let cliPaths = [
            "/opt/homebrew/bin/ollama", // Apple Silicon Homebrew
            "/usr/local/bin/ollama",    // Intel Homebrew
            "/usr/bin/ollama"           // Uncommon, but harmless to check
        ]

        if cliPaths.contains(where: { fm.fileExists(atPath: $0) }) {
            return true
        }

        return false
    }
}

nonisolated private struct VersionResponse: Decodable {
    let version: String
}

nonisolated private struct TagsResponse: Decodable {
    let models: [TagsModel]
}

nonisolated private struct TagsModel: Decodable {
    let name: String
    let size: Int64?
}

nonisolated private struct DeleteModelRequest: Encodable {
    let model: String
}

nonisolated private struct PullModelRequest: Encodable {
    let model: String
}

nonisolated private struct PullModelChunk: Decodable {
    let status: String?
    let completed: Int64?
    let total: Int64?
    let error: String?
}

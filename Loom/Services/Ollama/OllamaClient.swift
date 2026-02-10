import Foundation
import OSLog

nonisolated struct OllamaModel: Identifiable, Hashable, Sendable {
    let tag: String

    var id: String { tag }
}

actor OllamaClient {
    private let log = Logger(subsystem: "com.loom.app", category: "OllamaClient")
    private let baseURL = URL(string: "http://127.0.0.1:11434")!
    private let timeout: TimeInterval = 1.5

    func ping() async -> Bool {
        do {
            _ = try await fetchTags()
            return true
        } catch {
            log.debug("Ping failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func listModels() async throws -> [OllamaModel] {
        let response = try await fetchTags()
        let models = response.models.map { OllamaModel(tag: $0.name) }
        return models.sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    private func fetchTags() async throws -> TagsResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(TagsResponse.self, from: data)
    }
}

nonisolated private struct TagsResponse: Decodable {
    let models: [TagsModel]
}

nonisolated private struct TagsModel: Decodable {
    let name: String
}

import Foundation
import OSLog

/// Capabilities represent Loom tool compatibility for a model in this catalog.
/// They are app-level compatibility flags, not native multimodal guarantees from model vendors.
nonisolated struct CatalogModelCapabilities: Codable, Equatable, Sendable {
    let speechInput: Bool
    let speechOutput: Bool
    let fileUploads: Bool

    static let `default` = CatalogModelCapabilities(
        speechInput: true,
        speechOutput: true,
        fileUploads: true
    )
}

nonisolated struct CatalogModel: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let tag: String
    let displayName: String
    let vendor: String
    let country: String?
    let lastTrained: String?
    let summary: String
    let bestAt: [String]
    let approxDownloadBytes: Int64?
    let approxDiskBytes: Int64?
    let notes: String?
    let recommended: Bool
    let capabilities: CatalogModelCapabilities?

    var resolvedCapabilities: CatalogModelCapabilities {
        capabilities ?? .default
    }
}

nonisolated struct ModelCatalog: Equatable, Sendable {
    let all: [CatalogModel]
    let lastRefreshedAt: String?

    init(all: [CatalogModel], lastRefreshedAt: String? = nil) {
        self.all = all
        self.lastRefreshedAt = lastRefreshedAt
    }

    var recommended: [CatalogModel] {
        all.filter(\.recommended)
    }

    func byTag(_ tag: String) -> CatalogModel? {
        all.first(where: { $0.tag == tag })
    }

    static func fallbackForTesting() -> ModelCatalog {
        ModelCatalog(all: fallbackModels, lastRefreshedAt: fallbackLastRefreshedAt)
    }

    static func load(from preferredBundle: Bundle = .main) -> ModelCatalog {
        for bundle in candidateBundles(preferredBundle: preferredBundle) {
            guard let url = bundle.url(forResource: "ModelCatalog", withExtension: "json") else { continue }
            do {
                let data = try Data(contentsOf: url)
                if let payload = try? JSONDecoder().decode(CatalogPayload.self, from: data),
                   !payload.models.isEmpty {
                    return ModelCatalog(
                        all: payload.models,
                        lastRefreshedAt: normalizedRefreshDate(payload.lastRefreshedAt)
                    )
                }

                let models = try JSONDecoder().decode([CatalogModel].self, from: data)
                if !models.isEmpty {
                    return ModelCatalog(all: models, lastRefreshedAt: nil)
                }
            } catch {
                log.error("Failed to load ModelCatalog.json from \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        return ModelCatalog(all: fallbackModels, lastRefreshedAt: fallbackLastRefreshedAt)
    }

    private static let log = Logger(subsystem: "com.loom.app", category: "ModelCatalog")

    private static func candidateBundles(preferredBundle: Bundle) -> [Bundle] {
        [preferredBundle, Bundle.main, Bundle(for: BundleToken.self)]
    }

    private static func normalizedRefreshDate(_ raw: String?) -> String? {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? raw?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
    }

    private static let fallbackLastRefreshedAt = "2026-05-26"

    private struct CatalogPayload: Codable {
        let lastRefreshedAt: String?
        let models: [CatalogModel]
    }

    private static let fallbackModels: [CatalogModel] = [
        CatalogModel(
            id: "qwen3.5:9b",
            tag: "qwen3.5:9b",
            displayName: "Qwen 3.5 (9B)",
            vendor: "Qwen",
            country: "China",
            lastTrained: nil,
            summary: "Modern balanced default for general chat, coding, and long-context local work.",
            bestAt: ["Coding help", "Reasoning", "General chat"],
            approxDownloadBytes: 6_600_000_000,
            approxDiskBytes: nil,
            notes: "Best starting point for modern Macs with enough memory for a 9B model.",
            recommended: true,
            capabilities: CatalogModelCapabilities(
                speechInput: true,
                speechOutput: true,
                fileUploads: true
            )
        ),
        CatalogModel(
            id: "deepseek-r1:8b",
            tag: "deepseek-r1:8b",
            displayName: "DeepSeek R1 (8B)",
            vendor: "DeepSeek",
            country: "China",
            lastTrained: "2025",
            summary: "Reasoning-first model with strong logic and technical performance at 8B size.",
            bestAt: ["Reasoning", "Math and logic", "Technical Q&A"],
            approxDownloadBytes: 5_200_000_000,
            approxDiskBytes: 5_800_000_000,
            notes: "Use when you want deeper step-by-step answers.",
            recommended: true,
            capabilities: CatalogModelCapabilities(
                speechInput: true,
                speechOutput: true,
                fileUploads: true
            )
        ),
        CatalogModel(
            id: "gemma3:4b",
            tag: "gemma3:4b",
            displayName: "Gemma 3 (4B)",
            vendor: "Google",
            country: "United States",
            lastTrained: "2025",
            summary: "Small modern model for fast local work with strong quality for its size.",
            bestAt: ["Fast drafts", "Summaries", "Low-memory Macs"],
            approxDownloadBytes: 3_300_000_000,
            approxDiskBytes: 3_800_000_000,
            notes: "Best lightweight pick in the refreshed catalog.",
            recommended: true,
            capabilities: CatalogModelCapabilities(
                speechInput: true,
                speechOutput: true,
                fileUploads: true
            )
        ),
        CatalogModel(
            id: "gemma4:e4b",
            tag: "gemma4:e4b",
            displayName: "Gemma 4 (E4B)",
            vendor: "Google",
            country: "United States",
            lastTrained: nil,
            summary: "Current Gemma option with improved reasoning and agentic capabilities.",
            bestAt: ["Reasoning", "Summaries", "General chat"],
            approxDownloadBytes: 9_600_000_000,
            approxDiskBytes: nil,
            notes: "Modern higher-quality option for Macs with more available memory.",
            recommended: true,
            capabilities: CatalogModelCapabilities(
                speechInput: true,
                speechOutput: true,
                fileUploads: true
            )
        )
    ]
}

private final class BundleToken {}

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

    private static let fallbackLastRefreshedAt = "2026-03-18"

    private struct CatalogPayload: Codable {
        let lastRefreshedAt: String?
        let models: [CatalogModel]
    }

    private static let fallbackModels: [CatalogModel] = [
        CatalogModel(
            id: "qwen3:8b",
            tag: "qwen3:8b",
            displayName: "Qwen 3 (8B)",
            vendor: "Qwen",
            country: "China",
            lastTrained: "2025",
            summary: "Current balanced default for coding, analysis, and general chat.",
            bestAt: ["Coding help", "Reasoning", "General chat"],
            approxDownloadBytes: 5_200_000_000,
            approxDiskBytes: 5_800_000_000,
            notes: "Best starting point for most Macs.",
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
            id: "gemma3:12b",
            tag: "gemma3:12b",
            displayName: "Gemma 3 (12B)",
            vendor: "Google",
            country: "United States",
            lastTrained: "2025",
            summary: "Higher-quality Gemma 3 option for users with more RAM.",
            bestAt: ["Long-form answers", "Summaries", "General chat"],
            approxDownloadBytes: 8_100_000_000,
            approxDiskBytes: 9_000_000_000,
            notes: "Great quality jump from 4B if your Mac can handle it.",
            recommended: true,
            capabilities: CatalogModelCapabilities(
                speechInput: true,
                speechOutput: true,
                fileUploads: true
            )
        ),
        CatalogModel(
            id: "mistral-small:24b",
            tag: "mistral-small:24b",
            displayName: "Mistral Small (24B)",
            vendor: "Mistral AI",
            country: "France",
            lastTrained: "2025",
            summary: "High-capability local model for users prioritizing quality over speed.",
            bestAt: ["Complex prompts", "Reasoning", "Agent-style tasks"],
            approxDownloadBytes: 14_000_000_000,
            approxDiskBytes: 15_500_000_000,
            notes: "Recommended for 32GB+ memory setups.",
            recommended: false,
            capabilities: CatalogModelCapabilities(
                speechInput: true,
                speechOutput: true,
                fileUploads: true
            )
        )
    ]
}

private final class BundleToken {}

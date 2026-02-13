import Foundation
import OSLog

nonisolated struct CatalogModel: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let tag: String
    let displayName: String
    let vendor: String
    let country: String?
    let summary: String
    let bestAt: [String]
    let approxDownloadBytes: Int64?
    let approxDiskBytes: Int64?
    let notes: String?
    let recommended: Bool
}

nonisolated struct ModelCatalog: Equatable, Sendable {
    let all: [CatalogModel]

    var recommended: [CatalogModel] {
        all.filter(\.recommended)
    }

    func byTag(_ tag: String) -> CatalogModel? {
        all.first(where: { $0.tag == tag })
    }

    static func load(from preferredBundle: Bundle = .main) -> ModelCatalog {
        for bundle in candidateBundles(preferredBundle: preferredBundle) {
            guard let url = bundle.url(forResource: "ModelCatalog", withExtension: "json") else { continue }
            do {
                let data = try Data(contentsOf: url)
                let models = try JSONDecoder().decode([CatalogModel].self, from: data)
                if !models.isEmpty {
                    return ModelCatalog(all: models)
                }
            } catch {
                log.error("Failed to load ModelCatalog.json from \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        return ModelCatalog(all: fallbackModels)
    }

    private static let log = Logger(subsystem: "com.loom.app", category: "ModelCatalog")

    private static func candidateBundles(preferredBundle: Bundle) -> [Bundle] {
        [preferredBundle, Bundle.main, Bundle(for: BundleToken.self)]
    }

    private static let fallbackModels: [CatalogModel] = [
        CatalogModel(
            id: "llama3.1:8b",
            tag: "llama3.1:8b",
            displayName: "Llama 3.1 (8B)",
            vendor: "Meta",
            country: "United States",
            summary: "Balanced all-around model for chat, drafting, and summaries.",
            bestAt: ["General chat", "Summaries", "Writing help"],
            approxDownloadBytes: 4_700_000_000,
            approxDiskBytes: 5_200_000_000,
            notes: "Great default for most Macs.",
            recommended: true
        ),
        CatalogModel(
            id: "qwen2.5:7b",
            tag: "qwen2.5:7b",
            displayName: "Qwen 2.5 (7B)",
            vendor: "Qwen",
            country: "China",
            summary: "Fast and strong at structured responses and coding support.",
            bestAt: ["Coding help", "Structured output", "Reasoning"],
            approxDownloadBytes: 4_400_000_000,
            approxDiskBytes: 4_900_000_000,
            notes: "Good balance of speed and quality.",
            recommended: true
        ),
        CatalogModel(
            id: "phi4:latest",
            tag: "phi4:latest",
            displayName: "Phi 4",
            vendor: "Microsoft",
            country: "United States",
            summary: "Compact reasoning-focused model with strong instruction following.",
            bestAt: ["Reasoning", "Task planning", "Short analyses"],
            approxDownloadBytes: 8_000_000_000,
            approxDiskBytes: 9_000_000_000,
            notes: "Needs more RAM than small 7-8B models.",
            recommended: false
        ),
        CatalogModel(
            id: "mistral:7b",
            tag: "mistral:7b",
            displayName: "Mistral (7B)",
            vendor: "Mistral AI",
            country: "France",
            summary: "Reliable lightweight model for everyday prompts and edits.",
            bestAt: ["Quick answers", "Rewrite tasks", "General chat"],
            approxDownloadBytes: 4_100_000_000,
            approxDiskBytes: 4_600_000_000,
            notes: "Fast on older hardware.",
            recommended: false
        ),
        CatalogModel(
            id: "gemma2:9b",
            tag: "gemma2:9b",
            displayName: "Gemma 2 (9B)",
            vendor: "Google",
            country: "United States",
            summary: "Helpful for concise answers, summaries, and research notes.",
            bestAt: ["Summaries", "Research notes", "General chat"],
            approxDownloadBytes: 5_600_000_000,
            approxDiskBytes: 6_200_000_000,
            notes: "Solid quality with moderate resource use.",
            recommended: false
        ),
        CatalogModel(
            id: "llama3.2:3b",
            tag: "llama3.2:3b",
            displayName: "Llama 3.2 (3B)",
            vendor: "Meta",
            country: "United States",
            summary: "Small model for lightweight local tasks and quick drafts.",
            bestAt: ["Fast drafts", "Simple Q&A", "Low-memory Macs"],
            approxDownloadBytes: 2_000_000_000,
            approxDiskBytes: 2_300_000_000,
            notes: "Best speed/resource option in this catalog.",
            recommended: true
        )
    ]
}

private final class BundleToken {}

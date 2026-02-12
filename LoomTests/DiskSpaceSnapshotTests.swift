import Foundation
import Testing
@testable import Loom

struct DiskSpaceSnapshotTests {
    @Test
    func preferredProbeURLsPrioritizeConfiguredOllamaPath() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let urls = DiskSpaceSnapshot.preferredProbeURLs(
            environment: ["OLLAMA_MODELS": "/Volumes/External/OllamaModels"],
            homeDirectory: home
        )

        #expect(urls.first?.path == "/Volumes/External/OllamaModels")
        #expect(urls.contains(where: { $0.path == "/Users/tester/.ollama/models" }))
        #expect(urls.contains(where: { $0.path == "/Users/tester" }))
        #expect(urls.last?.path == "/")
    }

    @Test
    func preferredProbeURLsTrimAndDeduplicatePaths() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let urls = DiskSpaceSnapshot.preferredProbeURLs(
            environment: ["OLLAMA_MODELS": "  /Users/tester/.ollama/models  "],
            homeDirectory: home
        )

        let matchingCount = urls.filter { $0.path == "/Users/tester/.ollama/models" }.count
        #expect(matchingCount == 1)
    }
}

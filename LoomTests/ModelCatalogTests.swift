import Testing
@testable import Loom

struct ModelCatalogTests {
    @Test
    func loadReturnsCatalogModels() {
        let catalog = ModelCatalog.load()

        #expect(!catalog.all.isEmpty)
        #expect(catalog.all.count == 5)
        #expect(catalog.all.contains(where: { $0.tag == "qwen3:8b" }))
    }

    @Test
    func recommendedReturnsCuratedSubset() {
        let catalog = ModelCatalog.load()

        #expect(!catalog.recommended.isEmpty)
        #expect(catalog.recommended.filter { !$0.recommended }.isEmpty)
        #expect(catalog.recommended.contains(where: { $0.tag == "qwen3:8b" }))
        #expect(catalog.recommended.contains(where: { $0.tag == "deepseek-r1:8b" }))
        #expect(catalog.recommended.contains(where: { $0.tag == "gemma3:4b" }))
        #expect(catalog.recommended.contains(where: { $0.tag == "gemma3:12b" }))
        #expect(!catalog.recommended.contains(where: { $0.tag == "mistral-small:24b" }))
    }

    @Test
    func byTagReturnsMatchingModel() {
        let catalog = ModelCatalog.load()

        let model = catalog.byTag("qwen3:8b")
        #expect(model?.displayName == "Qwen 3 (8B)")
        #expect(model?.vendor == "Qwen")
        #expect(model?.country == "China")
        #expect(model?.lastTrained == "2025")
    }

    @Test
    func modelCapabilitiesLoadFromCatalog() {
        let catalog = ModelCatalog.load()

        let fullMultimodal = catalog.byTag("qwen3:8b")?.resolvedCapabilities
        #expect(fullMultimodal?.speechInput == true)
        #expect(fullMultimodal?.speechOutput == true)
        #expect(fullMultimodal?.fileUploads == true)

        let highEnd = catalog.byTag("mistral-small:24b")?.resolvedCapabilities
        #expect(highEnd?.speechInput == true)
        #expect(highEnd?.speechOutput == true)
        #expect(highEnd?.fileUploads == true)
    }

    @Test
    func bundledCatalogAndFallbackStayInSyncByTag() {
        let bundledTags = Set(ModelCatalog.load().all.map(\.tag))
        let fallbackTags = Set(ModelCatalog.fallbackForTesting().all.map(\.tag))
        #expect(bundledTags == fallbackTags)
    }
}

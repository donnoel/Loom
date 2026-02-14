import Testing
@testable import Loom

struct ModelCatalogTests {
    @Test
    func loadReturnsCatalogModels() {
        let catalog = ModelCatalog.load()

        #expect(!catalog.all.isEmpty)
        #expect(catalog.all.contains(where: { $0.tag == "llama3.1:8b" }))
    }

    @Test
    func recommendedReturnsCuratedSubset() {
        let catalog = ModelCatalog.load()

        #expect(!catalog.recommended.isEmpty)
        #expect(catalog.recommended.filter { !$0.recommended }.isEmpty)
    }

    @Test
    func byTagReturnsMatchingModel() {
        let catalog = ModelCatalog.load()

        let model = catalog.byTag("qwen2.5:7b")
        #expect(model?.displayName == "Qwen 2.5 (7B)")
        #expect(model?.vendor == "Qwen")
        #expect(model?.country == "China")
        #expect(model?.lastTrained == "September 2024")
    }

    @Test
    func modelCapabilitiesLoadFromCatalog() {
        let catalog = ModelCatalog.load()

        let fullMultimodal = catalog.byTag("qwen2.5:7b")?.resolvedCapabilities
        #expect(fullMultimodal?.speechInput == true)
        #expect(fullMultimodal?.speechOutput == true)
        #expect(fullMultimodal?.fileUploads == true)

        let limited = catalog.byTag("llama3.2:3b")?.resolvedCapabilities
        #expect(limited?.speechInput == true)
        #expect(limited?.speechOutput == false)
        #expect(limited?.fileUploads == false)
    }
}

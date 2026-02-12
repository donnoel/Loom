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
    }
}

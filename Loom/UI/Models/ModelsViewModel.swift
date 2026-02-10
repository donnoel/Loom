import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ModelsViewModel {
    private let log = Logger(subsystem: "com.loom.app", category: "ModelsViewModel")
    private let client: OllamaClient

    var models: [OllamaModel] = []
    var ollamaReachable: Bool = false
    var isLoading: Bool = false

    init(client: OllamaClient = OllamaClient()) {
        self.client = client
    }

    var activeModelTag: String? {
        get {
            UserDefaults.standard.string(forKey: LoomPreferenceKeys.activeModelTag)?.nonEmptyTrimmed
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: LoomPreferenceKeys.activeModelTag)
            } else {
                UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.activeModelTag)
            }
        }
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        ollamaReachable = await client.ping()
        guard ollamaReachable else {
            models = []
            return
        }

        do {
            models = try await client.listModels()
            if let activeModelTag, !models.contains(where: { $0.tag == activeModelTag }) {
                self.activeModelTag = nil
            }
        } catch {
            log.error("Failed to refresh models: \(String(describing: error), privacy: .public)")
            models = []
        }
    }

    func selectModel(_ model: OllamaModel) {
        activeModelTag = model.tag
    }
}

import AppKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ModelsViewModel {
    enum OpenOllamaResult {
        case opened
        case showServeHelp
    }

    private let log = Logger(subsystem: "com.loom.app", category: "ModelsViewModel")
    private let client: OllamaClient
    private var activationObserver: NSObjectProtocol?

    var diagnosis: OllamaDiagnosis = .unavailable
    var models: [OllamaModel] = []
    var isRefreshing: Bool = false
    var lastRefreshAt: Date?

    init(client: OllamaClient = OllamaClient()) {
        self.client = client
    }

    var activeModelTag: String? {
        get {
            UserDefaults.standard.string(forKey: LoomPreferenceKeys.activeModelTag)?.nonEmptyTrimmed
        }
        set {
            if let value = newValue?.nonEmptyTrimmed {
                UserDefaults.standard.set(value, forKey: LoomPreferenceKeys.activeModelTag)
            } else {
                UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.activeModelTag)
            }
        }
    }

    var isRunning: Bool { diagnosis.isRunning }
    var isInstalled: Bool { diagnosis.isInstalled }
    var installedModelCount: Int { models.count }

    func startMonitoring() {
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
    }

    func stopMonitoring() {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshAt = Date()
        }

        diagnosis = await client.diagnose()

        guard diagnosis.isRunning else {
            models = []
            return
        }

        do {
            models = try await client.listModels()
        } catch {
            log.error("Failed to load models: \(String(describing: error), privacy: .public)")
            models = []
        }

        if let selected = activeModelTag, !models.contains(where: { $0.tag == selected }) {
            activeModelTag = nil
        }
    }

    func setActiveModel(tag: String) {
        activeModelTag = tag
    }

    func openOrInstallOllama() -> OpenOllamaResult {
        if let appURL = Self.ollamaAppURL() {
            NSWorkspace.shared.open(appURL)
            return .opened
        }

        if diagnosis.isInstalled {
            return .showServeHelp
        }

        NSWorkspace.shared.open(Self.downloadURL)
        return .opened
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(Self.downloadURL)
    }

    private static let downloadURL = URL(string: "https://ollama.com/download")!

    private static func ollamaAppURL() -> URL? {
        let bundleIdentifiers = [
            "ai.ollama.Ollama",
            "com.ollama.app"
        ]

        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }

        let paths = [
            "/Applications/Ollama.app",
            NSString(string: "~/Applications/Ollama.app").expandingTildeInPath
        ]

        for path in paths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }
}

nonisolated extension OllamaDiagnosis {
    static let unavailable = OllamaDiagnosis(
        isInstalled: false,
        isRunning: false,
        reachableBaseURL: nil,
        summary: "Checking status",
        nextStep: .tryAgain
    )
}

import AppKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class StatusViewModel {
    private let log = Logger(subsystem: "com.loom.app", category: "StatusViewModel")
    private let client: any OllamaStatusProviding
    private var refreshTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    private nonisolated static func isAutoRefreshEnabled() -> Bool {
        if let stored = UserDefaults.standard.object(forKey: LoomPreferenceKeys.statusAutoRefreshEnabled) as? Bool {
            return stored
        }
        return true
    }

    var snapshot: LoomStatusSnapshot = .unavailable
    var isRefreshing: Bool = false
    var lastRefreshAt: Date?
    var ollamaAppInstalled: Bool = false

    init(client: any OllamaStatusProviding = OllamaClient()) {
        self.client = client
    }

    func startMonitoring() {
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                guard Self.isAutoRefreshEnabled() else { return }
                Task { await self.refresh() }
            }
        }

        if refreshTask == nil {
            refreshTask = Task { [weak self] in
                guard let self else { return }

                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    guard Self.isAutoRefreshEnabled() else { continue }
                    await self.refresh()
                }
            }
        }

        Task { await refresh() }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil

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

        let diagnosis = await client.diagnose()
        ollamaAppInstalled = diagnosis.isInstalled
        let isReachable = diagnosis.isRunning

        var models: [OllamaModel] = []
        if isReachable {
            do {
                models = try await client.listModels()
            } catch {
                log.error("Failed to list models: \(String(describing: error), privacy: .public)")
            }
        }

        var activeModelTag = UserDefaults.standard.string(forKey: LoomPreferenceKeys.activeModelTag)?.nonEmptyTrimmed
        if let selectedTag = activeModelTag, !models.contains(where: { $0.tag == selectedTag }) {
            activeModelTag = nil
            UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.activeModelTag)
        }

        snapshot = LoomStatusSnapshot(
            ollamaReachable: isReachable,
            installedModelCount: models.count,
            activeModelTag: activeModelTag,
            offlineAvailable: isReachable && !models.isEmpty && activeModelTag != nil
        )
    }

    var ollamaActionTitle: String {
        if snapshot.ollamaReachable {
            return "Ollama is running"
        }
        return ollamaAppInstalled ? "Start Ollama" : "Install Ollama…"
    }

    func openOrInstallOllama() {
        if let appURL = Self.ollamaAppURL() {
            NSWorkspace.shared.open(appURL)
        } else {
            NSWorkspace.shared.open(Self.ollamaDownloadURL)
        }
    }

    private static let ollamaDownloadURL = URL(string: "https://ollama.com/download")!

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

        let fallbackPaths = [
            "/Applications/Ollama.app",
            NSString(string: "~/Applications/Ollama.app").expandingTildeInPath
        ]

        for path in fallbackPaths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }
}

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
    private let client: any OllamaStatusProviding
    private var activationObserver: NSObjectProtocol?
    private let activeModelDeleteBlockedMessage = "This model is currently active. Choose another model before deleting."

    private nonisolated static func isAutoCheckEnabled() -> Bool {
        if let stored = UserDefaults.standard.object(forKey: LoomPreferenceKeys.modelsAutoCheckEnabled) as? Bool {
            return stored
        }
        return true
    }

    var diagnosis: OllamaDiagnosis = .unavailable
    var models: [OllamaModel] = []
    var diskSpaceSnapshot: DiskSpaceSnapshot?
    var isRefreshing: Bool = false
    var lastRefreshAt: Date?
    var selectedModelToDelete: String?
    var deleteAlertMessage: String?
    var isDeletingModel: Bool = false

    init(client: any OllamaStatusProviding = OllamaClient()) {
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
    var lowDiskSpaceWarningText: String? {
        guard let diskSpaceSnapshot, diskSpaceSnapshot.isLowSpace else { return nil }
        return DiskSpaceSnapshot.lowSpaceWarningMessage
    }

    var diskFreeSpaceText: String {
        guard let diskSpaceSnapshot else {
            return "Free space: unavailable"
        }

        return "Free space: \(DiskSpaceSnapshot.formattedBytes(diskSpaceSnapshot.availableBytes)) of \(DiskSpaceSnapshot.formattedBytes(diskSpaceSnapshot.totalBytes)) (\(diskSpaceSnapshot.availablePercentDisplay))"
    }

    func startMonitoring() {
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                guard Self.isAutoCheckEnabled() else { return }
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

        diskSpaceSnapshot = DiskSpaceSnapshot.current()
        diagnosis = await client.diagnose()

        guard diagnosis.isRunning else {
            models = []
            return
        }

        do {
            let listedModels = try await client.listModels()
            models = listedModels
        } catch {
            log.error("Failed to load models: \(String(describing: error), privacy: .public)")
            models = []
        }
    }

    func setActiveModel(tag: String) {
        activeModelTag = tag
    }

    func requestDelete(modelTag: String) {
        guard let tag = modelTag.nonEmptyTrimmed else { return }

        guard activeModelTag != tag else {
            selectedModelToDelete = nil
            deleteAlertMessage = activeModelDeleteBlockedMessage
            return
        }

        selectedModelToDelete = tag
    }

    func cancelDeleteRequest() {
        selectedModelToDelete = nil
    }

    func dismissDeleteAlert() {
        deleteAlertMessage = nil
    }

    func confirmDelete() async -> Bool {
        guard !isDeletingModel else { return false }
        guard let modelTag = selectedModelToDelete?.nonEmptyTrimmed else { return false }

        guard activeModelTag != modelTag else {
            selectedModelToDelete = nil
            deleteAlertMessage = activeModelDeleteBlockedMessage
            return false
        }

        isDeletingModel = true
        selectedModelToDelete = nil
        defer { isDeletingModel = false }

        do {
            try await client.deleteModel(name: modelTag)
            await refresh()
            return true
        } catch {
            log.error("Failed to delete model \(modelTag, privacy: .public): \(String(describing: error), privacy: .public)")
            deleteAlertMessage = deleteFailureMessage(for: error, modelTag: modelTag)
            return false
        }
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

    private func deleteFailureMessage(for error: Error, modelTag: String) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return "Loom can’t reach Ollama. Start it to continue."
            default:
                break
            }
        }

        return "Loom couldn’t delete '\(modelTag)'. Try again."
    }

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

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
    private let catalog: ModelCatalog
    private var activationObserver: NSObjectProtocol?
    private let activeModelDeleteBlockedMessage = "This model is currently active. Choose another model before deleting."
    private let progressUpdateInterval: Duration = .milliseconds(100)
    private var installTask: Task<Void, Never>?
    private var progressFlushTask: Task<Void, Never>?
    private var pendingPullProgress: PullProgress?

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
    var pendingLowSpaceInstallTag: String?
    var installingTag: String?
    var pullProgressByTag: [String: PullProgress] = [:]
    var installErrorMessage: String?

    init(
        client: any OllamaStatusProviding = OllamaClient(),
        catalog: ModelCatalog = .load()
    ) {
        self.client = client
        self.catalog = catalog
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
    var catalogModels: [CatalogModel] { catalog.all }
    var recommendedCatalogModels: [CatalogModel] { catalog.recommended }
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

        diskSpaceSnapshot = DiskSpaceSnapshot.currentForOllamaModels()
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

    func isModelInstalled(tag: String) -> Bool {
        models.contains(where: { $0.tag == tag })
    }

    func canInstallModel(tag: String) -> Bool {
        !isModelInstalled(tag: tag) && (installingTag == nil || installingTag == tag)
    }

    func installedSizeText(tag: String) -> String? {
        guard let model = models.first(where: { $0.tag == tag }),
              let size = model.sizeBytes else {
            return nil
        }
        return DiskSpaceSnapshot.formattedBytes(size)
    }

    func catalogSizeText(model: CatalogModel) -> String? {
        var segments: [String] = []

        if let downloadBytes = model.approxDownloadBytes {
            segments.append("Download \(DiskSpaceSnapshot.formattedBytes(downloadBytes))")
        }

        if let diskBytes = model.approxDiskBytes {
            segments.append("Uses \(DiskSpaceSnapshot.formattedBytes(diskBytes)) on disk")
        }

        return segments.isEmpty ? nil : segments.joined(separator: " • ")
    }

    func pullProgress(for tag: String) -> PullProgress? {
        pullProgressByTag[tag]
    }

    func beginInstall(tag: String) {
        guard let installTag = tag.nonEmptyTrimmed else { return }
        guard !isModelInstalled(tag: installTag) else { return }
        guard installingTag == nil else { return }

        if diskSpaceSnapshot?.isLowSpace == true {
            pendingLowSpaceInstallTag = installTag
            return
        }

        startInstall(tag: installTag)
    }

    func continueInstallAfterLowSpaceConfirmation() {
        guard let installTag = pendingLowSpaceInstallTag else { return }
        startInstall(tag: installTag)
    }

    func cancelLowSpaceInstallRequest() {
        pendingLowSpaceInstallTag = nil
    }

    func dismissInstallError() {
        installErrorMessage = nil
    }

    func cancelInstall() {
        installTask?.cancel()
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
        if let deleteError = error as? DeleteModelError,
           let description = deleteError.errorDescription?.nonEmptyTrimmed {
            return description
        }

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

    private func startInstall(tag: String) {
        guard installingTag == nil else { return }
        pendingLowSpaceInstallTag = nil
        installErrorMessage = nil
        installingTag = tag
        pendingPullProgress = nil
        pullProgressByTag[tag] = PullProgress(status: "Preparing download…", completed: nil, total: nil)

        progressFlushTask?.cancel()
        progressFlushTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.progressUpdateInterval)
                self.flushPendingPullProgress(for: tag)
            }
        }

        installTask?.cancel()
        installTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await self.client.pullModel(name: tag) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.installingTag == tag else { return }
                        self.pendingPullProgress = progress
                    }
                }

                self.flushPendingPullProgress(for: tag)
                await self.refresh()
            } catch is CancellationError {
                // User cancelled intentionally.
            } catch {
                self.log.error("Failed to install model \(tag, privacy: .public): \(String(describing: error), privacy: .public)")
                self.installErrorMessage = self.installFailureMessage(for: error, modelTag: tag)
            }

            self.finishInstall(tag: tag)
        }
    }

    private func flushPendingPullProgress(for tag: String) {
        guard installingTag == tag,
              let pendingPullProgress else { return }
        pullProgressByTag[tag] = pendingPullProgress
        self.pendingPullProgress = nil
    }

    private func finishInstall(tag: String) {
        progressFlushTask?.cancel()
        progressFlushTask = nil
        installTask = nil
        pendingPullProgress = nil
        pullProgressByTag[tag] = nil
        if installingTag == tag {
            installingTag = nil
        }
    }

    private func installFailureMessage(for error: Error, modelTag: String) -> String {
        if let pullError = error as? PullModelError,
           let description = pullError.errorDescription?.nonEmptyTrimmed {
            return description
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return "Loom can’t reach Ollama. Start it to continue."
            default:
                break
            }
        }

        return "Loom couldn’t install '\(modelTag)'. Try again."
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

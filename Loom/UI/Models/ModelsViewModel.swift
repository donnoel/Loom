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
    private static let uiTestResetDefaultsEnvironmentKey = "LOOM_UI_TEST_RESET_DEFAULTS"

    private nonisolated static func isAutoCheckEnabled() -> Bool {
        if let stored = UserDefaults.standard.object(forKey: LoomPreferenceKeys.modelsAutoCheckEnabled) as? Bool {
            return stored
        }
        return true
    }

    private nonisolated static func defaultClient() -> any OllamaStatusProviding {
        if ProcessInfo.processInfo.environment[uiTestResetDefaultsEnvironmentKey] == "1" {
            return UITestModelsStatusClient()
        }
        return OllamaClient()
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
    var updateErrorMessage: String?
    var updatingTag: String?
    var isCheckingUpdates: Bool = false
    var lastUpdateCheckAt: Date?
    var checkedForUpdatesAtByTag: [String: Date] = [:]

    init(
        client: (any OllamaStatusProviding)? = nil,
        catalog: ModelCatalog = .load()
    ) {
        self.client = client ?? Self.defaultClient()
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
    var statusSnapshot: LoomStatusSnapshot {
        LoomStatusSnapshot(
            ollamaReachable: isRunning,
            installedModelCount: models.count,
            activeModelTag: activeModelTag,
            offlineAvailable: isRunning && !models.isEmpty && activeModelTag != nil,
            diskSpace: diskSpaceSnapshot
        )
    }
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

    var totalInstalledSizeText: String {
        let totalBytes = models.reduce(into: Int64(0)) { partialResult, model in
            guard let size = model.sizeBytes, size > 0 else { return }
            let (nextValue, overflow) = partialResult.addingReportingOverflow(size)
            partialResult = overflow ? Int64.max : nextValue
        }
        return DiskSpaceSnapshot.formattedBytes(totalBytes)
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
            pruneUpdateCheckState()
            return
        }

        do {
            let listedModels = try await client.listModels()
            models = applyPreferredModelOrder(to: listedModels)
            persistModelOrder()
            pruneUpdateCheckState()
        } catch {
            log.error("Failed to load models: \(String(describing: error), privacy: .public)")
            models = []
            pruneUpdateCheckState()
        }
    }

    func moveInstalledModel(tag: String, before destinationTag: String) {
        guard let sourceIndex = models.firstIndex(where: { $0.tag == tag }),
              let destinationIndex = models.firstIndex(where: { $0.tag == destinationTag }),
              sourceIndex != destinationIndex else { return }

        var reordered = models
        let movedModel = reordered.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < destinationIndex ? (destinationIndex - 1) : destinationIndex
        reordered.insert(movedModel, at: insertionIndex)

        guard reordered != models else { return }
        models = reordered
        persistModelOrder()
    }

    func moveInstalledModelToEnd(tag: String) {
        guard let sourceIndex = models.firstIndex(where: { $0.tag == tag }),
              sourceIndex < models.count - 1 else { return }

        var reordered = models
        let movedModel = reordered.remove(at: sourceIndex)
        reordered.append(movedModel)

        guard reordered != models else { return }
        models = reordered
        persistModelOrder()
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

    func catalogModel(for tag: String) -> CatalogModel? {
        catalog.byTag(tag)
    }

    func capabilities(for tag: String) -> CatalogModelCapabilities {
        catalogModel(for: tag)?.resolvedCapabilities ?? .default
    }

    func installedModelCapabilitiesText(for model: OllamaModel) -> String {
        capabilitiesText(for: capabilities(for: model.tag))
    }

    func catalogModelCapabilitiesText(for model: CatalogModel) -> String {
        capabilitiesText(for: model.resolvedCapabilities)
    }

    func installedModelCompanyCountryText(for model: OllamaModel) -> String {
        guard let catalogModel = catalogModel(for: model.tag) else {
            return "Maker and country details aren’t listed for this model."
        }

        if let country = catalogModel.country?.nonEmptyTrimmed {
            return "Made by \(catalogModel.vendor) in \(country)."
        }

        return "Made by \(catalogModel.vendor)."
    }

    func installedModelBestForText(for model: OllamaModel) -> String {
        guard let catalogModel = catalogModel(for: model.tag) else {
            return "Good for everyday questions, writing help, and summaries."
        }

        let highlights = catalogModel.bestAt.prefix(2)
        if !highlights.isEmpty {
            return "Good for: \(highlights.joined(separator: ", "))."
        }

        return catalogModel.summary
    }

    func installedModelLastTrainedText(for model: OllamaModel) -> String {
        guard let catalogModel = catalogModel(for: model.tag),
              let lastTrained = catalogModel.lastTrained?.nonEmptyTrimmed else {
            return "Last trained date isn’t listed for this model."
        }

        return "Last trained: \(lastTrained)."
    }

    func parameterSizeText(for model: OllamaModel) -> String? {
        if let parameterSize = model.parameterSize?.nonEmptyTrimmed {
            return parameterSize
        }

        return Self.parameterSizeFromTag(model.tag)
    }

    func isModelCurrent(tag: String) -> Bool {
        checkedForUpdatesAtByTag[tag] != nil
    }

    func updateStatusText(for tag: String) -> String {
        if updatingTag == tag {
            return "Checking now…"
        }

        return isModelCurrent(tag: tag) ? "Current" : "Update"
    }

    func dismissUpdateError() {
        updateErrorMessage = nil
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

    func updateInstalledModel(tag: String) async -> Bool {
        guard let normalizedTag = tag.nonEmptyTrimmed else { return false }
        guard canUpdateModel(tag: normalizedTag) else { return false }

        updateErrorMessage = nil
        let didUpdate = await runModelUpdate(tag: normalizedTag)
        lastUpdateCheckAt = Date()

        if didUpdate {
            await refresh()
        }

        return didUpdate
    }

    func checkForUpdates() async {
        guard diagnosis.isRunning else { return }
        guard !isCheckingUpdates else { return }
        guard installingTag == nil else { return }

        isCheckingUpdates = true
        updateErrorMessage = nil

        defer {
            isCheckingUpdates = false
            lastUpdateCheckAt = Date()
        }

        let installedTags = models.map(\.tag)
        guard !installedTags.isEmpty else { return }

        var didUpdateAny = false
        for tag in installedTags {
            if await runModelUpdate(tag: tag) {
                didUpdateAny = true
            }
        }

        if didUpdateAny {
            await refresh()
        }
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
        await confirmDelete(modelTag: selectedModelToDelete ?? "")
    }

    func confirmDelete(modelTag: String) async -> Bool {
        guard !isDeletingModel else { return false }
        guard let normalizedTag = modelTag.nonEmptyTrimmed else { return false }

        guard activeModelTag != normalizedTag else {
            selectedModelToDelete = nil
            deleteAlertMessage = activeModelDeleteBlockedMessage
            return false
        }

        isDeletingModel = true
        selectedModelToDelete = nil
        defer { isDeletingModel = false }

        do {
            try await client.deleteModel(name: normalizedTag)
            await refresh()
            return true
        } catch {
            log.error("Failed to delete model \(normalizedTag, privacy: .public): \(String(describing: error), privacy: .public)")
            deleteAlertMessage = deleteFailureMessage(for: error, modelTag: normalizedTag)
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

    private func canUpdateModel(tag: String) -> Bool {
        guard diagnosis.isRunning else { return false }
        guard isModelInstalled(tag: tag) else { return false }
        guard !isCheckingUpdates else { return false }
        guard installingTag == nil else { return false }
        return updatingTag == nil || updatingTag == tag
    }

    private func runModelUpdate(tag: String) async -> Bool {
        updatingTag = tag
        defer {
            if updatingTag == tag {
                updatingTag = nil
            }
        }

        do {
            try await client.pullModel(name: tag) { _ in }
            checkedForUpdatesAtByTag[tag] = Date()
            return true
        } catch is CancellationError {
            return false
        } catch {
            log.error("Failed to update model \(tag, privacy: .public): \(String(describing: error), privacy: .public)")
            updateErrorMessage = updateFailureMessage(for: error, modelTag: tag)
            return false
        }
    }

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

    private func updateFailureMessage(for error: Error, modelTag: String) -> String {
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

        return "Loom couldn’t check updates for '\(modelTag)'. Try again."
    }

    private func pruneUpdateCheckState() {
        let installedTags = Set(models.map(\.tag))
        checkedForUpdatesAtByTag = checkedForUpdatesAtByTag.filter { installedTags.contains($0.key) }
        if let updatingTag, !installedTags.contains(updatingTag) {
            self.updatingTag = nil
        }
    }

    private func applyPreferredModelOrder(to listedModels: [OllamaModel]) -> [OllamaModel] {
        let preferredTags = storedModelOrder
        guard !preferredTags.isEmpty else { return listedModels }

        var preferredRank: [String: Int] = [:]
        for (index, tag) in preferredTags.enumerated() where preferredRank[tag] == nil {
            preferredRank[tag] = index
        }

        var fallbackOrder: [String: Int] = [:]
        for (index, model) in listedModels.enumerated() where fallbackOrder[model.tag] == nil {
            fallbackOrder[model.tag] = index
        }

        return listedModels.sorted { lhs, rhs in
            let lhsRank = preferredRank[lhs.tag]
            let rhsRank = preferredRank[rhs.tag]

            switch (lhsRank, rhsRank) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return (fallbackOrder[lhs.tag] ?? 0) < (fallbackOrder[rhs.tag] ?? 0)
            }
        }
    }

    private var storedModelOrder: [String] {
        guard let stored = UserDefaults.standard.array(forKey: LoomPreferenceKeys.modelLibraryOrder) as? [String] else {
            return []
        }
        return stored.compactMap(\.nonEmptyTrimmed)
    }

    private func persistModelOrder() {
        UserDefaults.standard.set(models.map(\.tag), forKey: LoomPreferenceKeys.modelLibraryOrder)
    }

    private static func parameterSizeFromTag(_ tag: String) -> String? {
        guard let tagSuffix = tag.split(separator: ":").last else { return nil }

        let trimmed = tagSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }

        let lastCharacter = trimmed.last?.lowercased()
        guard lastCharacter == "b" else { return nil }

        let value = String(trimmed.dropLast())
        guard !value.isEmpty else { return nil }
        guard value.allSatisfy({ $0.isNumber || $0 == "." }) else {
            return nil
        }

        return "\(value)B"
    }

    private func capabilitiesText(for capabilities: CatalogModelCapabilities) -> String {
        var supported: [String] = []
        var unavailable: [String] = []

        if capabilities.speechInput {
            supported.append("Speech Input")
        } else {
            unavailable.append("Speech Input")
        }

        if capabilities.speechOutput {
            supported.append("Speech Output")
        } else {
            unavailable.append("Speech Output")
        }

        if capabilities.fileUploads {
            supported.append("File Uploads")
        } else {
            unavailable.append("File Uploads")
        }

        var segments: [String] = []
        if !supported.isEmpty {
            segments.append("Supports: \(supported.joined(separator: ", "))")
        }
        if !unavailable.isEmpty {
            segments.append("Unavailable: \(unavailable.joined(separator: ", "))")
        }

        return segments.joined(separator: " • ")
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

private actor UITestModelsStatusClient: OllamaStatusProviding {
    func diagnose() async -> OllamaDiagnosis {
        OllamaDiagnosis(
            isInstalled: true,
            isRunning: true,
            reachableBaseURL: URL(string: "http://localhost:11434"),
            summary: "Ready",
            nextStep: .ready
        )
    }

    func listModels() async throws -> [OllamaModel] {
        [OllamaModel(tag: "ui-test-model")]
    }

    func deleteModel(name: String) async throws {}

    func pullModel(name: String, onProgress: @Sendable (PullProgress) -> Void) async throws {}
}


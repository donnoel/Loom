import Foundation
import Observation
import PDFKit

@MainActor
@Observable
final class SessionMessagesViewModel {
    struct PendingAttachment: Identifiable, Equatable, Sendable {
        let id: UUID
        let fileName: String
        let sourcePath: String
        let contentPreview: String
        let originalCharacterCount: Int

        var characterCountLabel: String {
            "\(originalCharacterCount) chars"
        }
    }

    struct BannerState: Equatable {
        enum Action: Equatable {
            case browseModels
            case openOrInstallOllama
            case retryLastReply
        }

        let text: String
        let actionTitle: String?
        let action: Action?
    }

    nonisolated enum HistoryContextLevel: String, CaseIterable, Identifiable, Sendable {
        case concise
        case balanced
        case extended

        var id: String { rawValue }

        var title: String {
            switch self {
            case .concise: "Concise"
            case .balanced: "Balanced"
            case .extended: "Extended"
            }
        }

        var messageLimit: Int {
            switch self {
            case .concise: 8
            case .balanced: 20
            case .extended: 40
            }
        }

        var baseTokenBudget: Int {
            switch self {
            case .concise: 2_000
            case .balanced: 4_000
            case .extended: 8_000
            }
        }
    }

    nonisolated enum FileContextLevel: String, CaseIterable, Identifiable, Sendable {
        case off
        case compact
        case full

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "Off"
            case .compact: "Compact"
            case .full: "Full"
            }
        }

        var attachmentCharacterBudget: Int {
            switch self {
            case .off: 0
            case .compact: 4_000
            case .full: 12_000
            }
        }

        var additionalTokenBudget: Int {
            switch self {
            case .off: 0
            case .compact: 1_000
            case .full: 2_000
            }
        }
    }

    struct ContextBudgetSnapshot: Equatable, Sendable {
        let estimatedTokens: Int
        let budgetTokens: Int

        var usageRatio: Double {
            guard budgetTokens > 0 else { return 1 }
            return min(1, Double(estimatedTokens) / Double(budgetTokens))
        }

        var label: String {
            "~\(estimatedTokens) / \(budgetTokens) tokens"
        }
    }

    private let store: SessionStore
    private let sessionID: UUID
    private let onActivity: (() async -> Void)?
    private let ollamaClient: any OllamaStatusProviding
    private let chatClient: any OllamaChatStreaming
    private let catalog: ModelCatalog
    private let attachmentImporter: SessionAttachmentImporter
    private let streamUpdateInterval: Duration = .milliseconds(60)
    private static let maxPendingAttachmentCount = 8
    private static let roughCharactersPerToken = 4
    private static let uiTestChatScenarioEnvironmentKey = "LOOM_UI_TEST_CHAT_STUB_SCENARIO"
    private static let uiTestActiveModelTagEnvironmentKey = "LOOM_UI_TEST_ACTIVE_MODEL_TAG"
    private static let uiTestChatScenarioDefaultsKey = "loom.uiTest.chatScenario"

    var messages: [ChatMessage] = []
    var draft: String = ""
    var isGenerating: Bool = false
    var generationTask: Task<Void, Never>?
    var generatingMessageID: UUID?
    var banner: BannerState?
    private(set) var isShowingFullHistory: Bool = false
    private(set) var pendingAttachments: [PendingAttachment] = []
    private(set) var availableModelTags: [String] = []
    var historyContextLevel: HistoryContextLevel {
        didSet {
            guard historyContextLevel != oldValue else { return }
            UserDefaults.standard.set(historyContextLevel.rawValue, forKey: LoomPreferenceKeys.composerHistoryContextLevel)
        }
    }
    var fileContextLevel: FileContextLevel {
        didSet {
            guard fileContextLevel != oldValue else { return }
            UserDefaults.standard.set(fileContextLevel.rawValue, forKey: LoomPreferenceKeys.composerFileContextLevel)
        }
    }
    private var isPreparingGeneration: Bool = false
    private var activeModelTagStorage: String?
    private var lastStreamModel: String?
    private var lastStreamContext: [ChatMessage]?
    private var lastStreamPlaceholderID: UUID?
    private var generatingMessageIndex: Int?
    private var persistedAssistantMessageIDs: Set<UUID> = []

    init(
        store: SessionStore,
        sessionID: UUID,
        onActivity: (() async -> Void)? = nil,
        ollamaClient: OllamaClient = OllamaClient(),
        chatClient: OllamaChatClient? = nil,
        catalog: ModelCatalog = .load(),
        attachmentImporter: SessionAttachmentImporter = SessionAttachmentImporter()
    ) {
        self.store = store
        self.sessionID = sessionID
        self.onActivity = onActivity
        self.catalog = catalog
        self.attachmentImporter = attachmentImporter

        if let scenario = Self.uiTestChatScenario() {
            let uiTestModelTag = Self.uiTestActiveModelTag()
            self.ollamaClient = UITestOllamaStatusClient(modelTag: uiTestModelTag)
            self.chatClient = UITestOllamaChatClient(scenario: scenario)
        } else {
            self.ollamaClient = ollamaClient
            self.chatClient = chatClient ?? OllamaChatClient(ollamaClient: ollamaClient)
        }

        self.activeModelTagStorage = Self.storedActiveModelTag()
        self.lastStreamModel = Self.storedLastStreamModel(for: sessionID)
        self.historyContextLevel = Self.storedHistoryContextLevel()
        self.fileContextLevel = Self.storedFileContextLevel()
    }

    init(
        store: SessionStore,
        sessionID: UUID,
        onActivity: (() async -> Void)? = nil,
        ollamaClient: any OllamaStatusProviding,
        chatClient: any OllamaChatStreaming,
        catalog: ModelCatalog = .load(),
        attachmentImporter: SessionAttachmentImporter = SessionAttachmentImporter()
    ) {
        self.store = store
        self.sessionID = sessionID
        self.onActivity = onActivity
        self.ollamaClient = ollamaClient
        self.chatClient = chatClient
        self.catalog = catalog
        self.attachmentImporter = attachmentImporter
        self.activeModelTagStorage = Self.storedActiveModelTag()
        self.lastStreamModel = Self.storedLastStreamModel(for: sessionID)
        self.historyContextLevel = Self.storedHistoryContextLevel()
        self.fileContextLevel = Self.storedFileContextLevel()
    }

    var activeModelSupportsSpeechInput: Bool {
        activeModelCapabilities.speechInput
    }

    var activeModelSupportsSpeechOutput: Bool {
        activeModelCapabilities.speechOutput
    }

    var activeModelSupportsFileUploads: Bool {
        activeModelCapabilities.fileUploads
    }

    var activeModelTag: String? {
        get {
            activeModelTagStorage
        }
        set {
            if let value = newValue?.nonEmptyTrimmed {
                activeModelTagStorage = value
                UserDefaults.standard.set(value, forKey: LoomPreferenceKeys.activeModelTag)
            } else {
                activeModelTagStorage = nil
                UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.activeModelTag)
            }
        }
    }

    var activeModelSelectionLabel: String {
        guard let activeModelTag else {
            return "Choose Model"
        }

        let baseName = modelDisplayName(for: activeModelTag)
        guard availableModelTags.contains(activeModelTag) else {
            return "\(baseName) (Unavailable)"
        }
        return baseName
    }

    var activeModelCapabilityNote: String? {
        guard let activeModelTag,
              let model = catalog.byTag(activeModelTag) else {
            return nil
        }

        let capabilities = model.resolvedCapabilities
        var unavailable: [String] = []
        if !capabilities.speechInput {
            unavailable.append("speech input")
        }
        if !capabilities.speechOutput {
            unavailable.append("speech output")
        }
        if !capabilities.fileUploads {
            unavailable.append("file uploads")
        }

        guard !unavailable.isEmpty else { return nil }
        let unavailableList = unavailable.joined(separator: ", ")
        return "\(model.displayName) currently doesn’t support \(unavailableList)."
    }

    var isVoiceReplyEnabled: Bool {
        get {
            if let stored = UserDefaults.standard.object(forKey: LoomPreferenceKeys.voiceReplyEnabled) as? Bool {
                return stored
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: LoomPreferenceKeys.voiceReplyEnabled)
        }
    }

    var contextBudgetSnapshot: ContextBudgetSnapshot {
        let contextMessages = nextTurnContextMessagesPreview()
        let estimatedTokens = Self.estimatedTokenCount(for: contextMessages)
        return ContextBudgetSnapshot(
            estimatedTokens: estimatedTokens,
            budgetTokens: contextTokenBudget
        )
    }

    var contextBudgetHint: String {
        "\(historyContextLevel.title) history · \(fileContextLevel.title) files"
    }

    func modelDisplayName(for tag: String) -> String {
        catalog.byTag(tag)?.displayName ?? tag
    }

    func selectActiveModel(tag: String) {
        activeModelTag = tag
        banner = nil
    }

    func refreshInstalledModels() async {
        synchronizeActiveModelSelectionFromPreferences()
        let diagnosis = await ollamaClient.diagnose()
        guard diagnosis.isRunning else {
            availableModelTags = []
            return
        }

        do {
            let listedModels = try await ollamaClient.listModels()
            availableModelTags = applyPreferredModelOrder(to: listedModels).map(\.tag)
        } catch {
            availableModelTags = []
        }
    }

    func load() async {
        do {
            messages = try await store.loadRecentMessages(sessionID: sessionID, limit: 200)
            isShowingFullHistory = false
            generatingMessageIndex = nil
        } catch {
            messages = []
            isShowingFullHistory = false
            generatingMessageIndex = nil
        }

        await refreshInstalledModels()
    }

    func loadFullHistory() async {
        do {
            messages = try await store.loadMessages(sessionID: sessionID)
            isShowingFullHistory = true
            generatingMessageIndex = nil
        } catch {
            // Keep current tail-loaded messages if full history fails.
        }
    }

    func importAttachments(from urls: [URL]) async {
        guard !urls.isEmpty else { return }

        let result = await attachmentImporter.importFiles(at: urls)
        var skippedMessages = result.skipped

        if !result.imported.isEmpty {
            var mergedByPath = Dictionary(uniqueKeysWithValues: pendingAttachments.map { ($0.sourcePath, $0) })
            for attachment in result.imported {
                if mergedByPath[attachment.sourcePath] != nil {
                    mergedByPath[attachment.sourcePath] = attachment
                    continue
                }

                if mergedByPath.count >= Self.maxPendingAttachmentCount {
                    skippedMessages.append("\(attachment.fileName) (too many files; keep up to \(Self.maxPendingAttachmentCount))")
                    continue
                }

                mergedByPath[attachment.sourcePath] = attachment
            }
            pendingAttachments = mergedByPath.values.sorted { lhs, rhs in
                lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
            }
        }

        if !skippedMessages.isEmpty {
            let summary = skippedMessages.prefix(2).joined(separator: ", ")
            let skippedCount = skippedMessages.count
            let suffix = skippedCount > 2 ? " and \(skippedCount - 2) more." : "."
            banner = BannerState(
                text: "Some files couldn’t be added: \(summary)\(suffix)",
                actionTitle: nil,
                action: nil
            )
        } else if !result.imported.isEmpty {
            banner = nil
        }
    }

    func removeAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func sendDraft() async {
        guard !isGenerating, !isPreparingGeneration else { return }
        isPreparingGeneration = true
        defer { isPreparingGeneration = false }
        synchronizeActiveModelSelectionFromPreferences()

        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if fileContextLevel != .off && !pendingAttachments.isEmpty && !activeModelSupportsFileUploads {
            banner = BannerState(
                text: "This model can’t use uploaded files yet. Choose one with file upload support.",
                actionTitle: "Choose Model",
                action: .browseModels
            )
            return
        }

        guard let activeModelTag else {
            banner = BannerState(
                text: "Choose a model to chat with.",
                actionTitle: "Choose Model",
                action: .browseModels
            )
            return
        }

        let diagnosis = await ollamaClient.diagnose()
        guard diagnosis.isRunning else {
            banner = BannerState(
                text: "Loom can’t reach Ollama. Start it to continue.",
                actionTitle: diagnosis.isInstalled ? "Start Ollama" : "Install Ollama…",
                action: .openOrInstallOllama
            )
            return
        }

        let userMessage = ChatMessage(role: .user, content: text)
        let attachmentsForThisTurn = pendingAttachments

        do {
            try await store.appendMessage(userMessage, sessionID: sessionID)
            messages.append(userMessage)
            draft = ""
            pendingAttachments = []
            banner = nil

            if let onActivity {
                await onActivity()
            }
        } catch {
            banner = BannerState(
                text: "Loom couldn’t save your message. Try again.",
                actionTitle: nil,
                action: nil
            )
            return
        }

        let assistantPlaceholder = ChatMessage(role: .assistant, content: "")
        messages.append(assistantPlaceholder)
        isGenerating = true
        generatingMessageID = assistantPlaceholder.id
        generatingMessageIndex = messages.index(before: messages.endIndex)

        let historyLimit = historyContextLevel.messageLimit
        var context: [ChatMessage]
        if didSwitchModels(from: lastStreamModel, to: activeModelTag) {
            context = contextMessagesForModelSwitch(limit: historyLimit)
        } else {
            context = contextMessages(excluding: assistantPlaceholder.id, limit: historyLimit)
        }
        if let attachmentContext = attachmentContextMessage(
            for: attachmentsForThisTurn,
            level: fileContextLevel
        ) {
            context.append(attachmentContext)
        }
        lastStreamModel = activeModelTag
        persistLastStreamModel(activeModelTag)
        lastStreamContext = context
        lastStreamPlaceholderID = assistantPlaceholder.id

        startStreamingReply(
            model: activeModelTag,
            placeholderID: assistantPlaceholder.id,
            context: context
        )
    }

    func stopGenerating() {
        let placeholderID = generatingMessageID
        generationTask?.cancel()
        generationTask = nil
        generatingMessageID = nil
        generatingMessageIndex = nil
        isGenerating = false

        if let placeholderID {
            Task { [weak self] in
                await self?.persistAssistantMessage(id: placeholderID, forcePersist: false)
            }
        }
    }

    func retryLastReply() async {
        guard !isGenerating, !isPreparingGeneration else { return }
        isPreparingGeneration = true
        defer { isPreparingGeneration = false }
        synchronizeActiveModelSelectionFromPreferences()
        guard let context = lastStreamContext else {
            banner = BannerState(
                text: "There isn’t a previous reply to retry yet.",
                actionTitle: nil,
                action: nil
            )
            return
        }
        guard let model = activeModelTag ?? lastStreamModel else {
            banner = BannerState(
                text: "Choose a model to chat with.",
                actionTitle: "Choose Model",
                action: .browseModels
            )
            return
        }
        let effectiveContext: [ChatMessage]
        if didSwitchModels(from: lastStreamModel, to: model) {
            effectiveContext = contextMessagesForModelSwitch(limit: historyContextLevel.messageLimit)
        } else {
            effectiveContext = context
        }

        let diagnosis = await ollamaClient.diagnose()
        guard diagnosis.isRunning else {
            banner = BannerState(
                text: "Loom can’t reach Ollama. Start it to continue.",
                actionTitle: diagnosis.isInstalled ? "Start Ollama" : "Install Ollama…",
                action: .openOrInstallOllama
            )
            return
        }

        if let failedPlaceholderID = lastStreamPlaceholderID,
           let failedIndex = resolvedMessageIndex(for: failedPlaceholderID) {
            messages.remove(at: failedIndex)
        }

        let freshPlaceholder = ChatMessage(role: .assistant, content: "")
        messages.append(freshPlaceholder)
        generatingMessageID = freshPlaceholder.id
        generatingMessageIndex = messages.index(before: messages.endIndex)
        isGenerating = true
        banner = nil
        lastStreamModel = model
        persistLastStreamModel(model)
        lastStreamContext = effectiveContext
        lastStreamPlaceholderID = freshPlaceholder.id

        startStreamingReply(
            model: model,
            placeholderID: freshPlaceholder.id,
            context: effectiveContext
        )
    }

    private var activeModelCapabilities: CatalogModelCapabilities {
        guard let activeModelTag,
              let model = catalog.byTag(activeModelTag) else {
            return .default
        }
        return model.resolvedCapabilities
    }

    private func didSwitchModels(from previousModel: String?, to currentModel: String?) -> Bool {
        guard let previousModel = previousModel?.nonEmptyTrimmed,
              let currentModel = currentModel?.nonEmptyTrimmed else {
            return false
        }
        return previousModel != currentModel
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

    private var contextTokenBudget: Int {
        historyContextLevel.baseTokenBudget + fileContextLevel.additionalTokenBudget
    }

    private func nextTurnContextMessagesPreview() -> [ChatMessage] {
        let historyLimit = historyContextLevel.messageLimit
        let switchedModels = didSwitchModels(from: lastStreamModel, to: activeModelTag)

        var context: [ChatMessage]
        if switchedModels {
            context = contextMessagesForModelSwitch(source: messages, limit: historyLimit)
        } else {
            context = contextMessages(source: messages, excluding: nil, limit: historyLimit)
        }

        if let trimmedDraft = draft.nonEmptyTrimmed {
            context.append(ChatMessage(role: .user, content: trimmedDraft))
        }

        if let attachmentContext = attachmentContextMessage(for: pendingAttachments, level: fileContextLevel) {
            context.append(attachmentContext)
        }

        return context
    }

    private func attachmentContextMessage(
        for attachments: [PendingAttachment],
        level: FileContextLevel
    ) -> ChatMessage? {
        guard level != .off else { return nil }
        guard !attachments.isEmpty else { return nil }

        var lines: [String] = [
            "Use the attached local file excerpts as trusted context when relevant.",
            "If you cite details from an attachment, name the file in your answer."
        ]
        lines.append("")

        var remainingCharacters = level.attachmentCharacterBudget
        var didTrimForBudget = false
        var includedCount = 0

        for attachment in attachments {
            guard remainingCharacters > 0 else {
                didTrimForBudget = true
                break
            }

            let excerpt = String(attachment.contentPreview.prefix(remainingCharacters))
            guard excerpt.nonEmptyTrimmed != nil else { continue }

            lines.append("[\(attachment.fileName)]")
            lines.append(excerpt)
            lines.append("")

            includedCount += 1
            if excerpt.count < attachment.contentPreview.count {
                didTrimForBudget = true
            }
            remainingCharacters -= excerpt.count
        }

        if includedCount < attachments.count {
            didTrimForBudget = true
        }

        if didTrimForBudget {
            lines.append("Note: Loom trimmed attachment excerpts to fit this message.")
        }

        return ChatMessage(role: .system, content: lines.joined(separator: "\n"))
    }

    private func persistLastStreamModel(_ model: String) {
        guard let model = model.nonEmptyTrimmed else { return }
        UserDefaults.standard.set(model, forKey: LoomPreferenceKeys.sessionLastStreamModelKey(for: sessionID))
    }

    private static func storedLastStreamModel(for sessionID: UUID) -> String? {
        UserDefaults.standard.string(forKey: LoomPreferenceKeys.sessionLastStreamModelKey(for: sessionID))?.nonEmptyTrimmed
    }

    private static func storedHistoryContextLevel() -> HistoryContextLevel {
        guard let raw = UserDefaults.standard.string(forKey: LoomPreferenceKeys.composerHistoryContextLevel),
              let level = HistoryContextLevel(rawValue: raw) else {
            return .balanced
        }
        return level
    }

    private static func storedFileContextLevel() -> FileContextLevel {
        guard let raw = UserDefaults.standard.string(forKey: LoomPreferenceKeys.composerFileContextLevel),
              let level = FileContextLevel(rawValue: raw) else {
            return .full
        }
        return level
    }

    private static func storedActiveModelTag() -> String? {
        UserDefaults.standard.string(forKey: LoomPreferenceKeys.activeModelTag)?.nonEmptyTrimmed
    }

    private func synchronizeActiveModelSelectionFromPreferences() {
        activeModelTagStorage = Self.storedActiveModelTag()
    }

    private static func uiTestChatScenario() -> UITestOllamaChatClient.Scenario? {
        if let raw = ProcessInfo.processInfo.environment[uiTestChatScenarioEnvironmentKey]?.nonEmptyTrimmed {
            return UITestOllamaChatClient.Scenario(rawValue: raw.lowercased())
        }
        if let raw = UserDefaults.standard.string(forKey: uiTestChatScenarioDefaultsKey)?.nonEmptyTrimmed {
            return UITestOllamaChatClient.Scenario(rawValue: raw.lowercased())
        }
        return nil
    }

    private static func uiTestActiveModelTag() -> String {
        if let tag = ProcessInfo.processInfo.environment[uiTestActiveModelTagEnvironmentKey]?.nonEmptyTrimmed {
            return tag
        }
        if let tag = UserDefaults.standard.string(forKey: LoomPreferenceKeys.activeModelTag)?.nonEmptyTrimmed {
            return tag
        }
        return "ui-test-model"
    }

    private func startStreamingReply(model: String, placeholderID: UUID, context: [ChatMessage]) {
        generationTask?.cancel()

        generationTask = Task { [weak self] in
            guard let self else { return }

            let buffer = StreamDeltaBuffer()
            let flushTask = Task { [weak self] in
                guard let self else { return }

                while !Task.isCancelled {
                    try? await Task.sleep(for: self.streamUpdateInterval)

                    let pending = await buffer.drain()
                    guard !pending.isEmpty else { continue }

                    await MainActor.run { self.applyDelta(pending, to: placeholderID) }
                }
            }

            var streamError: Error?
            var didFinishStream = false

            do {
                try await self.chatClient.streamChat(model: model, messages: context) { delta in
                    guard !delta.isEmpty else { return }
                    await buffer.append(delta)
                }
                didFinishStream = true
            } catch {
                streamError = error
            }

            flushTask.cancel()

            let tail = await buffer.drain()
            if !tail.isEmpty {
                await MainActor.run { self.applyDelta(tail, to: placeholderID) }
            }

            if let streamError, !(streamError is CancellationError) {
                await MainActor.run { self.handleStreamFailure(streamError) }
            }

            await self.persistAssistantMessage(id: placeholderID, forcePersist: didFinishStream)
            await MainActor.run { self.finishStreaming(placeholderID: placeholderID) }
        }
    }

    private func contextMessages(excluding messageID: UUID, limit: Int) -> [ChatMessage] {
        contextMessages(source: messages, excluding: messageID, limit: limit)
    }

    private func contextMessages(source: [ChatMessage], excluding messageID: UUID?, limit: Int) -> [ChatMessage] {
        guard limit > 0 else { return [] }

        if let messageID, source.last?.id == messageID {
            let context = source.dropLast()
            guard context.count > limit else { return Array(context) }
            return Array(context.suffix(limit))
        }

        let context = source.filter { message in
            guard let messageID else { return true }
            return message.id != messageID
        }
        guard context.count > limit else { return context }
        return Array(context.suffix(limit))
    }

    private func contextMessagesForModelSwitch(limit: Int) -> [ChatMessage] {
        contextMessagesForModelSwitch(source: messages, limit: limit)
    }

    private func contextMessagesForModelSwitch(source: [ChatMessage], limit: Int) -> [ChatMessage] {
        guard limit > 0 else { return [] }
        let userOnlyMessages = source.filter { $0.role == .user }
        guard userOnlyMessages.count > limit else {
            return userOnlyMessages
        }
        return Array(userOnlyMessages.suffix(limit))
    }

    private static func estimatedTokenCount(for messages: [ChatMessage]) -> Int {
        messages.reduce(into: 0) { total, message in
            let contentTokenEstimate = max(1, message.content.count / roughCharactersPerToken)
            total += contentTokenEstimate + 8
        }
    }

    private func applyDelta(_ delta: String, to messageID: UUID) {
        guard let index = resolvedMessageIndex(for: messageID) else { return }

        let existing = messages[index]
        messages[index] = ChatMessage(
            id: existing.id,
            role: existing.role,
            content: existing.content + delta,
            createdAt: existing.createdAt
        )
    }

    private func handleStreamFailure(_ error: Error) {
        if let streamError = error as? OllamaChatClient.StreamError {
            switch streamError {
            case .ollamaUnavailable:
                banner = BannerState(
                    text: "Loom can’t reach Ollama. Start it to continue.",
                    actionTitle: OllamaClient.detectInstalled() ? "Start Ollama" : "Install Ollama…",
                    action: .openOrInstallOllama
                )
                return

            case .serverError(let message) where isModelUnavailableErrorMessage(message):
                banner = BannerState(
                    text: "Loom can’t use this model right now. Choose another model.",
                    actionTitle: "Choose Model",
                    action: .browseModels
                )
                return

            case .serverError(let message) where isModelLoadingErrorMessage(message):
                banner = BannerState(
                    text: "That model is still loading. Try again in a moment.",
                    actionTitle: "Retry",
                    action: .retryLastReply
                )
                return

            default:
                break
            }
        }

        banner = BannerState(
            text: "Loom lost connection while generating. Try again.",
            actionTitle: "Retry",
            action: .retryLastReply
        )
    }

    private func isModelUnavailableErrorMessage(_ message: String) -> Bool {
        let normalized = normalizedServerErrorMessage(message)
        if normalized.contains("unknown model") {
            return true
        }
        if normalized.contains("model") && normalized.contains("not found") {
            return true
        }
        if normalized.contains("model") && normalized.contains("does not exist") {
            return true
        }
        return false
    }

    private func isModelLoadingErrorMessage(_ message: String) -> Bool {
        let normalized = normalizedServerErrorMessage(message)
        if normalized.contains("model is loading") {
            return true
        }
        if normalized.contains("loading model") {
            return true
        }
        if normalized.contains("model loading") {
            return true
        }
        return false
    }

    private func normalizedServerErrorMessage(_ message: String) -> String {
        message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func persistAssistantMessage(id: UUID, forcePersist: Bool) async {
        guard let index = resolvedMessageIndex(for: id) else { return }
        guard !persistedAssistantMessageIDs.contains(id) else { return }

        let message = messages[index]
        let hasContent = message.content.nonEmptyTrimmed != nil

        guard forcePersist || hasContent else {
            messages.remove(at: index)
            if id == generatingMessageID {
                generatingMessageIndex = nil
            }
            return
        }

        do {
            try await store.appendMessage(message, sessionID: sessionID)
            persistedAssistantMessageIDs.insert(id)

            if let onActivity {
                await onActivity()
            }
        } catch {
            banner = BannerState(
                text: "Loom couldn’t save the assistant reply.",
                actionTitle: nil,
                action: nil
            )
        }
    }

    private func finishStreaming(placeholderID: UUID) {
        if generatingMessageID == placeholderID {
            generatingMessageID = nil
            generatingMessageIndex = nil
        }

        isGenerating = false
        generationTask = nil
    }

    private func resolvedMessageIndex(for id: UUID) -> Int? {
        if let cached = generatingMessageIndex,
           messages.indices.contains(cached),
           messages[cached].id == id {
            return cached
        }

        guard let found = messages.firstIndex(where: { $0.id == id }) else { return nil }

        if id == generatingMessageID {
            generatingMessageIndex = found
        }

        return found
    }
}

actor SessionAttachmentImporter {
    struct Result: Sendable {
        let imported: [SessionMessagesViewModel.PendingAttachment]
        let skipped: [String]
    }

    private static let maxFilesPerImport = 8
    private static let maxBytesPerTextFile = 2_000_000
    private static let maxBytesPerPDFFile = 5_000_000
    private static let maxCharactersPerAttachment = 6_000

    func importFiles(at urls: [URL]) -> Result {
        var imported: [SessionMessagesViewModel.PendingAttachment] = []
        var skipped: [String] = []
        let allowedURLs = Array(urls.prefix(Self.maxFilesPerImport))

        if urls.count > Self.maxFilesPerImport {
            for url in urls.dropFirst(Self.maxFilesPerImport) {
                skipped.append("\(url.lastPathComponent) (\(ImportError.tooManyFiles(maxFiles: Self.maxFilesPerImport).localizedDescription))")
            }
        }

        for url in allowedURLs {
            do {
                let text = try extractText(from: url)
                let normalized = normalize(text)
                guard let trimmed = normalized.nonEmptyTrimmed else {
                    skipped.append("\(url.lastPathComponent) (empty text)")
                    continue
                }

                let preview = String(trimmed.prefix(Self.maxCharactersPerAttachment))
                let attachment = SessionMessagesViewModel.PendingAttachment(
                    id: UUID(),
                    fileName: url.lastPathComponent,
                    sourcePath: url.path,
                    contentPreview: preview,
                    originalCharacterCount: trimmed.count
                )
                imported.append(attachment)
            } catch {
                skipped.append("\(url.lastPathComponent) (\(error.localizedDescription))")
            }
        }

        return Result(imported: imported, skipped: skipped)
    }

    private func extractText(from url: URL) throws -> String {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let isPDF = url.pathExtension.lowercased() == "pdf"
        let maxBytes = isPDF ? Self.maxBytesPerPDFFile : Self.maxBytesPerTextFile

        if let fileSize = fileSizeInBytes(for: url), fileSize > maxBytes {
            throw ImportError.fileTooLarge(maxBytes: maxBytes)
        }

        if isPDF {
            guard let document = PDFDocument(url: url), let text = document.string else {
                throw ImportError.unreadable
            }
            return text
        }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        if data.count > maxBytes {
            throw ImportError.fileTooLarge(maxBytes: maxBytes)
        }
        if Self.isLikelyBinary(data) {
            throw ImportError.unsupportedType
        }

        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1] {
            if let decoded = String(data: data, encoding: encoding), decoded.nonEmptyTrimmed != nil {
                return decoded
            }
        }

        throw ImportError.unreadable
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private func fileSizeInBytes(for url: URL) -> Int? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return values.fileSize ?? values.fileAllocatedSize ?? values.totalFileAllocatedSize
    }

    nonisolated private static func isLikelyBinary(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let sample = data.prefix(2_048)
        guard !sample.isEmpty else { return false }

        let controlCharacterCount = sample.reduce(into: 0) { count, byte in
            let isControl = byte < 0x09 || (byte > 0x0D && byte < 0x20)
            if isControl {
                count += 1
            }
        }

        return Double(controlCharacterCount) / Double(sample.count) > 0.12
    }

    private enum ImportError: LocalizedError {
        case unsupportedType
        case tooManyFiles(maxFiles: Int)
        case fileTooLarge(maxBytes: Int)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unsupportedType:
                return "unsupported format"
            case .tooManyFiles(let maxFiles):
                return "too many files (keep up to \(maxFiles))"
            case .fileTooLarge(let maxBytes):
                let maxLabel = ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)
                return "file is too large (max \(maxLabel))"
            case .unreadable:
                return "couldn’t read text"
            }
        }
    }
}

private actor StreamDeltaBuffer {
    private var pending: String = ""

    func append(_ delta: String) {
        pending.append(delta)
    }

    func drain() -> String {
        defer { pending = "" }
        return pending
    }
}

private actor UITestOllamaStatusClient: OllamaStatusProviding {
    private let modelTag: String

    init(modelTag: String) {
        self.modelTag = modelTag
    }

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
        [OllamaModel(tag: modelTag)]
    }

    func deleteModel(name: String) async throws {}

    func pullModel(name: String, onProgress: @Sendable (PullProgress) -> Void) async throws {}
}

private actor UITestOllamaChatClient: OllamaChatStreaming {
    enum Scenario: String {
        case streamSuccess = "stream_success"
        case cancelablePartial = "cancelable_partial"
    }

    private let scenario: Scenario

    init(scenario: Scenario) {
        self.scenario = scenario
    }

    func streamChat(
        model: String,
        messages: [ChatMessage],
        onDelta: @Sendable (String) async -> Void
    ) async throws {
        switch scenario {
        case .streamSuccess:
            for delta in ["Hello", " from", " stub", " response"] {
                try Task.checkCancellation()
                await onDelta(delta)
                try await Task.sleep(for: .milliseconds(200))
            }

        case .cancelablePartial:
            for _ in 0..<200 {
                try Task.checkCancellation()
                await onDelta("partial ")
                try await Task.sleep(for: .milliseconds(120))
            }
        }
    }
}

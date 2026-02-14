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

    private let store: SessionStore
    private let sessionID: UUID
    private let onActivity: (() async -> Void)?
    private let ollamaClient: any OllamaStatusProviding
    private let chatClient: any OllamaChatStreaming
    private let catalog: ModelCatalog
    private let attachmentImporter: SessionAttachmentImporter
    private let streamUpdateInterval: Duration = .milliseconds(60)
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
    private var lastStreamModel: String?
    private var lastStreamContext: [ChatMessage]?
    private var lastStreamPlaceholderID: UUID?
    private var generatingMessageIndex: Int?

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

        self.lastStreamModel = Self.storedLastStreamModel(for: sessionID)
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
        self.lastStreamModel = Self.storedLastStreamModel(for: sessionID)
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

    var activeModelCapabilityNote: String? {
        guard let activeModelTag = selectedActiveModelTag,
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
        if !result.imported.isEmpty {
            var mergedByPath = Dictionary(uniqueKeysWithValues: pendingAttachments.map { ($0.sourcePath, $0) })
            for attachment in result.imported {
                mergedByPath[attachment.sourcePath] = attachment
            }
            pendingAttachments = mergedByPath.values.sorted { lhs, rhs in
                lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
            }
        }

        if !result.skipped.isEmpty {
            let summary = result.skipped.prefix(2).joined(separator: ", ")
            let skippedCount = result.skipped.count
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
        guard !isGenerating else { return }

        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if !pendingAttachments.isEmpty && !activeModelSupportsFileUploads {
            banner = BannerState(
                text: "This model can’t use uploaded files yet. Choose one with file upload support.",
                actionTitle: "Choose Model",
                action: .browseModels
            )
            return
        }

        guard let activeModel = selectedActiveModelTag else {
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

        var context: [ChatMessage]
        if didSwitchModels(from: lastStreamModel, to: activeModel) {
            context = contextMessagesForModelSwitch(limit: 20)
        } else {
            context = contextMessages(excluding: assistantPlaceholder.id, limit: 20)
        }
        if let attachmentContext = attachmentContextMessage(for: attachmentsForThisTurn) {
            context.append(attachmentContext)
        }
        lastStreamModel = activeModel
        persistLastStreamModel(activeModel)
        lastStreamContext = context
        lastStreamPlaceholderID = assistantPlaceholder.id

        startStreamingReply(
            model: activeModel,
            placeholderID: assistantPlaceholder.id,
            context: context
        )
    }

    func stopGenerating() {
        generationTask?.cancel()
    }

    func retryLastReply() async {
        guard !isGenerating else { return }
        guard let context = lastStreamContext else {
            banner = BannerState(
                text: "There isn’t a previous reply to retry yet.",
                actionTitle: nil,
                action: nil
            )
            return
        }
        guard let model = selectedActiveModelTag ?? lastStreamModel else {
            banner = BannerState(
                text: "Choose a model to chat with.",
                actionTitle: "Choose Model",
                action: .browseModels
            )
            return
        }
        let effectiveContext: [ChatMessage]
        if didSwitchModels(from: lastStreamModel, to: model) {
            effectiveContext = contextMessagesForModelSwitch(limit: 20)
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

    private var selectedActiveModelTag: String? {
        UserDefaults.standard.string(forKey: LoomPreferenceKeys.activeModelTag)?.nonEmptyTrimmed
    }

    private var activeModelCapabilities: CatalogModelCapabilities {
        guard let activeModelTag = selectedActiveModelTag,
              let model = catalog.byTag(activeModelTag) else {
            return .default
        }
        return model.resolvedCapabilities
    }

    private func contextMessagesForModelSwitch(limit: Int) -> [ChatMessage] {
        guard limit > 0 else { return [] }
        let userOnlyMessages = messages.filter { $0.role == .user }
        guard userOnlyMessages.count > limit else {
            return userOnlyMessages
        }
        return Array(userOnlyMessages.suffix(limit))
    }

    private func didSwitchModels(from previousModel: String?, to currentModel: String?) -> Bool {
        guard let previousModel = previousModel?.nonEmptyTrimmed,
              let currentModel = currentModel?.nonEmptyTrimmed else {
            return false
        }
        return previousModel != currentModel
    }

    private func attachmentContextMessage(for attachments: [PendingAttachment]) -> ChatMessage? {
        guard !attachments.isEmpty else { return nil }

        var lines: [String] = [
            "Use the attached local file excerpts as trusted context when relevant.",
            "If you cite details from an attachment, name the file in your answer."
        ]
        lines.append("")

        for attachment in attachments {
            lines.append("[\(attachment.fileName)]")
            lines.append(attachment.contentPreview)
            lines.append("")
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
        guard limit > 0 else { return [] }

        if messages.last?.id == messageID {
            let context = messages.dropLast()
            guard context.count > limit else { return Array(context) }
            return Array(context.suffix(limit))
        }

        let context = messages.filter { $0.id != messageID }
        guard context.count > limit else { return context }
        return Array(context.suffix(limit))
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

    private static let maxBytesPerTextFile = 2_000_000
    private static let maxCharactersPerAttachment = 6_000

    func importFiles(at urls: [URL]) -> Result {
        var imported: [SessionMessagesViewModel.PendingAttachment] = []
        var skipped: [String] = []

        for url in urls {
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

        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url), let text = document.string else {
                throw ImportError.unreadable
            }
            return text
        }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        if data.count > Self.maxBytesPerTextFile {
            throw ImportError.fileTooLarge
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
        case fileTooLarge
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unsupportedType:
                return "unsupported format"
            case .fileTooLarge:
                return "file is too large"
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

import Foundation
import Observation

@MainActor
@Observable
final class SessionMessagesViewModel {
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
    private let streamUpdateInterval: Duration = .milliseconds(60)

    var messages: [ChatMessage] = []
    var draft: String = ""
    var isGenerating: Bool = false
    var generationTask: Task<Void, Never>?
    var generatingMessageID: UUID?
    var banner: BannerState?
    private(set) var isShowingFullHistory: Bool = false
    private var lastStreamModel: String?
    private var lastStreamContext: [ChatMessage]?
    private var lastStreamPlaceholderID: UUID?
    private var generatingMessageIndex: Int?

    init(
        store: SessionStore,
        sessionID: UUID,
        onActivity: (() async -> Void)? = nil,
        ollamaClient: OllamaClient = OllamaClient(),
        chatClient: OllamaChatClient? = nil
    ) {
        self.store = store
        self.sessionID = sessionID
        self.onActivity = onActivity
        self.ollamaClient = ollamaClient
        self.chatClient = chatClient ?? OllamaChatClient(ollamaClient: ollamaClient)
        self.lastStreamModel = Self.storedLastStreamModel(for: sessionID)
    }

    init(
        store: SessionStore,
        sessionID: UUID,
        onActivity: (() async -> Void)? = nil,
        ollamaClient: any OllamaStatusProviding,
        chatClient: any OllamaChatStreaming
    ) {
        self.store = store
        self.sessionID = sessionID
        self.onActivity = onActivity
        self.ollamaClient = ollamaClient
        self.chatClient = chatClient
        self.lastStreamModel = Self.storedLastStreamModel(for: sessionID)
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

    func sendDraft() async {
        guard !isGenerating else { return }

        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

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

        do {
            try await store.appendMessage(userMessage, sessionID: sessionID)
            messages.append(userMessage)
            draft = ""
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

        let context: [ChatMessage]
        if didSwitchModels(from: lastStreamModel, to: activeModel) {
            context = contextMessagesForModelSwitch(limit: 20)
        } else {
            context = contextMessages(excluding: assistantPlaceholder.id, limit: 20)
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

    private func persistLastStreamModel(_ model: String) {
        guard let model = model.nonEmptyTrimmed else { return }
        UserDefaults.standard.set(model, forKey: LoomPreferenceKeys.sessionLastStreamModelKey(for: sessionID))
    }

    private static func storedLastStreamModel(for sessionID: UUID) -> String? {
        UserDefaults.standard.string(forKey: LoomPreferenceKeys.sessionLastStreamModelKey(for: sessionID))?.nonEmptyTrimmed
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
        if let streamError = error as? OllamaChatClient.StreamError,
           case .ollamaUnavailable = streamError {
            banner = BannerState(
                text: "Loom can’t reach Ollama. Start it to continue.",
                actionTitle: OllamaClient.detectInstalled() ? "Start Ollama" : "Install Ollama…",
                action: .openOrInstallOllama
            )
            return
        }

        banner = BannerState(
            text: "Connection lost. Try again.",
            actionTitle: "Retry",
            action: .retryLastReply
        )
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

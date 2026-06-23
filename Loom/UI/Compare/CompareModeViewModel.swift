import Foundation
import Observation

@MainActor
@Observable
final class CompareModeViewModel {
    enum ResponseState: Equatable {
        case idle
        case loading
        case success(String)
        case failure(String)
    }

    private let ollamaClient: any OllamaStatusProviding
    private let chatClient: any OllamaChatStreaming
    private var compareTask: Task<Void, Never>?
    private var compareGeneration: UInt64 = 0

    var availableModelTags: [String] = []
    var leftModelTag: String?
    var rightModelTag: String?
    var prompt: String = ""
    var leftState: ResponseState = .idle
    var rightState: ResponseState = .idle
    var isRunningCompare: Bool = false
    var bannerText: String?

    init(ollamaClient: OllamaClient = OllamaClient(), chatClient: (any OllamaChatStreaming)? = nil) {
        self.ollamaClient = ollamaClient
        self.chatClient = chatClient ?? OllamaChatClient(ollamaClient: ollamaClient)
    }

    init(ollamaClient: any OllamaStatusProviding, chatClient: any OllamaChatStreaming) {
        self.ollamaClient = ollamaClient
        self.chatClient = chatClient
    }

    func loadModels() async {
        let diagnosis = await ollamaClient.diagnose()
        guard diagnosis.isRunning else {
            availableModelTags = []
            bannerText = "Loom can’t reach Ollama. Start it to continue."
            return
        }

        do {
            availableModelTags = try await ollamaClient.listModels().map(\.tag)
            bannerText = nil

            if leftModelTag == nil {
                leftModelTag = availableModelTags.first
            }

            if rightModelTag == nil {
                rightModelTag = availableModelTags.dropFirst().first ?? availableModelTags.first
            }
        } catch {
            availableModelTags = []
            bannerText = "Loom couldn’t load models right now. Try again."
        }
    }

    func runCompare() {
        guard !isRunningCompare else { return }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            bannerText = "Enter a prompt to compare model responses."
            return
        }

        guard let leftModelTag, let rightModelTag else {
            bannerText = "Choose two models to compare."
            return
        }

        guard leftModelTag != rightModelTag else {
            bannerText = "Choose two different models to compare."
            return
        }

        guard availableModelTags.contains(leftModelTag), availableModelTags.contains(rightModelTag) else {
            bannerText = "One selected model is unavailable. Choose installed models and try again."
            return
        }

        isRunningCompare = true
        bannerText = nil
        leftState = .loading
        rightState = .loading

        compareGeneration &+= 1
        let generation = compareGeneration

        compareTask = Task { [weak self] in
            guard let self else { return }

            async let leftResult = self.compareOnce(modelTag: leftModelTag, prompt: trimmedPrompt)
            async let rightResult = self.compareOnce(modelTag: rightModelTag, prompt: trimmedPrompt)

            let (resolvedLeftState, resolvedRightState) = await (leftResult, rightResult)

            guard !Task.isCancelled, self.compareGeneration == generation else { return }

            self.leftState = resolvedLeftState
            self.rightState = resolvedRightState
            self.finishCompare(generation: generation)

            if case .failure = self.leftState, case .failure = self.rightState {
                self.bannerText = "Both model responses failed. Try again or choose different models."
            }
        }
    }

    func cancelCompare() {
        compareGeneration &+= 1
        compareTask?.cancel()
        compareTask = nil

        guard isRunningCompare else { return }
        isRunningCompare = false
        if leftState == .loading {
            leftState = .idle
        }
        if rightState == .loading {
            rightState = .idle
        }
    }

    private func compareOnce(modelTag: String, prompt: String) async -> ResponseState {
        let accumulator = ResponseAccumulator()
        do {
            try Task.checkCancellation()
            try await chatClient.streamChat(
                model: modelTag,
                messages: [ChatMessage(role: .user, content: prompt)],
                onDelta: { delta in
                    await accumulator.append(delta)
                }
            )
            try Task.checkCancellation()
            let value = await accumulator.value().trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(value.isEmpty ? "(No response content)" : value)
        } catch is CancellationError {
            return .idle
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func finishCompare(generation: UInt64) {
        guard compareGeneration == generation else { return }
        compareTask = nil
        isRunningCompare = false
    }
}

private actor ResponseAccumulator {
    private var text: String = ""

    func append(_ delta: String) {
        text.append(delta)
    }

    func value() -> String {
        text
    }
}

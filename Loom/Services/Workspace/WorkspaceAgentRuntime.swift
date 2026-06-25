import Foundation

protocol WorkspaceAgentProviding: Actor {
    func respond(to request: WorkspaceAgentRequest) async throws -> WorkspaceAgentProviderResponse
}

nonisolated struct WorkspaceAgentTurnResult: Sendable {
    let messages: [ChatMessage]
    let toolResults: [DeveloperToolResult]
    let changeRecords: [WorkspaceChangeRecord]
}

actor WorkspaceAgentRuntime {
    private let store: WorkspaceStore
    private let runner: any DeveloperToolRunning
    private let provider: any WorkspaceAgentProviding
    private let maxIterations: Int

    init(
        store: WorkspaceStore,
        runner: any DeveloperToolRunning,
        provider: any WorkspaceAgentProviding,
        maxIterations: Int = 3
    ) {
        self.store = store
        self.runner = runner
        self.provider = provider
        self.maxIterations = maxIterations
    }

    func runTurn(session: WorkspaceSession, userText: String, existingMessages: [ChatMessage]) async throws -> WorkspaceAgentTurnResult {
        let trimmedText = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return WorkspaceAgentTurnResult(messages: [], toolResults: [], changeRecords: [])
        }

        let userMessage = ChatMessage(role: .user, content: trimmedText)
        try await store.appendMessage(userMessage, sessionID: session.id)

        var emittedMessages: [ChatMessage] = [userMessage]
        var workingMessages = existingMessages + [userMessage]
        var allToolResults: [DeveloperToolResult] = []
        var changeRecords: [WorkspaceChangeRecord] = []

        for _ in 0..<maxIterations {
            let index = await WorkspaceIndexer.snapshot(for: session, runner: runner)
            let response = try await provider.respond(
                to: WorkspaceAgentRequest(
                    session: session,
                    messages: workingMessages,
                    indexSnapshot: index,
                    toolResults: allToolResults
                )
            )

            let assistantMessage = ChatMessage(role: .assistant, content: response.message.nonEmptyTrimmed ?? "I checked the LoomX project.")
            try await store.appendMessage(assistantMessage, sessionID: session.id)
            emittedMessages.append(assistantMessage)
            workingMessages.append(assistantMessage)

            guard !response.toolCalls.isEmpty else {
                break
            }

            for toolCall in response.toolCalls {
                let toolResult = await execute(toolCall, session: session)
                try await store.appendToolEvent(toolResult, sessionID: session.id)
                allToolResults.append(toolResult)

                if toolCall.tool == .applyPatch,
                   toolResult.status == .success,
                   let patch = toolCall.patch?.nonEmptyTrimmed {
                    let record = try await store.saveChangePatch(patch, toolResultID: toolResult.id, sessionID: session.id)
                    changeRecords.append(record)
                }

                let toolMessage = ChatMessage(role: .tool, content: toolMessageContent(for: toolResult))
                try await store.appendMessage(toolMessage, sessionID: session.id)
                emittedMessages.append(toolMessage)
                workingMessages.append(toolMessage)
            }
        }

        return WorkspaceAgentTurnResult(
            messages: emittedMessages,
            toolResults: allToolResults,
            changeRecords: changeRecords
        )
    }

    private func execute(_ toolCall: WorkspaceAgentToolCall, session: WorkspaceSession) async -> DeveloperToolResult {
        if toolCall.tool.isEditingTool && !session.allowsAutonomousEdits {
            return DeveloperToolResult(
                tool: toolCall.tool,
                status: .skipped,
                summary: "Autonomous edits are off for this LoomX project.",
                output: ""
            )
        }

        switch toolCall.tool {
        case .readFile:
            return await runner.readFile(session: session, relativePath: toolCall.relativePath ?? "")
        case .search:
            return await runner.search(session: session, pattern: toolCall.pattern ?? "")
        case .listFiles:
            let (result, _) = await runner.listFiles(session: session)
            return result
        case .writeFile:
            return await runner.writeFile(
                session: session,
                relativePath: toolCall.relativePath ?? "",
                contents: toolCall.contents ?? ""
            )
        case .applyPatch:
            return await runner.applyPatch(session: session, patch: toolCall.patch ?? "")
        case .gitDiff:
            return await runner.gitDiff(session: session)
        case .gitStatus:
            return await runner.gitStatus(session: session)
        case .xcodebuildList:
            let (result, _) = await runner.xcodebuildList(session: session)
            return result
        case .build:
            return await runner.build(session: session)
        case .test:
            return await runner.test(session: session)
        case .openInXcode:
            return await runner.openInXcode(session: session)
        }
    }

    private func toolMessageContent(for result: DeveloperToolResult) -> String {
        var parts = [
            "[\(result.tool.title)] \(result.status.rawValue)",
            result.summary
        ]
        if let output = result.output.nonEmptyTrimmed {
            parts.append(output)
        }
        return parts.joined(separator: "\n")
    }
}

actor LocalOllamaWorkspaceAgentProvider: WorkspaceAgentProviding {
    private let modelTag: String?
    private let chatClient: any OllamaChatStreaming

    init(modelTag: String?, chatClient: any OllamaChatStreaming) {
        self.modelTag = modelTag?.nonEmptyTrimmed
        self.chatClient = chatClient
    }

    func respond(to request: WorkspaceAgentRequest) async throws -> WorkspaceAgentProviderResponse {
        guard let modelTag else {
            return WorkspaceAgentProviderResponse(message: "Choose a local model before using LoomX.")
        }

        let accumulator = WorkspaceResponseAccumulator()
        try await chatClient.streamChat(
            model: modelTag,
            messages: promptMessages(for: request),
            onDelta: { delta in
                await accumulator.append(delta)
            }
        )
        let responseText = await accumulator.value()
        return WorkspaceToolCallParser.parse(responseText)
    }

    private func promptMessages(for request: WorkspaceAgentRequest) -> [ChatMessage] {
        let system = ChatMessage(role: .system, content: systemPrompt(for: request))
        return [system] + Array(request.messages.suffix(28))
    }

    private func systemPrompt(for request: WorkspaceAgentRequest) -> String {
        let project = request.session.selectedProject?.relativePath ?? "No Xcode project selected"
        let files = request.indexSnapshot.files.prefix(180).joined(separator: "\n")
        return """
        You are LoomX, Loom's coding agent. Work only inside the selected LoomX project.
        Use typed tools when you need code context or need to edit. Never ask for raw shell access.
        Prefer small diffs, preserve behavior, and run build or test tools after code changes when useful.

        LoomX project: \(request.session.displayName)
        Xcode project: \(project)
        Scheme: \(request.session.selectedScheme ?? "None")

        Indexed files:
        \(files)

        To call tools, reply with JSON in this shape:
        {"message":"short user-facing update","toolCalls":[{"tool":"readFile","relativePath":"path"}]}
        Supported tools: readFile, search, listFiles, writeFile, applyPatch, gitDiff, gitStatus, xcodebuildList, build, test, openInXcode.
        For applyPatch, provide a unified git patch in the patch field.
        If no tool is needed, answer normally.
        """
    }
}

actor CloudWorkspaceAgentProvider: WorkspaceAgentProviding {
    func respond(to request: WorkspaceAgentRequest) async throws -> WorkspaceAgentProviderResponse {
        WorkspaceAgentProviderResponse(
            message: "Cloud LoomX coding is enabled for this session, but no cloud provider is configured yet. Switch to Local to continue."
        )
    }
}

nonisolated enum WorkspaceToolCallParser {
    private struct ToolEnvelope: Decodable {
        let message: String?
        let toolCalls: [WorkspaceAgentToolCall]?
    }

    static func parse(_ text: String) -> WorkspaceAgentProviderResponse {
        let candidates = jsonCandidates(in: text)
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(ToolEnvelope.self, from: data) else {
                continue
            }
            return WorkspaceAgentProviderResponse(
                message: envelope.message?.nonEmptyTrimmed ?? text,
                toolCalls: envelope.toolCalls ?? []
            )
        }
        return WorkspaceAgentProviderResponse(message: text)
    }

    private static func jsonCandidates(in text: String) -> [String] {
        var candidates: [String] = []
        if let fenced = fencedJSON(in: text) {
            candidates.append(fenced)
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            candidates.append(String(text[start...end]))
        }
        candidates.append(text)
        return candidates
    }

    private static func fencedJSON(in text: String) -> String? {
        guard let fenceRange = text.range(of: "```") else { return nil }
        let afterFence = text[fenceRange.upperBound...]
        let contentStart: String.Index
        if afterFence.hasPrefix("json\n") {
            contentStart = afterFence.index(afterFence.startIndex, offsetBy: 4)
        } else {
            contentStart = afterFence.startIndex
        }
        guard let closeRange = afterFence[contentStart...].range(of: "```") else { return nil }
        return String(afterFence[contentStart..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private actor WorkspaceResponseAccumulator {
    private var text = ""

    func append(_ delta: String) {
        text.append(delta)
    }

    func value() -> String {
        text
    }
}

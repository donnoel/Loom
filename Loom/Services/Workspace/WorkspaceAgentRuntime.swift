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

        let directToolCalls = WorkspaceToolIntentDetector.toolCalls(for: trimmedText)
        for toolCall in directToolCalls {
            let toolResult = await execute(toolCall, session: session)
            try await store.appendToolEvent(toolResult, sessionID: session.id)
            allToolResults.append(toolResult)

            let toolMessage = ChatMessage(role: .tool, content: toolMessageContent(for: toolResult))
            workingMessages.append(toolMessage)
        }

        for iteration in 0..<maxIterations {
            let index = await WorkspaceIndexer.snapshot(for: session, runner: runner)
            let response = try await provider.respond(
                to: WorkspaceAgentRequest(
                    session: session,
                    messages: workingMessages,
                    indexSnapshot: index,
                    toolResults: allToolResults
                )
            )

            if response.toolCalls.isEmpty,
               shouldRequestToolFollowUp(
                userText: trimmedText,
                assistantMessage: response.message,
                toolResults: allToolResults,
                iteration: iteration
               ) {
                workingMessages.append(ChatMessage(role: .assistant, content: response.message))
                workingMessages.append(ChatMessage(role: .system, content: toolFollowUpPrompt))
                continue
            }

            let assistantMessage = ChatMessage(
                role: .assistant,
                content: response.message.nonEmptyTrimmed ?? "I checked the LoomX project."
            )
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
            guard let relativePath = toolCall.relativePath?.nonEmptyTrimmed else {
                return DeveloperToolResult(
                    tool: .writeFile,
                    status: .failure,
                    summary: "The model tried to write a file without a path.",
                    output: "Retry with a writeFile tool call that includes relativePath and contents."
                )
            }
            guard let contents = toolCall.contents else {
                return DeveloperToolResult(
                    tool: .writeFile,
                    status: .failure,
                    summary: "The model tried to write \(relativePath) without file contents.",
                    output: "Retry with an applyPatch tool call, or provide writeFile with both relativePath and full contents."
                )
            }
            return await runner.writeFile(
                session: session,
                relativePath: relativePath,
                contents: contents
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

    private var toolFollowUpPrompt: String {
        """
        The user asked LoomX to inspect or change the selected workspace. Your previous reply did not include toolCalls, so no work happened.
        Continue by returning only JSON with concrete toolCalls. Read files if you need context, use applyPatch or writeFile for edits, then build or test when useful.
        """
    }

    private func shouldRequestToolFollowUp(
        userText: String,
        assistantMessage: String,
        toolResults: [DeveloperToolResult],
        iteration: Int
    ) -> Bool {
        guard iteration < maxIterations - 1,
              userText.requestsWorkspaceAction,
              assistantMessage.announcesWorkspaceAction else {
            return false
        }
        return !toolResults.contains { result in
            result.status == .success && (
                result.tool.isEditingTool
                    || result.tool == .build
                    || result.tool == .test
                    || result.tool == .openInXcode
            )
        }
    }
}

private extension String {
    nonisolated var requestsWorkspaceAction: Bool {
        let normalized = lowercased()
        return normalized.contains("implement")
            || normalized.contains("make changes")
            || normalized.contains("change ")
            || normalized.contains("update ")
            || normalized.contains("edit ")
            || normalized.contains("fix ")
            || normalized.contains("build out")
            || normalized.contains("create ")
            || normalized.contains("add ")
            || normalized.contains("remove ")
            || normalized.contains("directly in xcode")
    }

    nonisolated var announcesWorkspaceAction: Bool {
        let normalized = lowercased()
        return normalized.contains("starting implementation")
            || normalized.contains("creating ")
            || normalized.contains("updating ")
            || normalized.contains("implementing ")
            || normalized.contains("i'll start")
            || normalized.contains("i will start")
            || normalized.contains("let me implement")
            || normalized.contains("i’ll implement")
            || normalized.contains("i will implement")
            || normalized.contains("i'll create")
            || normalized.contains("i will create")
            || normalized.contains("i’ll create")
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
            if !request.toolResults.isEmpty {
                return WorkspaceAgentProviderResponse(message: "I ran that LoomX tool. Review the activity output above.")
            }
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
        The JSON must be the entire reply when calling tools. Every tool call object must include the "tool" key.
        Supported tools: readFile, search, listFiles, writeFile, applyPatch, gitDiff, gitStatus, xcodebuildList, build, test, openInXcode.
        For applyPatch, provide a unified git patch in the patch field.
        For edits, prefer applyPatch. If you use writeFile, include relativePath and the complete contents field.
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

nonisolated enum WorkspaceToolIntentDetector {
    static func toolCalls(for text: String) -> [WorkspaceAgentToolCall] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = normalized.lowercased()

        if containsAny(lowercase, ["git status", "status"]) {
            return [WorkspaceAgentToolCall(tool: .gitStatus)]
        }
        if containsAny(lowercase, ["git diff", "show diff", "current diff", "what changed"]) {
            return [WorkspaceAgentToolCall(tool: .gitDiff)]
        }
        if containsAny(lowercase, ["xcode metadata", "list schemes", "schemes"]) {
            return [WorkspaceAgentToolCall(tool: .xcodebuildList)]
        }
        if containsBuildIntent(lowercase) {
            return [WorkspaceAgentToolCall(tool: .build)]
        }
        if containsTestIntent(lowercase) {
            return [WorkspaceAgentToolCall(tool: .test)]
        }
        if containsAny(lowercase, ["open in xcode", "open xcode"]) {
            return [WorkspaceAgentToolCall(tool: .openInXcode)]
        }
        if containsAny(lowercase, ["list files", "show files", "file list"]) {
            return [WorkspaceAgentToolCall(tool: .listFiles)]
        }
        if let pattern = searchPattern(in: normalized) {
            return [WorkspaceAgentToolCall(tool: .search, pattern: pattern)]
        }
        if let relativePath = readPath(in: normalized) {
            return [WorkspaceAgentToolCall(tool: .readFile, relativePath: relativePath)]
        }
        return []
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func containsBuildIntent(_ text: String) -> Bool {
        text == "build"
            || text == "run build"
            || text.hasPrefix("run build ")
            || text == "build project"
            || text == "build the project"
            || text == "build workspace"
            || text == "build the workspace"
    }

    private static func containsTestIntent(_ text: String) -> Bool {
        text == "test"
            || text == "run tests"
            || text == "run test"
            || text.hasPrefix("run tests ")
            || text.hasPrefix("run test ")
            || text == "test project"
            || text == "test the project"
            || text == "test workspace"
            || text == "test the workspace"
    }

    private static func searchPattern(in text: String) -> String? {
        let prefixes = ["search for ", "search ", "find "]
        for prefix in prefixes {
            guard let range = text.range(of: prefix, options: [.caseInsensitive]) else { continue }
            let pattern = text[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return pattern.nonEmptyTrimmed
        }
        return nil
    }

    private static func readPath(in text: String) -> String? {
        let prefixes = ["read file ", "read ", "open file ", "show file "]
        for prefix in prefixes {
            guard let range = text.range(of: prefix, options: [.caseInsensitive]) else { continue }
            let path = text[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard path.contains("/") || path.contains(".") else { continue }
            return path.nonEmptyTrimmed
        }
        return nil
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
        let fallbackToolCalls = looseToolCalls(in: text)
        if !fallbackToolCalls.isEmpty {
            return WorkspaceAgentProviderResponse(
                message: displayMessageBeforeJSON(in: text)
                    ?? quotedValue(for: "message", in: text)
                    ?? "I’ll inspect that with LoomX tools.",
                toolCalls: fallbackToolCalls
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

    private static func displayMessageBeforeJSON(in text: String) -> String? {
        guard let jsonStart = text.firstIndex(of: "{") else {
            return text.nonEmptyTrimmed
        }
        return String(text[..<jsonStart]).nonEmptyTrimmed
    }

    private static func looseToolCalls(in text: String) -> [WorkspaceAgentToolCall] {
        guard text.contains("toolCalls") else { return [] }

        var calls: [WorkspaceAgentToolCall] = []
        for tool in DeveloperToolName.allCases {
            var searchRange = text.startIndex..<text.endIndex
            let token = "\"\(tool.rawValue)\""

            while let range = text.range(of: token, options: [], range: searchRange) {
                if let call = looseToolCall(tool: tool, text: text, startingAt: range.lowerBound) {
                    calls.append(call)
                }
                searchRange = range.upperBound..<text.endIndex
            }
        }
        return calls
    }

    private static func looseToolCall(tool: DeveloperToolName, text: String, startingAt start: String.Index) -> WorkspaceAgentToolCall? {
        let end = text.index(start, offsetBy: min(600, text.distance(from: start, to: text.endIndex)))
        let objectText = String(text[start..<end])

        switch tool {
        case .readFile:
            guard let relativePath = quotedValue(for: "relativePath", in: objectText) else { return nil }
            return WorkspaceAgentToolCall(tool: .readFile, relativePath: relativePath)
        case .search:
            guard let pattern = quotedValue(for: "pattern", in: objectText) else { return nil }
            return WorkspaceAgentToolCall(tool: .search, pattern: pattern)
        case .writeFile:
            let relativePath = quotedValue(for: "relativePath", in: objectText)
            let contents = quotedValue(for: "contents", in: objectText)
            return WorkspaceAgentToolCall(tool: .writeFile, relativePath: relativePath, contents: contents)
        case .applyPatch:
            guard let patch = quotedValue(for: "patch", in: objectText) else { return nil }
            return WorkspaceAgentToolCall(tool: .applyPatch, patch: patch)
        case .listFiles, .gitDiff, .gitStatus, .xcodebuildList, .build, .test, .openInXcode:
            return WorkspaceAgentToolCall(tool: tool)
        }
    }

    private static func quotedValue(for key: String, in text: String) -> String? {
        guard let keyRange = text.range(of: "\"\(key)\""),
              let colonRange = text[keyRange.upperBound...].range(of: ":"),
              let openingQuote = text[colonRange.upperBound...].firstIndex(of: "\"") else {
            return nil
        }

        var value = ""
        var isEscaped = false
        var index = text.index(after: openingQuote)
        while index < text.endIndex {
            let character = text[index]
            if isEscaped {
                value.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return value.nonEmptyTrimmed
            } else {
                value.append(character)
            }
            index = text.index(after: index)
        }
        return nil
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

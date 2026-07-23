import Foundation
import Testing
@testable import Loom

private func cleanupSessionFolder(id: UUID) {
    UserDefaults.standard.removeObject(forKey: LoomPreferenceKeys.sessionLastStreamModelKey(for: id))
    guard let folder = try? LoomPaths.sessionFolder(for: id) else { return }
    guard FileManager.default.fileExists(atPath: folder.path) else { return }
    try? FileManager.default.removeItem(at: folder)
}

private func appendRawJSONLLine(_ line: String, to url: URL) throws {
    let payload = Data("\(line)\n".utf8)

    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }

    try handle.seekToEnd()
    try handle.write(contentsOf: payload)
}

private func decodeMetadata(at url: URL) throws -> Session.Metadata {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(Session.Metadata.self, from: data)
}

private func fixedDate(_ iso8601: String) -> Date {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: iso8601) else {
        Issue.record("Failed to build fixed test date: \(iso8601)")
        return Date(timeIntervalSince1970: 0)
    }
    return date
}

struct SessionStoreTests {
    @Test
    func createSessionCreatesMetadataAndMessagesFiles() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Test \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        let metadataURL = try LoomPaths.sessionMetadataURL(for: session.id)
        let messagesURL = try LoomPaths.sessionMessagesURL(for: session.id)

        #expect(FileManager.default.fileExists(atPath: metadataURL.path))
        #expect(FileManager.default.fileExists(atPath: messagesURL.path))

        let loaded = try await store.loadMessages(sessionID: session.id)
        #expect(loaded.isEmpty)
    }

    @Test
    func appendAndLoadMessagesPreservesAppendOrder() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Append \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        let user = ChatMessage(
            role: .user,
            content: "Hello",
            createdAt: fixedDate("2026-01-01T00:00:00Z")
        )
        let assistant = ChatMessage(
            role: .assistant,
            content: "Hi there",
            createdAt: fixedDate("2026-01-01T00:00:01Z")
        )

        try await store.appendMessage(user, sessionID: session.id)
        try await store.appendMessage(assistant, sessionID: session.id)

        let loaded = try await store.loadMessages(sessionID: session.id)
        #expect(loaded == [user, assistant])
    }

    @Test
    func firstUserMessageAutoTitlesNewSession() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: Session.Metadata.defaultTitle)
        defer { cleanupSessionFolder(id: session.id) }

        try await store.appendMessage(
            ChatMessage(
                role: .user,
                content: "  Help me plan a two-week budget meal prep.\nInclude a grocery list.  ",
                createdAt: fixedDate("2026-01-01T00:00:00Z")
            ),
            sessionID: session.id
        )

        let metadataURL = try LoomPaths.sessionMetadataURL(for: session.id)
        let metadata = try decodeMetadata(at: metadataURL)
        #expect(metadata.title == "Two-Week Budget Meal Prep")
    }

    @Test
    func firstUserMessageAutoTitlesLegacyNewSessionTitle() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "New Session")
        defer { cleanupSessionFolder(id: session.id) }

        try await store.appendMessage(
            ChatMessage(
                role: .user,
                content: "Help me compare local privacy tools.",
                createdAt: fixedDate("2026-01-01T00:00:00Z")
            ),
            sessionID: session.id
        )

        let metadataURL = try LoomPaths.sessionMetadataURL(for: session.id)
        let metadata = try decodeMetadata(at: metadataURL)
        #expect(metadata.title == "Compare Local Privacy Tools")
    }

    @Test
    func firstUserMessageAutoTitlePullsMainTopic() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: Session.Metadata.defaultTitle)
        defer { cleanupSessionFolder(id: session.id) }

        try await store.appendMessage(
            ChatMessage(
                role: .user,
                content: "Can you plan my weekend trip with a hiking day and food stops?",
                createdAt: fixedDate("2026-01-01T00:00:00Z")
            ),
            sessionID: session.id
        )

        let metadataURL = try LoomPaths.sessionMetadataURL(for: session.id)
        let metadata = try decodeMetadata(at: metadataURL)
        #expect(metadata.title == "Weekend Trip Hiking Day Food Stops")
    }

    @Test
    func firstUserMessageDoesNotOverrideCustomSessionTitle() async throws {
        let store = SessionStore()
        let customTitle = "Project Phoenix"
        let session = try await store.createSession(title: customTitle)
        defer { cleanupSessionFolder(id: session.id) }

        try await store.appendMessage(
            ChatMessage(
                role: .user,
                content: "Tell me how to launch a product.",
                createdAt: fixedDate("2026-01-01T00:00:00Z")
            ),
            sessionID: session.id
        )

        let metadataURL = try LoomPaths.sessionMetadataURL(for: session.id)
        let metadata = try decodeMetadata(at: metadataURL)
        #expect(metadata.title == customTitle)
    }

    @Test
    func loadMessagesSkipsMalformedJSONLLines() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Malformed \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        let first = ChatMessage(
            role: .user,
            content: "First",
            createdAt: fixedDate("2026-01-01T00:00:00Z")
        )
        let second = ChatMessage(
            role: .assistant,
            content: "Second",
            createdAt: fixedDate("2026-01-01T00:00:01Z")
        )

        try await store.appendMessage(first, sessionID: session.id)
        let messagesURL = try LoomPaths.sessionMessagesURL(for: session.id)
        try appendRawJSONLLine("not-json", to: messagesURL)
        try await store.appendMessage(second, sessionID: session.id)

        let loaded = try await store.loadMessages(sessionID: session.id)
        #expect(loaded == [first, second])
    }

    @Test
    func loadRecentMessagesReturnsLatestLimitInOrder() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Recent \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        let messages: [ChatMessage] = [
            ChatMessage(role: .user, content: "One", createdAt: fixedDate("2026-01-01T00:00:00Z")),
            ChatMessage(role: .assistant, content: "Two", createdAt: fixedDate("2026-01-01T00:00:01Z")),
            ChatMessage(role: .user, content: "Three", createdAt: fixedDate("2026-01-01T00:00:02Z")),
            ChatMessage(role: .assistant, content: "Four", createdAt: fixedDate("2026-01-01T00:00:03Z"))
        ]

        for message in messages {
            try await store.appendMessage(message, sessionID: session.id)
        }

        let recent = try await store.loadRecentMessages(sessionID: session.id, limit: 2)
        #expect(recent == Array(messages.suffix(2)))
    }

    @Test
    func loadRecentMessagesReturnsEmptyWhenLimitIsNonPositive() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Recent Limit \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        try await store.appendMessage(
            ChatMessage(role: .user, content: "Hello", createdAt: fixedDate("2026-01-01T00:00:00Z")),
            sessionID: session.id
        )

        let zero = try await store.loadRecentMessages(sessionID: session.id, limit: 0)
        let negative = try await store.loadRecentMessages(sessionID: session.id, limit: -3)

        #expect(zero.isEmpty)
        #expect(negative.isEmpty)
    }

    @Test
    func updateMetadataPersistsTitleChange() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Original \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        var metadata = session.metadata
        let updatedTitle = "Renamed \(UUID().uuidString)"
        metadata.title = updatedTitle

        try await store.updateMetadata(metadata, for: session.id)

        let metadataURL = try LoomPaths.sessionMetadataURL(for: session.id)
        let updated = try decodeMetadata(at: metadataURL)
        #expect(updated.title == updatedTitle)
    }

    @Test
    func chatTemplateLibraryPersistsEditsAndResets() throws {
        let suiteName = "LoomChatTemplateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var templates = ChatTemplateLibrary.load(userDefaults: defaults)
        templates[0].prompt = "Make a practical weekend plan."

        let saved = ChatTemplateLibrary.save(templates, userDefaults: defaults)
        let loaded = ChatTemplateLibrary.load(userDefaults: defaults)
        #expect(saved[0].prompt == "Make a practical weekend plan.")
        #expect(loaded[0].prompt == "Make a practical weekend plan.")

        let reset = ChatTemplateLibrary.reset(userDefaults: defaults)
        #expect(reset == ChatTemplateLibrary.defaultTemplates)
        #expect(ChatTemplateLibrary.load(userDefaults: defaults) == ChatTemplateLibrary.defaultTemplates)
    }

    @Test
    func listSessionsKeepsLegacyMetadataVisibleWithFallbackDefaults() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoomLegacyMetadataTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = SessionStore(sessionsRoot: tempRoot)
        let session = try await store.createSession(title: "Legacy")
        let metadataURL = tempRoot
            .appendingPathComponent(session.id.uuidString, isDirectory: true)
            .appendingPathComponent(LoomPaths.metadataFileName, isDirectory: false)
        let legacyMetadata = """
        {
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-02T00:00:00Z"
        }
        """
        try Data(legacyMetadata.utf8).write(to: metadataURL, options: [.atomic])

        let loaded = try await store.loadSession(id: session.id)
        #expect(loaded?.metadata.title == Session.Metadata.defaultTitle)
        #expect(loaded?.metadata.tags == [])
        #expect(loaded?.metadata.isPinned == false)
        #expect(loaded?.metadata.isArchived == false)
        #expect(loaded?.metadata.collectionName == nil)

        let listed = try await store.listSessions()
        #expect(listed.contains(where: { $0.id == session.id }))
    }

    @Test
    func deleteSessionRemovesSessionFolder() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Delete \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        let modelKey = LoomPreferenceKeys.sessionLastStreamModelKey(for: session.id)
        UserDefaults.standard.set("llama3", forKey: modelKey)

        let folderURL = try LoomPaths.sessionFolder(for: session.id)
        #expect(FileManager.default.fileExists(atPath: folderURL.path))
        #expect(UserDefaults.standard.string(forKey: modelKey) == "llama3")

        try await store.deleteSession(id: session.id)
        #expect(!FileManager.default.fileExists(atPath: folderURL.path))
        #expect(UserDefaults.standard.string(forKey: modelKey) == nil)
    }

    @Test
    func deleteSessionClearsModelKeyWhenFolderIsAlreadyMissing() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "Delete Missing \(UUID().uuidString)")
        defer { cleanupSessionFolder(id: session.id) }

        let modelKey = LoomPreferenceKeys.sessionLastStreamModelKey(for: session.id)
        UserDefaults.standard.set("phi4", forKey: modelKey)

        let folderURL = try LoomPaths.sessionFolder(for: session.id)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.removeItem(at: folderURL)
        }

        try await store.deleteSession(id: session.id)
        #expect(UserDefaults.standard.string(forKey: modelKey) == nil)
    }

    @Test
    func scratchpadPersistsAndLoadsBySession() async throws {
        let store = SessionStore()
        let first = try await store.createSession(title: "Scratch One")
        let second = try await store.createSession(title: "Scratch Two")
        defer {
            cleanupSessionFolder(id: first.id)
            cleanupSessionFolder(id: second.id)
        }

        try await store.saveScratchpad("First session notes", sessionID: first.id)
        try await store.saveScratchpad("Second session notes", sessionID: second.id)

        let loadedFirst = try await store.loadScratchpad(sessionID: first.id)
        let loadedSecond = try await store.loadScratchpad(sessionID: second.id)

        #expect(loadedFirst == "First session notes")
        #expect(loadedSecond == "Second session notes")
    }

    @Test
    func loadScratchpadReturnsEmptyForMissingFile() async throws {
        let store = SessionStore()
        let session = try await store.createSession(title: "No Scratchpad Yet")
        defer { cleanupSessionFolder(id: session.id) }

        let loaded = try await store.loadScratchpad(sessionID: session.id)

        #expect(loaded.isEmpty)
    }

    @Test
    func globalMemoryPersistsRoundTripAndIsBounded() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoomGlobalMemoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = SessionStore(sessionsRoot: tempRoot)

        let memory = SessionMemory(
            preferredUserName: "  Don  ",
            preferredAssistantName: "Loom",
            responseStyle: String(repeating: "brief ", count: 50),
            sessionNote: "Talk through the launch plan.",
            isEnabled: true
        )

        try await store.saveGlobalMemory(memory)
        let loaded = try await store.loadGlobalMemory()

        #expect(loaded.preferredUserName == "Don")
        #expect(loaded.preferredAssistantName == "Loom")
        #expect(loaded.responseStyle.count == SessionMemory.responseStyleLimit)
        #expect(loaded.sessionNote == "Talk through the launch plan.")
        #expect(loaded.isEnabled)
    }

    @Test
    func globalMemoryIsSharedAcrossSessions() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoomGlobalMemoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = SessionStore(sessionsRoot: tempRoot)
        let first = try await store.createSession(title: "Memory One")
        let second = try await store.createSession(title: "Memory Two")
        defer {
            cleanupSessionFolder(id: first.id)
            cleanupSessionFolder(id: second.id)
        }

        try await store.saveGlobalMemory(SessionMemory(preferredUserName: "Don"))

        let loadedFirst = try await store.loadGlobalMemory(fallbackSessionID: first.id)
        let loadedSecond = try await store.loadGlobalMemory(fallbackSessionID: second.id)

        #expect(loadedFirst.preferredUserName == "Don")
        #expect(loadedFirst.isEnabled)
        #expect(loadedSecond.preferredUserName == "Don")
        #expect(loadedSecond.isEnabled)
    }

    @Test
    func loadGlobalMemoryReturnsEmptyForMissingFile() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoomGlobalMemoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = SessionStore(sessionsRoot: tempRoot)

        let loaded = try await store.loadGlobalMemory()

        #expect(loaded == .empty)
        #expect(loaded.contextMessage() == nil)
    }

    @Test
    func globalMemorySurvivesSessionDeletion() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoomGlobalMemoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = SessionStore(sessionsRoot: tempRoot)
        let session = try await store.createSession(title: "Delete Memory")
        defer { cleanupSessionFolder(id: session.id) }

        try await store.saveGlobalMemory(SessionMemory(preferredUserName: "Don"))
        let memoryURL = tempRoot.appendingPathComponent(LoomPaths.memoryFileName, isDirectory: false)
        #expect(FileManager.default.fileExists(atPath: memoryURL.path))

        try await store.deleteSession(id: session.id)

        #expect(FileManager.default.fileExists(atPath: memoryURL.path))
        let loaded = try await store.loadGlobalMemory()
        #expect(loaded.preferredUserName == "Don")
    }

    @Test
    func loadGlobalMemoryMigratesLegacySessionMemoryWhenMissing() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoomGlobalMemoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = SessionStore(sessionsRoot: tempRoot)
        let session = try await store.createSession(title: "Legacy Memory")
        defer { cleanupSessionFolder(id: session.id) }

        try await store.saveSessionMemory(
            SessionMemory(preferredUserName: "Don", responseStyle: "Keep it crisp."),
            sessionID: session.id
        )

        let loaded = try await store.loadGlobalMemory(fallbackSessionID: session.id)
        let globalMemoryURL = tempRoot.appendingPathComponent(LoomPaths.memoryFileName, isDirectory: false)

        #expect(loaded.preferredUserName == "Don")
        #expect(loaded.responseStyle == "Keep it crisp.")
        #expect(FileManager.default.fileExists(atPath: globalMemoryURL.path))
    }
}

struct LoomStatusSnapshotTests {
    @Test
    func readinessIsNotReadyWhenOllamaIsUnavailable() {
        let snapshot = LoomStatusSnapshot(
            ollamaReachable: false,
            installedModelCount: 2,
            activeModelTag: "llama3.2",
            offlineAvailable: false
        )

        #expect(snapshot.readiness == .notReady)
        #expect(snapshot.issues == [.ollamaNotRunning])
    }

    @Test
    func readinessNeedsSetupWhenModelMissing() {
        let snapshot = LoomStatusSnapshot(
            ollamaReachable: true,
            installedModelCount: 1,
            activeModelTag: nil,
            offlineAvailable: false
        )

        #expect(snapshot.readiness == .needsSetup)
        #expect(snapshot.issues == [.noModelSelected])
    }

    @Test
    func readinessIsReadyWhenOllamaAndModelAreAvailable() {
        let snapshot = LoomStatusSnapshot(
            ollamaReachable: true,
            installedModelCount: 2,
            activeModelTag: "llama3.2",
            offlineAvailable: true
        )

        #expect(snapshot.readiness == .ready)
        #expect(snapshot.issues.isEmpty)
    }

    @Test
    func lowDiskWarningShownWhenBelowTenPercent() {
        let snapshot = LoomStatusSnapshot(
            ollamaReachable: true,
            installedModelCount: 1,
            activeModelTag: "llama3.2",
            offlineAvailable: true,
            diskSpace: DiskSpaceSnapshot(totalBytes: 100, availableBytes: 9)
        )

        #expect(snapshot.lowDiskSpaceWarning == DiskSpaceSnapshot.lowSpaceWarningMessage)
    }

    @Test
    func lowDiskWarningHiddenWhenDiskIsHealthy() {
        let snapshot = LoomStatusSnapshot(
            ollamaReachable: true,
            installedModelCount: 1,
            activeModelTag: "llama3.2",
            offlineAvailable: true,
            diskSpace: DiskSpaceSnapshot(totalBytes: 100, availableBytes: 20)
        )

        #expect(snapshot.lowDiskSpaceWarning == nil)
    }
}

struct StringTrimmingTests {
    @Test
    func nonEmptyTrimmedReturnsNilForWhitespaceOnlyValues() {
        #expect("   \n\t".nonEmptyTrimmed == nil)
    }

    @Test
    func nonEmptyTrimmedReturnsTrimmedContent() {
        #expect("  hello  ".nonEmptyTrimmed == "hello")
    }
}

struct VoiceReplyPreferencesTests {
    @Test
    func recommendedVoicesUseCuratedFemaleVoicesOnly() {
        let voices = [
            VoiceReplyVoiceCandidate(identifier: "in-female", name: "Lekha", language: "hi-IN", qualityRank: 1),
            VoiceReplyVoiceCandidate(identifier: "us-female", name: "Samantha", language: "en-US", qualityRank: 1),
            VoiceReplyVoiceCandidate(identifier: "in-male", name: "Rishi", language: "en-IN", qualityRank: 1),
            VoiceReplyVoiceCandidate(identifier: "us-novelty", name: "Bad News", language: "en-US", qualityRank: 1)
        ]

        let recommended = VoiceReplyVoiceCatalog.recommendedCandidates(
            from: voices,
            selectedIdentifier: nil,
            limit: 2
        )

        #expect(recommended.map(\.identifier) == ["in-female", "us-female"])
    }

    @Test
    func defaultVoicePrefersFemaleIndianVoice() {
        let voices = [
            VoiceReplyVoiceCandidate(identifier: "us-female", name: "Samantha", language: "en-US", qualityRank: 1),
            VoiceReplyVoiceCandidate(identifier: "in-female", name: "Lekha", language: "hi-IN", qualityRank: 1)
        ]

        let defaultVoice = VoiceReplyVoiceCatalog.defaultCandidate(
            from: voices,
            selectedIdentifier: nil
        )

        #expect(defaultVoice?.identifier == "in-female")
    }

    @Test
    func defaultVoiceKeepsSelectedFemaleVoiceVisible() {
        let voices = [
            VoiceReplyVoiceCandidate(identifier: "us-female", name: "Samantha", language: "en-US", qualityRank: 1),
            VoiceReplyVoiceCandidate(identifier: "in-female", name: "Lekha", language: "hi-IN", qualityRank: 1)
        ]

        let defaultVoice = VoiceReplyVoiceCatalog.defaultCandidate(
            from: voices,
            selectedIdentifier: "us-female"
        )

        #expect(defaultVoice?.identifier == "us-female")
    }
}

struct ChatDisplayFormatterTests {
    @Test
    func formatAddsParagraphBreaksForShortPlainText() {
        let input = "Loom helps you chat locally. It keeps your data on this Mac. You can choose a model and start quickly."
        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("\n\n"))
        #expect(formatted.contains("Loom helps you chat locally."))
        #expect(formatted.contains("You can choose a model and start quickly."))
    }

    @Test
    func formatNormalizesInlineNumberedLists() {
        let input = "To get started, follow these steps. 1) Open Models. 2) Choose llama3. 3) Send a message."
        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("\n1. Open Models."))
        #expect(formatted.contains("\n2. Choose llama3."))
        #expect(formatted.contains("\n3. Send a message."))
    }

    @Test
    func formatRepairsSentenceSpacingWithoutBreakingTechnicalTokens() {
        let input = "First sentence.Second sentence references v1.2.3 and example.com."
        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("First sentence. Second sentence"))
        #expect(formatted.contains("v1.2.3"))
        #expect(formatted.contains("example.com"))
        #expect(!formatted.contains("example. com"))
        #expect(!formatted.contains("v1. 2. 3"))
    }

    @Test
    func formatImprovesDenseSectionedOutput() {
        let input = """
        Determining which scientific discipline is the most fundamental can be a matter of perspective and often depends on how one defines "fundamental." Each discipline plays a crucial role and contributes to our understanding of the world in unique ways. However, some might argue that physics holds a foundational position due to its focus on the basic laws governing matter, energy, space, and time.Why Physics isConsidered Fundamental:Basic Laws: Physics seeks to understand the fundamental forces that govern the behavior of all matter in the universe.Building Blocks: Many other sciences rely on physics principles.OtherSciences:Chemistry: While chemistry is incredibly important, it builds upon the principles of physics.Conclusion:While all scientific disciplines are essential, physics often stands out as the most fundamental.
        """

        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("Why Physics is Considered Fundamental:"))
        #expect(formatted.contains("Basic Laws:"))
        #expect(formatted.contains("Building Blocks:"))
        #expect(formatted.contains("Other Sciences:"))
        #expect(formatted.contains("\n\nChemistry:"))
        #expect(formatted.contains("Conclusion:\n\nWhile all scientific disciplines are essential"))
        #expect(!formatted.contains("isConsidered"))
        #expect(!formatted.contains("OtherSciences"))
    }

    @Test
    func formatAddsParagraphBreaksForDenseShortReplies() {
        let input = "Loom is local. It stores chats on your Mac. You can stop any reply."
        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("\n\n"))
    }

    @Test
    func markdownSyntaxPreservesLineBreaksForPlainText() {
        let input = "Line one.\nLine two."
        let syntax = ChatDisplayFormatter.markdownSyntax(for: input)

        #expect({
            if case .inlineOnlyPreservingWhitespace = syntax {
                return true
            }
            return false
        }())
    }

    @Test
    func markdownSyntaxStaysWhitespacePreservingForMarkdownLists() {
        let input = "- One\n- Two"
        let syntax = ChatDisplayFormatter.markdownSyntax(for: input)

        #expect({
            if case .inlineOnlyPreservingWhitespace = syntax {
                return true
            }
            return false
        }())
    }

    @Test
    func formatSplitsDenseInlineLabelRunsIntoParagraphs() {
        let input = """
        Physics is a vast and fascinating field that seeks to understand the fundamental laws governing the behavior of the physical universe. It's a subject that has been instrumental in shaping our understanding of the world around us, from the smallest subatomic particles to the entire cosmos.To get started with learning physics, here are some steps you can follow:Understand the basics: Start by learning about the fundamental concepts of physics, such as:Motion: speed, velocity, accelerationEnergy: types (kinetic, potential, thermal), conversionsForces: friction, gravity, normal forceWork and energy transfersMomentum and collisionsBuild a strong foundation in math: Physics relies heavily on mathematical concepts, particularly algebra, geometry, and calculus.Explore different areas of physics: There are many subfields within physics, such as:Mechanics: kinematics, dynamics, energyThermodynamics: heat transfer, temperature, entropyElectromagnetism: electric fields, magnetic fields, electromagnetic wavesQuantum mechanics: wave-particle duality, Schrodinger equationUse online resources: There are many excellent online resources available to learn physics.
        """

        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("\n\nBuild a strong foundation in math:"))
        #expect(formatted.contains("\n\nExplore different areas of physics:"))
        #expect(formatted.contains("\n\nUse online resources:"))
        #expect(!formatted.contains("forceWork"))
        #expect(!formatted.contains("transfersMomentum"))
        #expect(!formatted.contains("equationUse"))
    }

    @Test
    func formatSplitsDenseColonLabelBlocks() {
        let input = """
        Here's a step-by-step guide on how to make delicious French fries at home:Ingredients:2-3 large potatoesEquipment:Large potInstructions:Select and peel the potatoes:Choose starchy potatoes.Cut the potatoes into strips:Soak the potato strips in cold water:Drain and dry the potato strips:Heat the oil:
        """

        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("Ingredients:\n2-3 large potatoes"))
        #expect(formatted.contains("Equipment:\nLarge pot"))
        #expect(formatted.contains("\n\nInstructions:"))
        #expect(formatted.contains("\n\nCut the potatoes into strips:"))
        #expect(formatted.contains("\n\nHeat the oil:"))
    }

    @Test
    func formatSplitsDenseBoldLabelBlocks() {
        let input = """
        Here's a guide:**Ingredients:**2 potatoes**Equipment:**Large pot**Instructions:**Wash potatoes**Cut:**Thin strips**Fry:**Until golden.
        """

        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("\n\n**Ingredients:**\n2 potatoes"))
        #expect(formatted.contains("\n\n**Equipment:**\nLarge pot"))
        #expect(formatted.contains("\n\n**Instructions:**\nWash potatoes"))
    }

    @Test
    func formatFallbackParagraphizesLongMixedMarkdownWhenStillDense() {
        let input = """
        1. prep potatoes. 2. heat oil. this is still one dense block with many steps and no helpful spacing even though a numbered token exists near the start and the response keeps running without clear breaks so it becomes hard to scan. keep frying in batches and season immediately while hot for best texture and flavor.
        """

        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("\n\n"))
    }

    @Test
    func formatAddsSpacingForDenseWeatherStyleLists() {
        let input = """
        Determining the weather forecast involves a combination of observations, computer models, and scientific expertise. Here's an overview of the process:1. Observations: Weather forecasting begins with observing current weather conditions from various sources, including:- Radar: Uses radio waves to detect precipitation and other weather phenomena.- Satellites: Provide images of clouds, storms, and temperature patterns.2. Data Collection: Collected data is fed into computer models to analyze and predict future weather patterns.3. Computer Models: Numerical weather prediction models use complex algorithms to simulate the behavior of the atmosphere.
        """

        let formatted = ChatDisplayFormatter.format(input)

        #expect(formatted.contains("\n\n1. Observations:"))
        #expect(formatted.contains("\n\n- Radar:"))
        #expect(formatted.contains("\n\n- Satellites:"))
        #expect(formatted.contains("\n\n2. Data Collection:"))
        #expect(formatted.contains("\n\n3. Computer Models:"))
        #expect(!formatted.contains("Data\n\nCollection:"))
        #expect(!formatted.contains("Computer\n\nModels:"))
    }

    @Test
    func formatAndSyntaxStayStableAcrossStreamingPrefixes() {
        let partial = """
        Determining the weather forecast involves a combination of observations, computer models, and scientific expertise. Here's an overview of the process:1. Observations: Weather forecasting begins with observing current weather conditions from various sources, including:- Radar: Uses radio waves to detect precipitation and other weather phenomena.- Satellites: Provide images of clouds and storms.
        """
        let full = partial + "2. Data Collection: Collected data is fed into computer models to analyze and predict future weather patterns.3. Computer Models: Numerical weather prediction models use complex algorithms."

        let formattedPartial = ChatDisplayFormatter.format(partial)
        let formattedFull = ChatDisplayFormatter.format(full)
        let partialSyntax = ChatDisplayFormatter.markdownSyntax(for: formattedPartial)
        let fullSyntax = ChatDisplayFormatter.markdownSyntax(for: formattedFull)

        #expect(formattedPartial.contains("\n\n1. Observations:"))
        #expect(formattedPartial.contains("\n\n- Radar:"))
        #expect(formattedFull.contains("\n\n2. Data Collection:"))
        #expect(formattedFull.contains("\n\n3. Computer Models:"))
        #expect({
            if case .inlineOnlyPreservingWhitespace = partialSyntax {
                return true
            }
            return false
        }())
        #expect({
            if case .inlineOnlyPreservingWhitespace = fullSyntax {
                return true
            }
            return false
        }())
    }
}

struct ChatMarkdownBlockParserTests {
    @Test
    func parseSplitsCodeFenceBlocksFromMarkdownText() {
        let input = """
        Before code.

        ```swift
        let greeting = "Hello"
        print(greeting)
        ```

        After code.
        """

        let blocks = ChatMarkdownBlockParser.parse(input)

        #expect(blocks.count == 3)
        #expect({
            if case .markdown(let markdown) = blocks[0] {
                return markdown.contains("Before code.")
            }
            return false
        }())
        #expect({
            if case .code(let language, let code) = blocks[1] {
                return language == "swift"
                    && code.contains("let greeting = \"Hello\"")
                    && code.contains("print(greeting)")
            }
            return false
        }())
        #expect({
            if case .markdown(let markdown) = blocks[2] {
                return markdown.contains("After code.")
            }
            return false
        }())
    }

    @Test
    func parseExtractsMarkdownTableBlock() {
        let input = """
        Before table
        | Name | Score |
        | --- | ---: |
        | Ada | 98 |
        | Ben | 91 |
        After table
        """

        let blocks = ChatMarkdownBlockParser.parse(input)

        #expect(blocks.count == 3)
        #expect({
            if case .table(let tableText) = blocks[1] {
                return tableText.contains("| Name | Score |")
                    && tableText.contains("| Ada | 98 |")
                    && tableText.contains("| Ben | 91 |")
            }
            return false
        }())
    }

    @Test
    func parseKeepsPipeOnlyTextAsMarkdownWhenNoTableSeparatorExists() {
        let input = """
        This line has a | pipe but is not a table.
        Another normal line.
        """

        let blocks = ChatMarkdownBlockParser.parse(input)

        #expect(blocks.count == 1)
        #expect({
            if case .markdown(let markdown) = blocks[0] {
                return markdown.contains("a | pipe")
            }
            return false
        }())
    }
}

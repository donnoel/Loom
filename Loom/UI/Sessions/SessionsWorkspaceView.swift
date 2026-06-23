import SwiftUI
import AppKit
import AVFoundation
import Speech
import UniformTypeIdentifiers
import NaturalLanguage

struct SessionDetailView: View {
    private static let attachmentTypes: [UTType] = [
        .plainText,
        .utf8PlainText,
        .pdf,
        .commaSeparatedText,
        .json,
        .xml,
        .sourceCode
    ]
    private static let starterPrompts: [String] = [
        "Help me plan a simple dinner for tonight.",
        "Write a friendly follow-up email.",
        "Explain this in plain language.",
        "Create a short to-do list for my day."
    ]

    let session: Session
    let store: SessionStore
    let initialScrollMessageID: ChatMessage.ID?
    let browseModels: () -> Void
    let openOrInstallOllama: () -> Void
    let onActivity: () async -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var vm: SessionMessagesViewModel
    @State private var didInitialScroll: Bool = false
    @State private var isBottomMarkerVisible: Bool = true
    @State private var scrollViewportFrame: CGRect = .null
    @State private var bottomMarkerFrame: CGRect = .null
    @State private var isShowingFileImporter: Bool = false
    @State private var isDictating: Bool = false
    @State private var isShowingScratchpad: Bool = false
    @State private var isShowingSessionMemory: Bool = false
    @FocusState private var isDraftFieldFocused: Bool
    @AppStorage(LoomPreferenceKeys.voiceReplyVoiceIdentifier)
    private var voiceReplyVoiceIdentifier: String = ""
    @State private var lastSpokenAssistantMessageID: UUID?
    @State private var speechInputController = SpeechInputController()
    @State private var speechSynthesizer = AVSpeechSynthesizer()

    init(
        session: Session,
        store: SessionStore,
        initialScrollMessageID: ChatMessage.ID? = nil,
        browseModels: @escaping () -> Void,
        openOrInstallOllama: @escaping () -> Void,
        onActivity: @escaping () async -> Void
    ) {
        self.session = session
        self.store = store
        self.initialScrollMessageID = initialScrollMessageID
        self.browseModels = browseModels
        self.openOrInstallOllama = openOrInstallOllama
        self.onActivity = onActivity
        _vm = State(initialValue: SessionMessagesViewModel(
            store: store,
            sessionID: session.id,
            onActivity: onActivity
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let banner = vm.banner {
                SessionInlineBanner(banner: banner) { action in
                    switch action {
                    case .browseModels:
                        browseModels()
                    case .openOrInstallOllama:
                        openOrInstallOllama()
                    case .retryLastReply:
                        Task { await vm.retryLastReply() }
                    }
                }
                .padding(.horizontal, 24)
            }

            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if !vm.isShowingFullHistory && vm.messages.count >= 200 {
                                Button("Load Earlier") {
                                    loadEarlierAndPreservePosition(proxy)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .padding(.bottom, 4)
                            }

                            if vm.messages.isEmpty {
                                welcomeEmptyState
                            } else {
                                ForEach(vm.messages, id: \.id) { message in
                                    MessageRowView(
                                        message: message,
                                        isThinking: vm.isGenerating
                                            && vm.generatingMessageID == message.id
                                            && message.content.isEmpty,
                                        onRegenerate: message.role == .assistant ? {
                                            Task { await vm.retryLastReply() }
                                        } : nil,
                                        onQuickTransform: message.role == .assistant ? { transform in
                                            Task {
                                                await vm.runAssistantQuickTransform(
                                                    from: message.id,
                                                    transform: transform
                                                )
                                            }
                                        } : nil
                                    )
                                    .equatable()
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: SessionBottomMarkerFramePreferenceKey.self,
                                            value: geometry.frame(in: .global)
                                        )
                                    }
                                )
                                .onPreferenceChange(SessionBottomMarkerFramePreferenceKey.self) { frame in
                                    bottomMarkerFrame = frame
                                    refreshJumpToBottomVisibility()
                                }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .animation(.easeOut(duration: 0.22), value: vm.messages.map(\.id))
                    }
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: SessionScrollViewportFramePreferenceKey.self,
                                value: geometry.frame(in: .global)
                            )
                        }
                    )
                    .onPreferenceChange(SessionScrollViewportFramePreferenceKey.self) { frame in
                        scrollViewportFrame = frame
                        refreshJumpToBottomVisibility()
                    }
                    .task {
                        await vm.load()
                        if !didInitialScroll {
                            didInitialScroll = true
                            DispatchQueue.main.async {
                                if let initialScrollMessageID,
                                   vm.messages.contains(where: { $0.id == initialScrollMessageID }) {
                                    proxy.scrollTo(initialScrollMessageID, anchor: .center)
                                } else {
                                    scrollToBottom(proxy)
                                }
                            }
                        }
                    }
                    .onChange(of: initialScrollMessageID) { _, newValue in
                        guard let newValue,
                              vm.messages.contains(where: { $0.id == newValue }) else {
                            return
                        }

                        DispatchQueue.main.async {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }

                    if !isBottomMarkerVisible && !vm.messages.isEmpty {
                        Button {
                            scrollToBottom(proxy)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(.thickMaterial, in: Circle())
                                .overlay(
                                    Circle().stroke(Color.primary.opacity(0.14), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
                        .padding(.bottom, 10)
                        .accessibilityIdentifier("session.detail.jumpToBottom")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    if !vm.pendingAttachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(vm.pendingAttachments) { attachment in
                                    HStack(spacing: 6) {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(attachment.fileName)
                                                .font(LoomTheme.Typography.captionStrong)
                                                .lineLimit(1)
                                            Text(attachment.characterCountLabel)
                                                .font(LoomTheme.Typography.captionTiny)
                                                .foregroundStyle(.secondary)
                                        }
                                        Button {
                                            vm.removeAttachment(id: attachment.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                                    )
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    TextField(
                        "",
                        text: $vm.draft,
                        prompt: Text("Ask anything")
                            .foregroundStyle(LoomTheme.inputPlaceholder(colorScheme)),
                        axis: .vertical
                    )
                        .autocorrectionDisabled(false)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2...8)
                        .foregroundStyle(LoomTheme.textPrimary(colorScheme))
                        .focused($isDraftFieldFocused)
                        .accessibilityIdentifier("session.detail.messageField")
                        .onSubmit {
                            guard !vm.isGenerating else { return }
                            sendAndScroll(proxy)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 4) {
                            composerUtilityButton(
                                symbolName: "paperclip",
                                helpText: vm.activeModelSupportsFileUploads ? "Attach files" : "Current model does not support file uploads",
                                isActive: !vm.pendingAttachments.isEmpty,
                                isDisabled: vm.isGenerating || !vm.activeModelSupportsFileUploads
                            ) {
                                isShowingFileImporter = true
                            }

                            composerUtilityButton(
                                symbolName: isDictating ? "waveform.circle.fill" : "mic",
                                helpText: vm.activeModelSupportsSpeechInput ? "Dictate message" : "Current model does not support speech input",
                                isActive: isDictating,
                                isDisabled: vm.isGenerating || !vm.activeModelSupportsSpeechInput
                            ) {
                                toggleDictation()
                            }

                            voiceReplyMenu
                        }

                        Menu {
                            if vm.availableModelTags.isEmpty {
                                Button("No installed models") {}
                                    .disabled(true)
                            } else {
                                Section("Model") {
                                    ForEach(vm.availableModelTags, id: \.self) { tag in
                                        Button {
                                            vm.selectActiveModel(tag: tag)
                                        } label: {
                                            if vm.activeModelTag == tag {
                                                Label(vm.modelDisplayName(for: tag), systemImage: "checkmark")
                                            } else {
                                                Text(vm.modelDisplayName(for: tag))
                                            }
                                        }
                                    }
                                }
                            }

                            Divider()

                            Button("Refresh Models") {
                                Task { await vm.refreshInstalledModels() }
                            }
                            Button("Browse Models…") {
                                browseModels()
                            }

                            Section("History") {
                                ForEach(SessionMessagesViewModel.HistoryContextLevel.allCases) { level in
                                    Button {
                                        vm.historyContextLevel = level
                                    } label: {
                                        if vm.historyContextLevel == level {
                                            Label(level.title, systemImage: "checkmark")
                                        } else {
                                            Text(level.title)
                                        }
                                    }
                                }
                            }

                            Section("Files") {
                                ForEach(SessionMessagesViewModel.FileContextLevel.allCases) { level in
                                    Button {
                                        vm.fileContextLevel = level
                                    } label: {
                                        if vm.fileContextLevel == level {
                                            Label(level.title, systemImage: "checkmark")
                                        } else {
                                            Text(level.title)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(LoomTheme.Typography.captionTinyStrong)
                                Text("Models")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: "chevron.down")
                                    .font(LoomTheme.Typography.captionTinyStrong)
                            }
                            .font(LoomTheme.Typography.bodyStrong)
                            .foregroundStyle(LoomTheme.textPrimary(colorScheme))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .frame(minHeight: 30)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(LoomTheme.surfaceBorder(colorScheme).opacity(0.55), lineWidth: 0.75)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("session.detail.modelPicker")
                        .accessibilityLabel("Model and tools")

                        Spacer(minLength: 4)

                        if vm.isGenerating {
                            Button(role: .destructive) {
                                vm.stopGenerating()
                                stopDictationIfNeeded()
                            } label: {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(Color.red.opacity(colorScheme == .dark ? 0.84 : 0.92))
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(2)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("session.detail.stopButton")
                            .accessibilityLabel("Stop")
                        } else {
                            Button {
                                sendAndScroll(proxy)
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(draftIsEmpty ? Color.secondary.opacity(0.65) : .white)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(
                                                draftIsEmpty
                                                    ? AnyShapeStyle(Color.secondary.opacity(colorScheme == .dark ? 0.22 : 0.20))
                                                    : AnyShapeStyle(LoomTheme.accentGradient(for: colorScheme))
                                            )
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08), lineWidth: draftIsEmpty ? 0.8 : 0)
                                    )
                            }
                            .accessibilityIdentifier("session.detail.sendButton")
                            .accessibilityLabel("Send")
                            .buttonStyle(.plain)
                            .disabled(draftIsEmpty)
                            .padding(2)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(minHeight: 38)

                    if !vm.pendingAttachments.isEmpty && vm.fileContextLevel == .off {
                        Text("Attached files are off for this send. Enable file context in Tools.")
                            .font(LoomTheme.Typography.captionTiny)
                            .foregroundStyle(LoomTheme.textSecondary(colorScheme))
                            .padding(.horizontal, 6)
                            .accessibilityIdentifier("session.detail.fileContextHint")
                    }
                }
                .padding(.top, 6)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(minHeight: 96)
                .frame(maxWidth: .infinity)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                    shape
                        .fill(colorScheme == .dark ? Color(red: 0.13, green: 0.13, blue: 0.14) : Color.white.opacity(0.98))
                        .overlay {
                            shape.strokeBorder(LoomTheme.surfaceBorder(colorScheme).opacity(0.52), lineWidth: 1)
                        }
                }
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.09 : 0.04), radius: 2, x: 0, y: 1)
                .padding(.top, 10)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: Self.attachmentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await vm.importAttachments(from: urls) }
            case .failure:
                vm.banner = SessionMessagesViewModel.BannerState(
                    text: "Loom couldn’t open those files. Try again.",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
        .onChange(of: vm.isGenerating) { _, isGenerating in
            if !isGenerating {
                speakLatestAssistantReplyIfNeeded()
            }
        }
        .onChange(of: vm.activeModelSupportsSpeechOutput) { _, supportsSpeechOutput in
            if !supportsSpeechOutput && vm.isVoiceReplyEnabled {
                vm.isVoiceReplyEnabled = false
            }
        }
        .onDisappear {
            stopDictationIfNeeded()
            speechSynthesizer.stopSpeaking(at: .immediate)
            vm.stopGenerating()
            Task {
                await vm.flushScratchpad()
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingSessionMemory = true
                } label: {
                    Label("Session Memory", systemImage: "person.text.rectangle")
                }
                .help("Edit session memory")
                .accessibilityIdentifier("session.detail.sessionMemory")
            }

            ToolbarItem {
                Button {
                    isShowingScratchpad.toggle()
                } label: {
                    Label("Scratchpad", systemImage: "note.text")
                }
                .help("Toggle scratchpad")
                .accessibilityIdentifier("session.detail.scratchpadToggle")
            }
        }
        .inspector(isPresented: $isShowingScratchpad) {
            scratchpadSidebar
        }
        .sheet(isPresented: $isShowingSessionMemory) {
            SessionMemorySheet(memory: vm.sessionMemory) { memory in
                await vm.saveSessionMemory(memory)
            }
        }
    }

    private var scratchpadSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scratchpad")
                .font(LoomTheme.Typography.bodyStrong)
                .foregroundStyle(.primary)

            scratchpadSection
        }
        .padding(16)
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
    }

    private var scratchpadSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if vm.scratchpadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Capture quick notes, conclusions, or takeaways for this session.")
                        .font(LoomTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }

                TextEditor(
                    text: Binding(
                        get: { vm.scratchpadText },
                        set: { vm.updateScratchpadText($0) }
                    )
                )
                .font(LoomTheme.Typography.caption)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
                .accessibilityIdentifier("session.detail.scratchpad")
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
    }

    private var draftIsEmpty: Bool {
        vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func composerUtilityButton(
        symbolName: String,
        helpText: String,
        isActive: Bool = false,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        ComposerUtilityIconButton(
            symbolName: symbolName,
            helpText: helpText,
            isActive: isActive,
            isDisabled: isDisabled,
            action: action
        )
    }

    private var voiceReplyMenu: some View {
        Menu {
            Button {
                vm.isVoiceReplyEnabled.toggle()
                if !vm.isVoiceReplyEnabled {
                    speechSynthesizer.stopSpeaking(at: .immediate)
                }
            } label: {
                Label(
                    vm.isVoiceReplyEnabled ? "Turn Voice Replies Off" : "Turn Voice Replies On",
                    systemImage: vm.isVoiceReplyEnabled ? "speaker.slash" : "speaker.wave.2"
                )
            }

            Button {
                speechSynthesizer.stopSpeaking(at: .immediate)
            } label: {
                Label("Stop Reading", systemImage: "stop.circle")
            }
            .disabled(!speechSynthesizer.isSpeaking)

            Divider()

            Section("Voice") {
                ForEach(recommendedVoiceReplyVoices, id: \.identifier) { voice in
                    Button {
                        selectVoiceReplyVoice(voice.identifier)
                    } label: {
                        voiceMenuLabel(
                            title: voiceReplyDisplayName(for: voice),
                            isSelected: selectedVoiceReplyIdentifier == voice.identifier
                        )
                    }
                }
            }
        } label: {
            ComposerUtilityIconChrome(
                symbolName: vm.isVoiceReplyEnabled ? "speaker.wave.2.fill" : "speaker.wave.2",
                isActive: vm.isVoiceReplyEnabled,
                isDisabled: !vm.activeModelSupportsSpeechOutput
            )
        }
        .help(vm.activeModelSupportsSpeechOutput ? "Voice replies" : "Current model does not support speech output")
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(!vm.activeModelSupportsSpeechOutput)
        .padding(2)
        .contentShape(Rectangle())
        .accessibilityIdentifier("session.detail.voiceRepliesMenu")
        .accessibilityLabel(vm.isVoiceReplyEnabled ? "Voice replies on" : "Voice replies off")
    }

    private var recommendedVoiceReplyVoices: [AVSpeechSynthesisVoice] {
        VoiceReplyVoiceCatalog.recommendedVoices(
            from: AVSpeechSynthesisVoice.speechVoices(),
            selectedIdentifier: voiceReplyVoiceIdentifier.nonEmptyTrimmed
        )
    }

    private var selectedVoiceReplyIdentifier: String? {
        VoiceReplyVoiceCatalog.defaultVoice(
            from: AVSpeechSynthesisVoice.speechVoices(),
            selectedIdentifier: voiceReplyVoiceIdentifier.nonEmptyTrimmed
        )?.identifier
    }

    @ViewBuilder
    private func voiceMenuLabel(title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func selectVoiceReplyVoice(_ identifier: String) {
        voiceReplyVoiceIdentifier = identifier
        vm.isVoiceReplyEnabled = true
    }

    private func voiceReplyDisplayName(for voice: AVSpeechSynthesisVoice) -> String {
        let languageName = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        return "\(voice.name) (\(languageName))"
    }

    private func sendAndScroll(_ proxy: ScrollViewProxy) {
        Task {
            await vm.sendDraft()
            DispatchQueue.main.async {
                scrollToBottom(proxy)
            }
        }
    }

    private func loadEarlierAndPreservePosition(_ proxy: ScrollViewProxy) {
        let anchorID = vm.messages.first?.id

        Task {
            await vm.loadFullHistory()

            DispatchQueue.main.async {
                if let anchorID {
                    proxy.scrollTo(anchorID, anchor: .top)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        setBottomMarkerVisibility(true)
        if let last = vm.messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func setBottomMarkerVisibility(_ isVisible: Bool) {
        guard isBottomMarkerVisible != isVisible else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            isBottomMarkerVisible = isVisible
        }
    }

    private func refreshJumpToBottomVisibility() {
        guard !vm.messages.isEmpty else {
            setBottomMarkerVisibility(true)
            return
        }

        guard !scrollViewportFrame.isNull, !bottomMarkerFrame.isNull else {
            setBottomMarkerVisibility(false)
            return
        }

        let overlap = scrollViewportFrame.intersection(bottomMarkerFrame)
        let isBottomVisible = !overlap.isNull && overlap.height > 0
        setBottomMarkerVisibility(isBottomVisible)
    }

    private func toggleDictation() {
        if isDictating {
            stopDictationIfNeeded()
            return
        }

        Task {
            let started = await speechInputController.start(
                initialDraft: vm.draft,
                onTranscript: { transcript in
                    vm.draft = transcript
                },
                onStateChange: { isRecording in
                    isDictating = isRecording
                },
                onError: { message in
                    vm.banner = SessionMessagesViewModel.BannerState(
                        text: message,
                        actionTitle: nil,
                        action: nil
                    )
                }
            )

            if !started {
                isDictating = false
            }
        }
    }

    private func stopDictationIfNeeded() {
        speechInputController.stop()
        isDictating = false
    }

    private func speakLatestAssistantReplyIfNeeded() {
        guard vm.isVoiceReplyEnabled else { return }
        guard vm.activeModelSupportsSpeechOutput else { return }

        guard let latestAssistant = vm.messages.last(where: { message in
            message.role == .assistant && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return }

        guard latestAssistant.id != lastSpokenAssistantMessageID else { return }
        lastSpokenAssistantMessageID = latestAssistant.id

        let utterance = AVSpeechUtterance(string: latestAssistant.content)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if let configuredIdentifier = voiceReplyVoiceIdentifier.nonEmptyTrimmed,
           let configuredVoice = AVSpeechSynthesisVoice(identifier: configuredIdentifier),
           VoiceReplyVoiceCatalog.isSupportedVoice(configuredVoice) {
            utterance.voice = configuredVoice
        } else {
            utterance.voice = VoiceReplyVoiceCatalog.defaultVoice(
                from: AVSpeechSynthesisVoice.speechVoices(),
                selectedIdentifier: nil
            )
        }

        speechSynthesizer.stopSpeaking(at: .immediate)
        speechSynthesizer.speak(utterance)
    }

    private var welcomeEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to your new session")
                        .font(LoomTheme.Typography.sectionTitle)
                    Text("Ask Loom anything in everyday language. You can also attach files or use your mic.")
                        .font(LoomTheme.Typography.body)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Try one of these:")
                .font(LoomTheme.Typography.captionStrong)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.starterPrompts, id: \.self) { prompt in
                        StarterPromptChip(prompt: prompt) {
                            applyStarterPrompt(prompt)
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            Text("AI can make mistakes. Check important info.")
                .font(LoomTheme.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .loomCard(cornerRadius: 12)
        .padding(.vertical, 6)
    }

    private func applyStarterPrompt(_ prompt: String) {
        vm.draft = prompt
        isDraftFieldFocused = true
    }
}

@MainActor
private final class SpeechInputController {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var draftPrefix: String = ""

    func start(
        initialDraft: String,
        onTranscript: @escaping (String) -> Void,
        onStateChange: @escaping (Bool) -> Void,
        onError: @escaping (String) -> Void
    ) async -> Bool {
        stop()

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) else {
            onError("Speech recognition isn’t available on this Mac.")
            return false
        }

        guard recognizer.isAvailable else {
            onError("Speech recognition isn’t available right now. Try again in a moment.")
            return false
        }

        let speechAuthorized = await requestSpeechAuthorization()
        guard speechAuthorized else {
            onError("Enable Speech Recognition in System Settings to use dictation.")
            return false
        }

        let microphoneAuthorized = await requestMicrophoneAuthorization()
        guard microphoneAuthorized else {
            onError("Enable microphone access in System Settings to use dictation.")
            return false
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        draftPrefix = initialDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            stop()
            onError("Loom couldn’t start the microphone. Try again.")
            return false
        }

        onStateChange(true)
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    let mergedDraft = merge(prefix: self.draftPrefix, transcript: transcript)
                    onTranscript(mergedDraft)

                    if result.isFinal {
                        self.stop()
                        onStateChange(false)
                    }
                }

                if error != nil {
                    self.stop()
                    onStateChange(false)
                    onError("Loom couldn’t transcribe audio right now. Try again.")
                }
            }
        }

        return true
    }

    func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func merge(prefix: String, transcript: String) -> String {
        if prefix.isEmpty {
            return transcript
        }
        if transcript.isEmpty {
            return prefix
        }
        return "\(prefix) \(transcript)"
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

private struct MessageRowView: View, Equatable {
    let message: ChatMessage
    let isThinking: Bool
    let onRegenerate: (() -> Void)?
    let onQuickTransform: ((SessionMessagesViewModel.AssistantQuickTransform) -> Void)?

    static func == (lhs: MessageRowView, rhs: MessageRowView) -> Bool {
        lhs.message == rhs.message && lhs.isThinking == rhs.isThinking
    }

    var body: some View {
        let isUser = message.role == .user

        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            MessageBubbleChrome(role: message.role) {
                if isThinking {
                    TypingPulseView()
                } else {
                    MessageContentView(
                        content: message.content,
                        role: message.role,
                        onRegenerate: onRegenerate,
                        onQuickTransform: onQuickTransform
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(roleLabel): \(accessibilityMessageText)")
            .accessibilityIdentifier(accessibilityIdentifier)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.vertical, 3)
    }

    private var roleLabel: String {
        switch message.role {
        case .assistant:
            return "Loom"
        case .user:
            return "You"
        case .system:
            return "System"
        case .tool:
            return "Tool"
        }
    }

    private var accessibilityMessageText: String {
        if isThinking {
            return "Thinking"
        }

        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Empty message" : trimmed
    }

    private var accessibilityIdentifier: String {
        switch message.role {
        case .assistant:
            return isThinking ? "session.message.assistant.typing" : "session.message.assistant.bubble"
        case .user:
            return "session.message.user.bubble"
        case .system:
            return "session.message.system.bubble"
        case .tool:
            return "session.message.tool.bubble"
        }
    }
}

private struct StarterPromptChip: View {
    let prompt: String
    let onTap: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            Text(prompt)
                .font(LoomTheme.Typography.caption)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(isHovered ? 0.16 : 0.10))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.primary.opacity(isHovered ? 0.18 : 0.10), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct ComposerUtilityIconButton: View {
    let symbolName: String
    let helpText: String
    let isActive: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ComposerUtilityIconChrome(
                symbolName: symbolName,
                isActive: isActive,
                isDisabled: isDisabled
            )
        }
        .help(helpText)
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .padding(2)
        .contentShape(Rectangle())
    }
}

private struct ComposerUtilityIconChrome: View {
    @Environment(\.colorScheme) private var colorScheme

    let symbolName: String
    let isActive: Bool
    let isDisabled: Bool

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(
                isDisabled
                    ? LoomTheme.textMuted(colorScheme)
                    : (isActive ? Color.accentColor : LoomTheme.textPrimary(colorScheme).opacity(0.88))
            )
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(
                        isActive
                            ? (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10))
                            : (colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.04))
                    )
            )
    }
}

private struct SessionBottomMarkerFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct SessionScrollViewportFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct TypingPulseView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.20)) { context in
            let activeIndex = Int(context.date.timeIntervalSinceReferenceDate / 0.20) % 3

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.secondary.opacity(index == activeIndex ? 0.92 : 0.34))
                            .frame(width: 6.5, height: 6.5)
                            .scaleEffect(index == activeIndex ? 1.22 : 0.84)
                    }
                }

                Text("Thinking")
                    .foregroundStyle(.secondary)
            }
            .animation(.easeInOut(duration: 0.16), value: activeIndex)
            .padding(.vertical, 2)
            .accessibilityIdentifier("session.message.assistant.typingPulse")
        }
    }
}

private struct MessageContentView: View {
    let content: String
    let role: ChatMessage.Role
    let onRegenerate: (() -> Void)?
    let onQuickTransform: ((SessionMessagesViewModel.AssistantQuickTransform) -> Void)?

    var body: some View {
        let displayContent = ChatDisplayFormatter.format(content)
        let blocks = ChatMarkdownBlockParser.parse(displayContent)

        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { item in
                switch item.element {
                case .markdown(let markdown):
                    MarkdownTextBlockView(markdown: markdown)
                case .code(let language, let code):
                    MarkdownCodeBlockView(language: language, code: code)
                case .table(let table):
                    MarkdownTableBlockView(tableText: table)
                }
            }
        }
        .textSelection(.enabled)
        .contextMenu {
            Button("Copy as Plain Text") {
                copyPlainTextToPasteboard(displayContent)
            }

            Button("Copy as Markdown") {
                copyTextToPasteboard(displayContent)
            }

            if role == .assistant,
               let onRegenerate,
               let onQuickTransform {
                Divider()
                Button("Summarize") {
                    onQuickTransform(.summarize)
                }
                Button("Simplify") {
                    onQuickTransform(.simplify)
                }
                Button("Rewrite in Professional Tone") {
                    onQuickTransform(.professional)
                }
                Button("Turn into Checklist") {
                    onQuickTransform(.checklist)
                }

                Divider()
                Button("Regenerate", action: onRegenerate)
            }
        }
    }
}

@MainActor
private func copyTextToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

@MainActor
private func copyPlainTextToPasteboard(_ text: String) {
    if let attributed = try? AttributedString(
        markdown: text,
        options: AttributedString.MarkdownParsingOptions(
            interpretedSyntax: ChatDisplayFormatter.markdownSyntax(for: text)
        )
    ) {
        copyTextToPasteboard(String(attributed.characters))
        return
    }

    copyTextToPasteboard(text)
}

private struct MarkdownTextBlockView: View {
    let markdown: String

    var body: some View {
        let segments = ChatRichTextSegmentParser.parse(markdown)

        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { item in
                switch item.element {
                case .markdown(let text):
                    MarkdownInlineFragmentView(markdown: text)
                case .heading(let level, let text):
                    ChatSectionHeadingView(level: level, text: text)
                case .divider:
                    ChatSectionDividerView()
                }
            }
        }
    }
}

private struct MarkdownInlineFragmentView: View {
    let markdown: String

    var body: some View {
        let syntax = ChatDisplayFormatter.markdownSyntax(for: markdown)

        Group {
            if let attributed = try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: syntax)
            ) {
                Text(attributed)
            } else {
                Text(markdown)
            }
        }
        .font(LoomTheme.Typography.chatBubbleBody)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ChatSectionHeadingView: View {
    @Environment(\.colorScheme) private var colorScheme

    let level: Int
    let text: String

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foreground)
            .padding(.top, topPadding)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var font: Font {
        switch min(max(level, 1), 4) {
        case 1:
            return .title3.weight(.semibold)
        case 2:
            return .headline.weight(.semibold)
        default:
            return .subheadline.weight(.semibold)
        }
    }

    private var foreground: Color {
        level <= 2
            ? LoomTheme.textPrimary(colorScheme)
            : LoomTheme.textPrimary(colorScheme).opacity(0.92)
    }

    private var topPadding: CGFloat {
        level <= 2 ? 6 : 2
    }
}

private struct ChatSectionDividerView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(LoomTheme.textMuted(colorScheme).opacity(colorScheme == .dark ? 0.28 : 0.18))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .padding(.vertical, 6)
            .accessibilityHidden(true)
    }
}

private struct MarkdownCodeBlockView: View {
    @Environment(\.colorScheme) private var colorScheme

    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(languageLabel)
                    .font(LoomTheme.Typography.captionStrong)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    copyTextToPasteboard(code)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(LoomTheme.Typography.captionStrong)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("session.message.code.copy")
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(codeBackgroundColor)
            )
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(codeContainerFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 1)
        )
    }

    private var languageLabel: String {
        language?.nonEmptyTrimmed ?? "Code"
    }

    private var codeContainerFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02)
    }

    private var codeBackgroundColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.30) : Color.black.opacity(0.06)
    }
}

private struct MarkdownTableBlockView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tableText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Table")
                    .font(LoomTheme.Typography.captionStrong)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    copyTextToPasteboard(tableText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(LoomTheme.Typography.captionStrong)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("session.message.table.copy")
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(tableText)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tableBackgroundColor)
            )
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tableContainerFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 1)
        )
    }

    private var tableContainerFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02)
    }

    private var tableBackgroundColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.24) : Color.black.opacity(0.05)
    }
}

nonisolated enum ChatRichTextSegmentParser {
    enum Segment: Equatable {
        case markdown(String)
        case heading(level: Int, text: String)
        case divider
    }

    private static let headingRegex = makeRegex("(?m)^\\s{0,3}(#{1,6})\\s+(.+?)\\s*$")
    private static let dividerRegex = makeRegex("(?m)^\\s{0,3}(?:---+|\\*\\*\\*+|___+)\\s*$")

    static func parse(_ markdown: String) -> [Segment] {
        let lines = markdown.components(separatedBy: "\n")
        var segments: [Segment] = []
        var markdownBuffer: [String] = []

        func flushMarkdownBuffer() {
            guard !markdownBuffer.isEmpty else { return }
            let text = markdownBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            markdownBuffer.removeAll(keepingCapacity: true)
            guard !text.isEmpty else { return }
            segments.append(.markdown(text))
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                markdownBuffer.append("")
                continue
            }

            if dividerRegex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                flushMarkdownBuffer()
                if segments.last != .divider {
                    segments.append(.divider)
                }
                continue
            }

            let range = NSRange(rawLine.startIndex..., in: rawLine)
            if let match = headingRegex.firstMatch(in: rawLine, options: [], range: range),
               let hashesRange = Range(match.range(at: 1), in: rawLine),
               let textRange = Range(match.range(at: 2), in: rawLine) {
                flushMarkdownBuffer()
                let level = rawLine[hashesRange].count
                let headingText = rawLine[textRange].trimmingCharacters(in: .whitespacesAndNewlines)
                if !headingText.isEmpty {
                    segments.append(.heading(level: level, text: headingText))
                }
                continue
            }

            markdownBuffer.append(rawLine)
        }

        flushMarkdownBuffer()
        return segments.isEmpty ? [.markdown(markdown)] : segments
    }

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }
}

nonisolated enum ChatMarkdownBlockParser {
    nonisolated enum Block: Equatable, Sendable {
        case markdown(String)
        case code(language: String?, code: String)
        case table(String)
    }

    private static let codeFence = "```"
    private static let tableSeparatorRegex = makeRegex("^\\s*\\|?(?:\\s*:?-{3,}:?\\s*\\|)+\\s*:?-{3,}:?\\s*\\|?\\s*$")

    static func parse(_ text: String) -> [Block] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.isEmpty else { return [.markdown("")] }

        let lines = normalized.components(separatedBy: "\n")
        var blocks: [Block] = []
        var markdownLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var isInsideCodeBlock = false

        func flushMarkdownLines() {
            guard !markdownLines.isEmpty else { return }
            let markdown = markdownLines.joined(separator: "\n")
            markdownLines.removeAll(keepingCapacity: true)
            appendMarkdown(markdown, into: &blocks)
        }

        func flushCodeLines() {
            blocks.append(.code(language: codeLanguage?.nonEmptyTrimmed, code: codeLines.joined(separator: "\n")))
            codeLines.removeAll(keepingCapacity: true)
            codeLanguage = nil
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(codeFence) {
                if isInsideCodeBlock {
                    flushCodeLines()
                } else {
                    flushMarkdownLines()
                    let language = String(trimmed.dropFirst(codeFence.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    codeLanguage = language.nonEmptyTrimmed
                }
                isInsideCodeBlock.toggle()
                continue
            }

            if isInsideCodeBlock {
                codeLines.append(line)
            } else {
                markdownLines.append(line)
            }
        }

        if isInsideCodeBlock {
            var openingFence = codeFence
            if let codeLanguage, !codeLanguage.isEmpty {
                openingFence += codeLanguage
            }
            markdownLines.append(openingFence)
            markdownLines.append(contentsOf: codeLines)
        } else if !codeLines.isEmpty {
            flushCodeLines()
        }

        flushMarkdownLines()
        return blocks.isEmpty ? [.markdown(normalized)] : blocks
    }

    private static func appendMarkdown(_ markdown: String, into blocks: inout [Block]) {
        let splitBlocks = splitMarkdownAndTables(markdown)
        for block in splitBlocks {
            switch block {
            case .markdown(let text):
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.markdown(text))
                }
            case .table(let table):
                blocks.append(.table(table))
            case .code:
                break
            }
        }
    }

    private static func splitMarkdownAndTables(_ markdown: String) -> [Block] {
        let lines = markdown.components(separatedBy: "\n")
        var result: [Block] = []
        var markdownBuffer: [String] = []
        var index = 0

        func flushMarkdownBuffer() {
            guard !markdownBuffer.isEmpty else { return }
            result.append(.markdown(markdownBuffer.joined(separator: "\n")))
            markdownBuffer.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            if let table = parseTable(lines: lines, startIndex: index) {
                flushMarkdownBuffer()
                result.append(.table(table.tableText))
                index = table.nextIndex
            } else {
                markdownBuffer.append(lines[index])
                index += 1
            }
        }

        flushMarkdownBuffer()
        return result
    }

    private static func parseTable(
        lines: [String],
        startIndex: Int
    ) -> (tableText: String, nextIndex: Int)? {
        guard startIndex + 1 < lines.count else { return nil }

        let headerLine = lines[startIndex]
        let separatorLine = lines[startIndex + 1]
        guard headerLine.contains("|") else { return nil }
        guard containsMatch(tableSeparatorRegex, in: separatorLine) else { return nil }

        var collectedLines: [String] = [headerLine, separatorLine]
        var index = startIndex + 2

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                break
            }
            guard line.contains("|") else { break }
            collectedLines.append(line)
            index += 1
        }

        return (collectedLines.joined(separator: "\n"), index)
    }

    private static func containsMatch(_ regex: NSRegularExpression, in text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }
}

nonisolated enum ChatDisplayFormatter {
    private static let marker = "\u{241E}"
    private static let headingPunctuationSet = CharacterSet(charactersIn: ",;")
    private static let headingStopWords: Set<String> = ["a", "an", "and", "in", "of", "on", "or", "the", "to", "with"]

    private static let markdownBulletRegex = makeRegex("(?m)^\\s*[-*]\\s+")
    private static let markdownNumberedRegex = makeRegex("(?m)^\\s*\\d+[\\.)]\\s+")
    private static let markdownHeadingRegex = makeRegex("(?m)^\\s*#+\\s+")
    private static let markdownBlockQuoteRegex = makeRegex("(?m)^\\s*>\\s+")
    private static let sentenceSpacingRegex = makeRegex("([A-Za-z][.!?])([A-Z])")
    private static let sentenceQuoteSpacingRegex = makeRegex("([A-Za-z][.!?][\"”’])([A-Z])")
    private static let collapsedHeadingRegex = makeRegex("([a-z]{2,})([A-Z][a-z]{2,})(\\s+[A-Z][A-Za-z]{2,}:)")
    private static let collapsedTrailingHeadingRegex = makeRegex("([a-z]{2,})([A-Z][a-z]{2,}:)")
    private static let sectionAfterPunctuationRegex = makeRegex("([.!?])\\s*(?=[A-Z][A-Za-z]{2,}(?: [A-Za-z]{1,}){0,6}:)")
    private static let sectionAfterLabelRegex = makeRegex("([A-Za-z][A-Za-z ]{2,40}:)\\s*(?=[A-Z])")
    private static let inlineLabelRegex = makeRegex("\\b[A-Z][A-Za-z]{2,}(?: [A-Za-z]{1,}){0,6}:")
    private static let boldInlineLabelRegex = makeRegex("\\*\\*[A-Z][^*]{1,80}:\\*\\*")
    private static let denseLabelBoundaryRegex = makeRegex("(?<=[a-z0-9\\):])(?=[A-Z][A-Za-z]{2,}(?: [A-Za-z]{1,}){0,6}:)")
    private static let spacedLabelBoundaryRegex = makeRegex("(?<!\\d\\.)(?<=[\\.:;\\)0-9])\\s+(?=[A-Z][A-Za-z]{2,}(?: [A-Za-z]{1,}){0,6}:)")
    private static let lowerWordBeforeLabelRegex = makeRegex("\\b([a-z][a-z0-9]{2,})\\s+(?=[A-Z][A-Za-z]{2,}(?: [A-Za-z]{1,}){0,6}:)")
    private static let labelValueBoundaryRegex = makeRegex("(?m)([A-Z][A-Za-z ]{2,80}:)[ \\t]*(?=[0-9A-Za-z])")
    private static let shortLabelValueDoubleBreakRegex = makeRegex("(?m)([A-Z][A-Za-z ]{2,80}:)\\n\\n([0-9A-Za-z][^\\n]{0,40})(?=\\n\\n[A-Z][A-Za-z ]{2,80}:)")
    private static let denseBoldLabelBoundaryRegex = makeRegex("(?<=\\S)(?=\\*\\*[A-Z][^*]{1,80}:\\*\\*)")
    private static let boldLabelValueBoundaryRegex = makeRegex("(\\*\\*[^*]{1,80}:\\*\\*)[ \\t]*(?=[0-9A-Za-z])")
    private static let denseCollapsedWordRegex = makeRegex("([a-z]{4,})([A-Z][a-z]{3,})")
    private static let numberedAfterColonRegex = makeRegex("(:)\\s*(\\d+\\.\\s+)")
    private static let bulletAfterColonRegex = makeRegex("(:)\\s*(-\\s+)")
    private static let listAfterPunctuationNumberedParenRegex = makeRegex("([.!?:;])\\s*(\\d+\\)\\s*)")
    private static let listAfterPunctuationNumberedDotRegex = makeRegex("([.!?:;])\\s*(\\d+\\.\\s+)")
    private static let listAfterPunctuationBulletRegex = makeRegex("([.!?:;])\\s*([•*\\-]\\s+)")
    private static let listLeadingBulletRegex = makeRegex("(?m)^\\s*[•*]\\s+")
    private static let listLeadingDashRegex = makeRegex("(?m)^\\s*[–—]\\s+")
    private static let listLeadingNumberedParenRegex = makeRegex("(?m)^\\s*(\\d+)\\)\\s*")
    private static let listLeadingNumberedDotRegex = makeRegex("(?m)^\\s*(\\d+)\\.\\s*")
    private static let listSpacingRegex = makeRegex("(?m)(?<!\\n)\\n(?=(?:\\d+\\.\\s+|-\\s+))")
    private static let sentenceSplitRegex = makeRegex("(?<=[.!?])\\s+(?=[A-Za-z0-9])")

    static func format(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        let hadBlockMarkdown = containsBlockMarkdown(trimmed)

        // Repair common "no-space after punctuation" without touching URLs/versions.
        var working = repairSentenceSpacing(in: trimmed)
        // Repair collapsed heading words like "isConsidered Fundamental:".
        working = repairCollapsedHeadingWords(in: working)
        // Add section boundaries around heading-like labels.
        working = normalizeSectionBoundaries(in: working)
        // Normalize list markers and split inline lists onto their own lines.
        working = normalizeListMarkers(in: working)
        // Split dense inline label runs like "...collisionsBuild a foundation:".
        working = splitDenseInlineLabels(in: working)

        if shouldAutoFormat(working, hadBlockMarkdown: hadBlockMarkdown) {
            let sentenceChunks = splitIntoSentences(working)
            if sentenceChunks.count >= 2 {
                var outputBlocks: [String] = []
                var paragraphBuffer: [String] = []

                func flushParagraph() {
                    guard !paragraphBuffer.isEmpty else { return }
                    outputBlocks.append(paragraphBuffer.joined(separator: " "))
                    paragraphBuffer.removeAll(keepingCapacity: true)
                }

                for sentence in sentenceChunks {
                    if isHeading(sentence) {
                        flushParagraph()
                        outputBlocks.append("**\(sentence)**")
                        continue
                    }

                    if let bullet = bulletLine(sentence) {
                        flushParagraph()
                        outputBlocks.append(bullet)
                        continue
                    }

                    paragraphBuffer.append(sentence)
                    let bufferLength = paragraphBuffer.joined(separator: " ").count
                    if paragraphBuffer.count >= 2 || bufferLength >= 280 {
                        flushParagraph()
                    }
                }

                flushParagraph()
                let formatted = outputBlocks.joined(separator: "\n\n")
                if !formatted.isEmpty {
                    working = formatted
                }
            }
        }

        let paragraphized = forceParagraphizeDensePlainText(working)
        return rebalanceLongParagraphs(in: paragraphized)
    }

    static func markdownSyntax(for text: String) -> AttributedString.MarkdownParsingOptions.InterpretedSyntax {
        // Keep rendering mode stable during streaming; switching between
        // markdown syntaxes mid-response can collapse whitespace and make
        // content appear to "snap back" into a dense block.
        return .inlineOnlyPreservingWhitespace
    }

    private static func shouldAutoFormat(_ text: String, hadBlockMarkdown: Bool) -> Bool {
        guard text.count >= 48 else { return false }
        guard !containsBlockMarkdown(text) else { return false }
        guard !hadBlockMarkdown else { return false }
        let paragraphCount = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        guard paragraphCount < 3 else { return false }
        return true
    }

    private static func containsMarkdownStructure(_ text: String) -> Bool {
        containsMatch(markdownBulletRegex, in: text)
            || containsMatch(markdownNumberedRegex, in: text)
            || containsMatch(markdownHeadingRegex, in: text)
    }

    private static func containsBlockMarkdown(_ text: String) -> Bool {
        if text.contains("```") {
            return true
        }
        return containsMarkdownStructure(text)
            || containsMatch(markdownBlockQuoteRegex, in: text)
    }

    private static func repairSentenceSpacing(in text: String) -> String {
        var working = regexReplace(sentenceSpacingRegex, in: text, with: "$1 $2")
        working = regexReplace(sentenceQuoteSpacingRegex, in: working, with: "$1 $2")
        return working
    }

    private static func repairCollapsedHeadingWords(in text: String) -> String {
        var working = regexReplace(collapsedHeadingRegex, in: text, with: "$1 $2$3")
        working = regexReplace(collapsedTrailingHeadingRegex, in: working, with: "$1 $2")
        return working
    }

    private static func normalizeSectionBoundaries(in text: String) -> String {
        var working = regexReplace(sectionAfterPunctuationRegex, in: text, with: "$1\n\n")
        working = regexReplace(sectionAfterLabelRegex, in: working, with: "$1\n\n")
        return working
    }

    private static func splitDenseInlineLabels(in text: String) -> String {
        let labelCount = matchCount(inlineLabelRegex, in: text)
        let boldLabelCount = matchCount(boldInlineLabelRegex, in: text)
        guard labelCount >= 2 || boldLabelCount >= 1 else { return text }

        var working = regexReplace(denseLabelBoundaryRegex, in: text, with: "\n\n")
        working = regexReplace(spacedLabelBoundaryRegex, in: working, with: "\n\n")
        working = regexReplace(lowerWordBeforeLabelRegex, in: working, with: "$1\n\n")
        working = regexReplace(labelValueBoundaryRegex, in: working, with: "$1\n")
        working = regexReplace(denseBoldLabelBoundaryRegex, in: working, with: "\n\n")
        working = regexReplace(boldLabelValueBoundaryRegex, in: working, with: "$1\n")
        working = regexReplace(denseCollapsedWordRegex, in: working, with: "$1 $2")
        working = regexReplace(shortLabelValueDoubleBreakRegex, in: working, with: "$1\n$2")
        return working
    }

    private static func normalizeListMarkers(in text: String) -> String {
        var working = regexReplace(listAfterPunctuationNumberedParenRegex, in: text, with: "$1\n$2")
        working = regexReplace(listAfterPunctuationNumberedDotRegex, in: working, with: "$1\n$2")
        working = regexReplace(listAfterPunctuationBulletRegex, in: working, with: "$1\n$2")
        working = regexReplace(numberedAfterColonRegex, in: working, with: "$1\n\n$2")
        working = regexReplace(bulletAfterColonRegex, in: working, with: "$1\n\n$2")
        working = regexReplace(listLeadingBulletRegex, in: working, with: "- ")
        working = regexReplace(listLeadingDashRegex, in: working, with: "- ")
        working = regexReplace(listLeadingNumberedParenRegex, in: working, with: "$1. ")
        working = regexReplace(listLeadingNumberedDotRegex, in: working, with: "$1. ")
        working = regexReplace(listSpacingRegex, in: working, with: "\n\n")
        return working
    }

    private static func forceParagraphizeDensePlainText(_ text: String) -> String {
        guard !text.contains("```") else { return text }
        guard text.count >= 140 else { return text }
        // Keep explicit label-heavy structure intact once we've already split it.
        if matchCount(inlineLabelRegex, in: text) >= 2 || matchCount(boldInlineLabelRegex, in: text) >= 1 {
            return text
        }
        if hasStructuredMarkdownLayout(text) {
            return text
        }
        let paragraphCount = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        guard paragraphCount < 4 else { return text }

        let sentenceChunks = splitIntoSentences(text)
        guard sentenceChunks.count >= 3 else { return text }

        var outputBlocks: [String] = []
        var paragraphBuffer: [String] = []

        for sentence in sentenceChunks {
            paragraphBuffer.append(sentence)
            let bufferLength = paragraphBuffer.joined(separator: " ").count
            if paragraphBuffer.count >= 2 || bufferLength >= 280 {
                outputBlocks.append(paragraphBuffer.joined(separator: " "))
                paragraphBuffer.removeAll(keepingCapacity: true)
            }
        }

        if !paragraphBuffer.isEmpty {
            outputBlocks.append(paragraphBuffer.joined(separator: " "))
        }

        let formatted = outputBlocks.joined(separator: "\n\n")
        return formatted.isEmpty ? text : formatted
    }

    private static func hasStructuredMarkdownLayout(_ text: String) -> Bool {
        guard containsBlockMarkdown(text) else { return false }
        let nonEmptyLineCount = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        return nonEmptyLineCount >= 8
    }

    private static func rebalanceLongParagraphs(in text: String) -> String {
        guard !text.contains("```") else { return text }

        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else { return text }

        var output: [String] = []
        var didRebalance = false

        for paragraph in paragraphs {
            guard paragraph.count > 360 else {
                output.append(paragraph)
                continue
            }

            let sentenceChunks = splitIntoSentences(paragraph)
            guard sentenceChunks.count >= 4 else {
                output.append(paragraph)
                continue
            }

            didRebalance = true
            var buffer: [String] = []

            for sentence in sentenceChunks {
                buffer.append(sentence)
                let bufferLength = buffer.joined(separator: " ").count
                if buffer.count >= 2 || bufferLength >= 280 {
                    output.append(buffer.joined(separator: " "))
                    buffer.removeAll(keepingCapacity: true)
                }
            }

            if !buffer.isEmpty {
                output.append(buffer.joined(separator: " "))
            }
        }

        guard didRebalance else { return text }
        return output.joined(separator: "\n\n")
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        if sentences.count >= 2 {
            return sentences
        }

        let withMarkers = regexReplace(sentenceSplitRegex, in: text, with: marker)
        return withMarkers
            .components(separatedBy: marker)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isHeading(_ sentence: String) -> Bool {
        guard sentence.count <= 70 else { return false }
        guard !sentence.contains(":") else { return false }
        guard sentence.rangeOfCharacter(from: headingPunctuationSet) == nil else { return false }
        guard let last = sentence.last, !".!?".contains(last) else { return false }

        let words = sentence.split(separator: " ")
        guard (2...8).contains(words.count) else { return false }

        for word in words {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            let lower = cleaned.lowercased()
            if headingStopWords.contains(lower) {
                continue
            }
            guard let scalar = cleaned.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(scalar) else {
                return false
            }
        }
        return true
    }

    private static func bulletLine(_ sentence: String) -> String? {
        guard let colon = sentence.firstIndex(of: ":") else { return nil }
        let prefix = sentence[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = sentence[sentence.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !suffix.isEmpty else { return nil }

        let words = prefix.split(separator: " ")
        guard (1...6).contains(words.count) else { return nil }
        guard let firstScalar = prefix.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(firstScalar) else {
            return nil
        }

        return "- **\(prefix):** \(suffix)"
    }

    private static func containsMatch(_ regex: NSRegularExpression, in text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func matchCount(_ regex: NSRegularExpression, in text: String) -> Int {
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    private static func regexReplace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }
}

private struct MessageBubbleChrome<Content: View>: View {
    let role: ChatMessage.Role
    let content: Content

    init(role: ChatMessage.Role, @ViewBuilder content: () -> Content) {
        self.role = role
        self.content = content()
    }

    var body: some View {
        content.loomBubble(role: role)
    }
}

private struct SessionInlineBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    let banner: SessionMessagesViewModel.BannerState
    let performAction: (SessionMessagesViewModel.BannerState.Action) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)

            Text(banner.text)
                .foregroundStyle(.primary)

            Spacer()

            if let action = banner.action,
               let actionTitle = banner.actionTitle {
                Button(actionTitle) {
                    performAction(action)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .loomCard(cornerRadius: 10)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(LoomTheme.accentGradient(for: colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.45))
                .frame(width: 3)
                .padding(.vertical, 6)
                .padding(.leading, 6)
        }
    }
}

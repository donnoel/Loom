import SwiftUI
import AppKit
import AVFoundation
import Speech
import UniformTypeIdentifiers
import NaturalLanguage

struct SessionsWorkspaceView: View {
    private let store: SessionStore
    private let browseModels: () -> Void
    private let openOrInstallOllama: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var vm: RootViewModel

    @State private var editingSessionID: Session.ID?
    @State private var draftTitle: String = ""
    @FocusState private var focusedRenameID: Session.ID?
    @State private var isShowingTagsEditor = false
    @State private var tagsDraft = ""
    @State private var tagsEditingSessionID: Session.ID?

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(
        store: SessionStore,
        browseModels: @escaping () -> Void = {},
        openOrInstallOllama: @escaping () -> Void = {}
    ) {
        self.store = store
        self.browseModels = browseModels
        self.openOrInstallOllama = openOrInstallOllama
        _vm = State(initialValue: RootViewModel(store: store))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $vm.selectedSessionID) {
                ForEach(vm.filteredSessions) { session in
                    row(for: session)
                        .tag(session.id)
                        .contextMenu {
                            Button("Rename") { beginRename(session) }
                            Button(session.metadata.isPinned ? "Unpin" : "Pin") {
                                Task { await vm.togglePinned(id: session.id) }
                            }
                            Button("Edit Tags…") { beginTagsEdit(session) }
                            Divider()
                            Button(role: .destructive) {
                                Task {
                                    vm.selectedSessionID = session.id
                                    await vm.deleteSelected()
                                }
                            } label: {
                                Text("Delete")
                            }
                        }
                }
            }
            .accessibilityIdentifier("sessions.list")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
            .searchable(text: $vm.searchQuery, placement: .automatic)
            .safeAreaInset(edge: .top) {
                if let banner = vm.sidebarBanner {
                    SessionsSidebarBanner(
                        text: banner.text,
                        actionTitle: banner.actionTitle
                    ) {
                        Task { await vm.load() }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        Task { await vm.newSession() }
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                    .accessibilityIdentifier("sessions.toolbar.new")

                    Button {
                        if let selected = vm.selectedSessionID,
                           let session = vm.sessions.first(where: { $0.id == selected }) {
                            beginRename(session)
                        }
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("sessions.toolbar.rename")
                    .disabled(vm.selectedSessionID == nil)

                    Button {
                        Task { @MainActor in
                            await exportSelectedSession()
                        }
                    } label: {
                        Label("Export Session", systemImage: "square.and.arrow.up")
                    }
                    .disabled(vm.selectedSessionID == nil)

                    Button(role: .destructive) {
                        Task { await vm.deleteSelected() }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("sessions.toolbar.delete")
                    .disabled(vm.selectedSessionID == nil)
                }
            }
        } detail: {
            if let session = vm.session(for: vm.selectedSessionID) {
                SessionDetailView(
                    session: session,
                    store: store,
                    browseModels: browseModels,
                    openOrInstallOllama: openOrInstallOllama,
                    onActivity: {
                        vm.touchSession(id: session.id)
                    }
                )
                .id(session.id)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sessions.detail")
            } else {
                ContentUnavailableView("No Session Selected", systemImage: "text.bubble")
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("sessions.noSelection")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task { await vm.load() }
        .onChange(of: focusedRenameID) { _, newValue in
            if editingSessionID != nil, newValue == nil {
                commitRenameIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loomExportSessionRequested)) { _ in
            Task { @MainActor in
                await exportSelectedSession()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loomSessionsDidChange)) { _ in
            Task { await vm.load() }
        }
        .sheet(isPresented: $isShowingTagsEditor, onDismiss: resetTagsEditorState) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Edit Tags")
                    .font(.headline)

                Text("Use commas to separate tags.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("design, roadmap, notes", text: $tagsDraft, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()

                    Button("Cancel", role: .cancel) {
                        resetTagsEditorState()
                    }

                    Button("Save") {
                        saveTagsEdit()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
        }
    }

    @ViewBuilder
    private func row(for session: Session) -> some View {
        let isSelected = vm.selectedSessionID == session.id

        VStack(alignment: .leading, spacing: 2) {
            if editingSessionID == session.id {
                TextField("", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .accessibilityIdentifier("sessions.renameField")
                    .focused($focusedRenameID, equals: session.id)
                    .onSubmit { commitRenameIfNeeded() }
                    .onExitCommand { cancelRename() }
            } else {
                Text(session.metadata.title)
                    .font(.headline)
            }

            Text(session.metadata.updatedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LoomTheme.accentGradient(colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.10))
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.14), lineWidth: 1)
            }
        }
    }

    private func beginRename(_ session: Session) {
        editingSessionID = session.id
        draftTitle = session.metadata.title
        vm.selectedSessionID = session.id

        DispatchQueue.main.async {
            focusedRenameID = session.id
        }
    }

    private func cancelRename() {
        editingSessionID = nil
        draftTitle = ""
        focusedRenameID = nil
    }

    private func commitRenameIfNeeded() {
        guard let id = editingSessionID else { return }
        let title = draftTitle

        editingSessionID = nil
        draftTitle = ""
        focusedRenameID = nil

        Task { await vm.renameSession(id: id, to: title) }
    }

    private func beginTagsEdit(_ session: Session) {
        tagsEditingSessionID = session.id
        tagsDraft = session.metadata.tags.joined(separator: ", ")
        isShowingTagsEditor = true
    }

    private func resetTagsEditorState() {
        isShowingTagsEditor = false
        tagsEditingSessionID = nil
        tagsDraft = ""
    }

    private func saveTagsEdit() {
        guard let id = tagsEditingSessionID else {
            resetTagsEditorState()
            return
        }

        let tags = parseTags(from: tagsDraft)
        resetTagsEditorState()

        Task { await vm.updateTags(id: id, tags: tags) }
    }

    private func parseTags(from text: String) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for item in text.split(separator: ",", omittingEmptySubsequences: false) {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            ordered.append(trimmed)
        }

        return ordered
    }

    private func exportSelectedSession() async {
        guard let selected = vm.selectedSessionID,
              let session = vm.sessions.first(where: { $0.id == selected })
        else { return }

        do {
            let messages = try await store.loadMessages(sessionID: selected)
            let markdown = renderMarkdown(session: session, messages: messages)

            let defaultName = sanitizedFileName(session.metadata.title.isEmpty ? "Session" : session.metadata.title) + ".md"
            guard let url = presentSavePanel(defaultFileName: defaultName) else { return }

            guard let data = markdown.data(using: .utf8) else { return }
            try data.write(to: url, options: [.atomic])
        } catch {
            // For v1: fail quietly; later we can surface a banner.
        }
    }

    private func renderMarkdown(session: Session, messages: [ChatMessage]) -> String {
        var lines: [String] = []
        lines.append("# \(session.metadata.title)")
        lines.append("")
        lines.append("Created: \(formatDate(session.metadata.createdAt))")
        lines.append("Updated: \(formatDate(session.metadata.updatedAt))")
        if !session.metadata.tags.isEmpty {
            lines.append("Tags: \(session.metadata.tags.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("---")
        lines.append("")

        for message in messages {
            lines.append("**\(message.role.rawValue.capitalized)**")
            lines.append(message.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func formatDate(_ date: Date) -> String {
        Self.exportDateFormatter.string(from: date)
    }

    private func sanitizedFileName(_ input: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = input.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func presentSavePanel(defaultFileName: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]

        NSApp.activate(ignoringOtherApps: true)

        let result = panel.runModal()
        return result == .OK ? panel.url : nil
    }
}

private struct SessionsSidebarBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
        .padding(10)
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
    let browseModels: () -> Void
    let openOrInstallOllama: () -> Void
    let onActivity: () async -> Void

    @State private var vm: SessionMessagesViewModel
    @State private var didInitialScroll: Bool = false
    @State private var isBottomMarkerVisible: Bool = true
    @State private var scrollViewportFrame: CGRect = .null
    @State private var bottomMarkerFrame: CGRect = .null
    @State private var isShowingFileImporter: Bool = false
    @State private var isDictating: Bool = false
    @FocusState private var isDraftFieldFocused: Bool
    @AppStorage(LoomPreferenceKeys.voiceReplyVoiceIdentifier)
    private var voiceReplyVoiceIdentifier: String = ""
    @AppStorage(LoomPreferenceKeys.voiceReplyRate)
    private var voiceReplyRate: Double = VoiceReplyPreferences.defaultRate
    @State private var lastSpokenAssistantMessageID: UUID?
    @State private var speechInputController = SpeechInputController()
    @State private var speechSynthesizer = AVSpeechSynthesizer()

    init(
        session: Session,
        store: SessionStore,
        browseModels: @escaping () -> Void,
        openOrInstallOllama: @escaping () -> Void,
        onActivity: @escaping () async -> Void
    ) {
        self.session = session
        self.store = store
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
            VStack(spacing: 2) {
                Text(session.metadata.title)
                    .font(LoomTheme.sessionHeaderFont())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .padding(.bottom, 4)

                Text("Updated \(session.metadata.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Divider()

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
            }

            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
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
                                scrollToBottom(proxy)
                            }
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

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Menu {
                            if vm.availableModelTags.isEmpty {
                                Button("No installed models") {}
                                    .disabled(true)
                                Divider()
                                Button("Refresh Models") {
                                    Task { await vm.refreshInstalledModels() }
                                }
                                Button("Browse Models…") {
                                    browseModels()
                                }
                            } else {
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
                                Divider()
                                Button("Refresh Models") {
                                    Task { await vm.refreshInstalledModels() }
                                }
                                Button("Browse Models…") {
                                    browseModels()
                                }
                            }
                        } label: {
                            Label(vm.activeModelSelectionLabel, systemImage: "cpu")
                                .lineLimit(1)
                                .frame(maxWidth: 260, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("session.detail.modelPicker")

                        Spacer()
                    }

                    if let note = vm.activeModelCapabilityNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !vm.pendingAttachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(vm.pendingAttachments) { attachment in
                                    HStack(spacing: 6) {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(attachment.fileName)
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(1)
                                            Text(attachment.characterCountLabel)
                                                .font(.caption2)
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
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(.quaternary.opacity(0.35), in: Capsule())
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    HStack(alignment: .bottom, spacing: 8) {
                        HStack(spacing: 6) {
                            Button {
                                isShowingFileImporter = true
                            } label: {
                                Image(systemName: "paperclip")
                            }
                            .help(vm.activeModelSupportsFileUploads ? "Attach files" : "Current model does not support file uploads")
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(vm.isGenerating || !vm.activeModelSupportsFileUploads)

                            Button {
                                toggleDictation()
                            } label: {
                                Image(systemName: isDictating ? "waveform.circle.fill" : "mic")
                            }
                            .help(vm.activeModelSupportsSpeechInput ? "Dictate message" : "Current model does not support speech input")
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(vm.isGenerating || !vm.activeModelSupportsSpeechInput)

                            Button {
                                vm.isVoiceReplyEnabled.toggle()
                                if !vm.isVoiceReplyEnabled {
                                    speechSynthesizer.stopSpeaking(at: .immediate)
                                }
                            } label: {
                                Image(systemName: vm.isVoiceReplyEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                            }
                            .help(vm.activeModelSupportsSpeechOutput ? "Read replies aloud" : "Current model does not support speech output")
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!vm.activeModelSupportsSpeechOutput)
                        }

                        TextField("Message", text: $vm.draft, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...6)
                            .focused($isDraftFieldFocused)
                            .accessibilityIdentifier("session.detail.messageField")
                            .onSubmit {
                                guard !vm.isGenerating else { return }
                                sendAndScroll(proxy)
                            }
                            .frame(maxWidth: .infinity)

                        if vm.isGenerating {
                            Button(role: .destructive) {
                                vm.stopGenerating()
                                stopDictationIfNeeded()
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .accessibilityIdentifier("session.detail.stopButton")
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                sendAndScroll(proxy)
                            } label: {
                                Label("Send", systemImage: "paperplane.fill")
                            }
                            .accessibilityIdentifier("session.detail.sendButton")
                            .buttonStyle(.bordered)
                            .tint(.accentColor)
                            .disabled(vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(8)
                .loomCard(cornerRadius: 14)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
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
        }
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
        utterance.rate = Float(VoiceReplyPreferences.normalizedRate(voiceReplyRate))
        if let configuredIdentifier = voiceReplyVoiceIdentifier.nonEmptyTrimmed,
           let configuredVoice = AVSpeechSynthesisVoice(identifier: configuredIdentifier) {
            utterance.voice = configuredVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
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
                        .font(.headline)
                    Text("Ask Loom anything in everyday language. You can also attach files or use your mic.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Try one of these:")
                .font(.caption.weight(.semibold))
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
                .font(.caption)
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
    @State private var isHovered: Bool = false

    static func == (lhs: MessageRowView, rhs: MessageRowView) -> Bool {
        lhs.message == rhs.message && lhs.isThinking == rhs.isThinking
    }

    var body: some View {
        let isUser = message.role == .user

        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            MessageBubbleChrome(role: message.role) {
                if isThinking {
                    TypingPulseView()
                } else {
                    MessageContentView(
                        content: message.content,
                        role: message.role,
                        onRegenerate: onRegenerate
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(roleLabel): \(accessibilityMessageText)")
            .accessibilityIdentifier(accessibilityIdentifier)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.vertical, 4)
        .scaleEffect(isHovered ? 1.006 : 1.0)
        .offset(y: isHovered ? -1 : 0)
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .onHover { hovering in
            guard message.role == .assistant || message.role == .user else { return }
            isHovered = hovering
        }
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
                .font(.caption)
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
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
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

    var body: some View {
        let displayContent = ChatDisplayFormatter.format(content)
        let markdownSyntax = ChatDisplayFormatter.markdownSyntax(for: displayContent)

        Group {
            if let attributed = try? AttributedString(
                markdown: displayContent,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: markdownSyntax)
            ) {
                Text(attributed)
            } else {
                Text(displayContent)
            }
        }
        .textSelection(.enabled)
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayContent, forType: .string)
            }

            if role == .assistant,
               let onRegenerate {
                Divider()
                Button("Regenerate", action: onRegenerate)
            }
        }
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
    private static let labelValueBoundaryRegex = makeRegex("(?m)([A-Z][A-Za-z ]{2,80}:)\\s*(?=[0-9A-Za-z])")
    private static let denseBoldLabelBoundaryRegex = makeRegex("(?<=\\S)(?=\\*\\*[A-Z][^*]{1,80}:\\*\\*)")
    private static let boldLabelValueBoundaryRegex = makeRegex("(\\*\\*[^*]{1,80}:\\*\\*)\\s*(?=[0-9A-Za-z])")
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
        working = regexReplace(labelValueBoundaryRegex, in: working, with: "$1\n")
        working = regexReplace(denseBoldLabelBoundaryRegex, in: working, with: "\n\n")
        working = regexReplace(boldLabelValueBoundaryRegex, in: working, with: "$1\n")
        working = regexReplace(denseCollapsedWordRegex, in: working, with: "$1 $2")
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

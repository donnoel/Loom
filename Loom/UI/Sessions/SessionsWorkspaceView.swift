import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
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
        .navigationSplitViewStyle(.prominentDetail)
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

private struct SessionDetailView: View {
    let session: Session
    let store: SessionStore
    let browseModels: () -> Void
    let openOrInstallOllama: () -> Void
    let onActivity: () async -> Void

    @State private var vm: SessionMessagesViewModel
    @State private var didInitialScroll: Bool = false

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
                            Text("This session is ready.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .id("bottom")
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
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                    }
                    .padding(.vertical, 8)
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

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $vm.draft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("session.detail.messageField")
                        .onSubmit {
                            guard !vm.isGenerating else { return }
                            sendAndScroll(proxy)
                        }

                    if vm.isGenerating {
                        Button(role: .destructive) {
                            vm.stopGenerating()
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
                .padding(8)
                .loomCard(cornerRadius: 14)

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .onDisappear {
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
        if let last = vm.messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

private struct MessageRowView: View, Equatable {
    let message: ChatMessage
    let isThinking: Bool
    let onRegenerate: (() -> Void)?

    static func == (lhs: MessageRowView, rhs: MessageRowView) -> Bool {
        lhs.message == rhs.message && lhs.isThinking == rhs.isThinking
    }

    var body: some View {
        let isUser = message.role == .user

        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Text(roleLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            MessageBubbleChrome(role: message.role) {
                if isThinking {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    MessageContentView(
                        content: message.content,
                        role: message.role,
                        onRegenerate: onRegenerate
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.vertical, 4)
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
}

private struct MessageContentView: View {
    let content: String
    let role: ChatMessage.Role
    let onRegenerate: (() -> Void)?

    var body: some View {
        let displayContent = ChatDisplayFormatter.format(content)

        Group {
            if let attributed = try? AttributedString(
                markdown: displayContent,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
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
                NSPasteboard.general.setString(content, forType: .string)
            }

            if role == .assistant,
               let onRegenerate {
                Divider()
                Button("Regenerate", action: onRegenerate)
            }
        }
    }
}

private nonisolated enum ChatDisplayFormatter {
    private static let marker = "\u{241E}"

    static func format(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        // Repair common "no-space after punctuation" and heading/list label joins.
        var working = regexReplace("([.!?])([^\\s.!?])", in: trimmed, with: "$1 $2")
        working = regexReplace("([a-z])([A-Z][A-Za-z]+ [A-Z][A-Za-z]+:)", in: working, with: "$1\n\n$2")

        guard shouldAutoFormat(working) else { return working }

        let sentenceChunks = splitIntoSentences(working)
        guard sentenceChunks.count >= 3 else { return working }

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
            if paragraphBuffer.count >= 2 {
                flushParagraph()
            }
        }

        flushParagraph()
        let formatted = outputBlocks.joined(separator: "\n\n")
        return formatted.isEmpty ? working : formatted
    }

    private static func shouldAutoFormat(_ text: String) -> Bool {
        guard text.count >= 220 else { return false }
        guard !text.contains("```") else { return false }
        guard !text.contains("\n\n") else { return false }
        guard !containsMarkdownStructure(text) else { return false }
        return true
    }

    private static func containsMarkdownStructure(_ text: String) -> Bool {
        text.contains("- ") || text.contains("* ") || text.contains("# ")
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
        let withMarkers = regexReplace("(?<=[.!?])\\s+(?=[A-Z0-9])", in: text, with: marker)
        return withMarkers
            .components(separatedBy: marker)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isHeading(_ sentence: String) -> Bool {
        guard sentence.count <= 70 else { return false }
        guard !sentence.contains(":") else { return false }
        guard sentence.rangeOfCharacter(from: CharacterSet(charactersIn: ",;")) == nil else { return false }
        guard let last = sentence.last, !".!?".contains(last) else { return false }

        let words = sentence.split(separator: " ")
        guard (2...8).contains(words.count) else { return false }

        for word in words {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            let lower = cleaned.lowercased()
            if ["a", "an", "and", "in", "of", "on", "or", "the", "to", "with"].contains(lower) {
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

    private static func regexReplace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
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

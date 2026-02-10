import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SessionsWorkspaceView: View {
    private let store: SessionStore
    private let browseModels: () -> Void
    private let openOrInstallOllama: () -> Void
    @State private var vm: RootViewModel

    @State private var editingSessionID: Session.ID?
    @State private var draftTitle: String = ""
    @FocusState private var focusedRenameID: Session.ID?

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
                ForEach(vm.sessions) { session in
                    row(for: session)
                        .tag(session.id)
                        .contextMenu {
                            Button("Rename") { beginRename(session) }
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
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        Task { await vm.newSession() }
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }

                    Button {
                        if let selected = vm.selectedSessionID,
                           let session = vm.sessions.first(where: { $0.id == selected }) {
                            beginRename(session)
                        }
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
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
            } else {
                ContentUnavailableView("No Session Selected", systemImage: "text.bubble")
            }
        }
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
    }

    @ViewBuilder
    private func row(for session: Session) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if editingSessionID == session.id {
                TextField("", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.headline)
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

private struct SessionDetailView: View {
    let session: Session
    let store: SessionStore
    let browseModels: () -> Void
    let openOrInstallOllama: () -> Void
    let onActivity: () async -> Void

    @State private var vm: SessionMessagesViewModel

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
            Text(session.metadata.title)
                .font(.largeTitle.bold())

            Divider()

            if let banner = vm.banner {
                SessionInlineBanner(banner: banner) { action in
                    switch action {
                    case .browseModels:
                        browseModels()
                    case .openOrInstallOllama:
                        openOrInstallOllama()
                    }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if vm.messages.isEmpty {
                            Text("This session is ready.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .id("bottom")
                        } else {
                            ForEach(vm.messages) { message in
                                messageRow(for: message)
                                    .id(message.id)
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
                    DispatchQueue.main.async {
                        scrollToBottom(proxy)
                    }
                }
                .onChange(of: vm.messages.last?.content) { _, _ in
                    DispatchQueue.main.async {
                        scrollToBottom(proxy)
                    }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $vm.draft)
                        .textFieldStyle(.roundedBorder)
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
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            sendAndScroll(proxy)
                        } label: {
                            Label("Send", systemImage: "paperplane.fill")
                        }
                        .disabled(vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = vm.messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func messageRow(for message: ChatMessage) -> some View {
        let isUser = message.role == .user

        return VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Text(message.role.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)

            bubbleContent(for: message)
                .loomBubble(role: message.role)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func bubbleContent(for message: ChatMessage) -> some View {
        if vm.isGenerating,
           vm.generatingMessageID == message.id,
           message.content.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Thinking…")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(message.content)
                .textSelection(.enabled)
        }
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

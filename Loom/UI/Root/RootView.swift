import SwiftUI
import AppKit

struct RootView: View {
    private let store: SessionStore
    @State private var vm: RootViewModel

    @State private var editingSessionID: Session.ID?
    @State private var draftTitle: String = ""
    @FocusState private var focusedRenameID: Session.ID?

    init(store: SessionStore) {
        self.store = store
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
            .navigationTitle("Loom")
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
                        Task { await exportSelectedSession() }
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
                    onActivity: {
                        touchSessionRecency(sessionID: session.id)
                    }
                )
                    .id(session.id)
            } else {
                ContentUnavailableView("No Session Selected", systemImage: "text.bubble")
            }
        }
        .task { await vm.load() }
        .onChange(of: focusedRenameID) { _, newValue in
            // If we were editing and focus left, commit.
            if editingSessionID != nil, newValue == nil {
                commitRenameIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loomExportSessionRequested)) { _ in
            Task { await exportSelectedSession() }
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

        // Focus on next run loop so List selection settles first.
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
    
    private func touchSessionRecency(sessionID: Session.ID) {
        guard let idx = vm.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        vm.sessions[idx].metadata.updatedAt = Date()
        vm.sessions.sort { $0.metadata.updatedAt > $1.metadata.updatedAt }
    }

    private func exportSelectedSession() async {
        guard let selected = vm.selectedSessionID,
              let session = vm.sessions.first(where: { $0.id == selected })
        else { return }

        do {
            let messages = try await store.loadMessages(sessionID: selected)
            let markdown = renderMarkdown(session: session, messages: messages)

            let defaultName = sanitizedFileName(session.metadata.title.isEmpty ? "Session" : session.metadata.title) + ".md"
            guard let url = await presentSavePanel(defaultFileName: defaultName) else { return }

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
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func sanitizedFileName(_ input: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = input.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func presentSavePanel(defaultFileName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName
        panel.allowedContentTypes = [.markdown]

        // Prefer sheet presentation when possible.
        if let window = NSApp.keyWindow {
            return await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { result in
                    continuation.resume(returning: result == .OK ? panel.url : nil)
                }
            }
        } else {
            let result = panel.runModal()
            return result == .OK ? panel.url : nil
        }
    }
}

private struct SessionDetailView: View {
    let session: Session
    let store: SessionStore
    let onActivity: () async -> Void

    @State private var vm: SessionMessagesViewModel

    init(session: Session, store: SessionStore, onActivity: @escaping () async -> Void) {
        self.session = session
        self.store = store
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.role.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(message.content)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 4)
                                .id(message.id)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .task {
                    await vm.load()
                    scrollToBottom(proxy)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $vm.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await vm.sendDraft() }
                    }

                Button {
                    Task { await vm.sendDraft() }
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .disabled(vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = vm.messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

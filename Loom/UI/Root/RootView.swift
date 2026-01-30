import SwiftUI

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
                SessionDetailView(session: session, store: store)
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
}

private struct SessionDetailView: View {
    let session: Session
    let store: SessionStore

    @State private var vm: SessionMessagesViewModel

    init(session: Session, store: SessionStore) {
        self.session = session
        self.store = store
        _vm = State(initialValue: SessionMessagesViewModel(
            store: store,
            sessionID: session.id
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

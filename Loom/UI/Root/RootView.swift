import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SidebarSelection: Hashable {
    case destination(SidebarItem)
    case session(Session.ID)
}

private struct AppInfoView: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct CompanyCitation: Identifiable {
        let company: String
        let role: String
        let url: URL

        var id: String { company }
    }

    private let catalog: ModelCatalog

    init(catalog: ModelCatalog = .load()) {
        self.catalog = catalog
    }

    private var modelVendors: [String] {
        Array(Set(catalog.all.map(\.vendor))).sorted()
    }

    private var modelVendorListText: String {
        modelVendors.joined(separator: ", ")
    }

    private var citations: [CompanyCitation] {
        var references: [CompanyCitation] = [
            CompanyCitation(
                company: "Apple",
                role: "macOS platform and SwiftUI interface framework used by Loom.",
                url: URL(string: "https://developer.apple.com/xcode/")!
            ),
            CompanyCitation(
                company: "Ollama",
                role: "Local runtime that loads and runs models on your Mac.",
                url: URL(string: "https://www.ollama.com")!
            )
        ]

        let providerByVendor: [String: CompanyCitation] = [
            "Google": CompanyCitation(
                company: "Google",
                role: "Creator of Gemma models.",
                url: URL(string: "https://deepmind.google/models/gemma/")!
            ),
            "Meta": CompanyCitation(
                company: "Meta",
                role: "Creator of Llama models.",
                url: URL(string: "https://github.com/meta-llama/llama-models")!
            ),
            "Microsoft": CompanyCitation(
                company: "Microsoft",
                role: "Creator of Phi models.",
                url: URL(string: "https://azure.microsoft.com/en-us/products/phi")!
            ),
            "Mistral AI": CompanyCitation(
                company: "Mistral AI",
                role: "Creator of Mistral models.",
                url: URL(string: "https://docs.mistral.ai/getting-started/models/")!
            ),
            "Qwen": CompanyCitation(
                company: "Alibaba Cloud (Qwen)",
                role: "Organization behind the Qwen model family.",
                url: URL(string: "https://www.alibabacloud.com/en/solutions/generative-ai/qwen?_p_lc=1")!
            )
        ]

        for vendor in modelVendors {
            if let citation = providerByVendor[vendor] {
                references.append(citation)
            }
        }

        return references
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                introCard
                flowCard
                modelsCard
                citationsCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen.info")
        .navigationTitle("Info")
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How Loom works")
                .font(LoomTheme.Typography.pageHero)

            Text("Loom is the chat workspace you see. Ollama is the local engine that does the heavy lifting. Models are the brains made by different AI companies.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LoomTheme.accentGradient(for: colorScheme).opacity(colorScheme == .dark ? 0.28 : 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private var flowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What Happens When You Send A Message")
                .font(LoomTheme.Typography.sectionTitle)

            flowStep(
                icon: "1.circle.fill",
                title: "You type in Loom",
                detail: "The app collects your message and keeps your project/session organized."
            )
            flowStep(
                icon: "2.circle.fill",
                title: "Loom talks to Ollama on this Mac",
                detail: "Your message is sent to a local Ollama service, not a random cloud service."
            )
            flowStep(
                icon: "3.circle.fill",
                title: "Ollama runs your selected model",
                detail: "The active model does the reasoning and creates the reply."
            )
            flowStep(
                icon: "4.circle.fill",
                title: "Reply streams back into Loom",
                detail: "You see the answer appear live, and Loom keeps your chat history locally."
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private func flowStep(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .font(.headline)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LoomTheme.Typography.bodyStrong)
                Text(detail)
                    .font(LoomTheme.Typography.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Makers In Loom")
                .font(LoomTheme.Typography.sectionTitle)

            Text("Current model providers in this catalog: \(modelVendorListText).")
                .foregroundStyle(.secondary)

            Text("Different models have different strengths. For example, some are better for writing, some for coding, and some for quick low-memory tasks.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var citationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Citations")
                .font(LoomTheme.Typography.sectionTitle)

            Text("Official references for each company involved in this stack:")
                .font(LoomTheme.Typography.body)
                .foregroundStyle(.secondary)

            ForEach(citations) { citation in
                VStack(alignment: .leading, spacing: 3) {
                    Text(citation.company)
                        .font(LoomTheme.Typography.bodyStrong)
                    Text(citation.role)
                        .font(LoomTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                    Link(citation.url.absoluteString, destination: citation.url)
                        .font(LoomTheme.Typography.monospacedCaption)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }
}

struct RootView: View {
    private let store: SessionStore

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSidebarSelection: SidebarSelection?
    @State private var statusViewModel = StatusViewModel()
    @State private var sessionsViewModel: RootViewModel
    @State private var isShowingStatusPopover: Bool = false
    @State private var renameSessionID: Session.ID?
    @State private var renameDraft: String = ""
    @State private var collectionSessionID: Session.ID?
    @State private var collectionDraft: String = ""
    @State private var searchJumpMessageID: ChatMessage.ID?
    @State private var isShowingArchivedSessions: Bool = false

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(store: SessionStore) {
        self.store = store
        _sessionsViewModel = State(initialValue: RootViewModel(store: store))
    }

    var body: some View {
        ZStack {
            (colorScheme == .dark
                ? Color(red: 0.11, green: 0.11, blue: 0.12)
                : Color(red: 0.96, green: 0.96, blue: 0.97))
                .ignoresSafeArea()

            NavigationSplitView {
                sidebar
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.prominentDetail)
            .toolbar {
                if showsSessionToolbarActions {
                    ToolbarItemGroup {
                        Button {
                            Task { await createSession() }
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .help("New Chat")
                        .accessibilityIdentifier("sessions.toolbar.new")
                        .controlSize(.small)

                        Button {
                            beginRenameForSelectedSession()
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .help("Rename")
                        .accessibilityIdentifier("sessions.toolbar.rename")
                        .disabled(selectedSession == nil)
                        .controlSize(.small)

                        Button(role: .destructive) {
                            Task { await deleteSelectedSession() }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Delete")
                        .accessibilityIdentifier("sessions.toolbar.delete")
                        .disabled(selectedSession == nil)
                        .controlSize(.small)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    statusPillButton
                }
            }
        }
        .task {
            statusViewModel.startMonitoring()
            await sessionsViewModel.load()
            synchronizeSelectionAfterSessionReload(preferredSessionID: sessionsViewModel.selectedSessionID)
        }
        .onChange(of: selectedSidebarSelection) { _, newValue in
            if case .session(let id) = newValue {
                sessionsViewModel.selectedSessionID = id
            } else if case .destination(.sessions) = newValue,
                      sessionsViewModel.selectedSessionID == nil,
                      let first = sessionsViewModel.sessions.first {
                sessionsViewModel.selectedSessionID = first.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loomExportSessionRequested)) { _ in
            Task { @MainActor in
                await exportSelectedSession()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loomSessionsDidChange)) { _ in
            Task {
                await sessionsViewModel.load()
                synchronizeSelectionAfterSessionReload(
                    preferredSessionID: sessionsViewModel.selectedSessionID,
                    forceSessionSelection: false
                )
            }
        }
        .sheet(isPresented: isShowingRenameSheet) {
            renameSheet
        }
        .sheet(isPresented: isShowingCollectionSheet) {
            collectionSheet
        }
        .onDisappear {
            statusViewModel.stopMonitoring()
        }
    }

    private var sidebar: some View {
        List {
            Section {
                if let banner = sessionsViewModel.sidebarBanner {
                    sidebarBannerRow(banner)
                }

                newSessionSidebarRow

                if isGlobalSearchActive {
                    globalSearchContent
                } else {
                    if sessionsViewModel.activeSessions.isEmpty {
                        Text(sessionsViewModel.archivedSessions.isEmpty ? "No chats yet" : "No active chats")
                            .font(LoomTheme.Typography.body)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(sessionsViewModel.activeSessionGroups) { group in
                            if sessionsViewModel.activeSessionGroups.count > 1 {
                                collectionHeaderRow(title: group.title, count: group.sessions.count)
                            }

                            ForEach(group.sessions) { session in
                                sessionSidebarRow(session)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        searchJumpMessageID = nil
                                        selectedSidebarSelection = .session(session.id)
                                    }
                                    .contextMenu {
                                        sessionContextMenu(for: session, isArchived: false)
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                        }
                    }

                    if !sessionsViewModel.archivedSessions.isEmpty {
                        archivedDisclosureRow

                        if isShowingArchivedSessions {
                            ForEach(sessionsViewModel.archivedSessionGroups) { group in
                                if sessionsViewModel.archivedSessionGroups.count > 1 {
                                    collectionHeaderRow(title: group.title, count: group.sessions.count)
                                }

                                ForEach(group.sessions) { session in
                                    sessionSidebarRow(session)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            searchJumpMessageID = nil
                                            selectedSidebarSelection = .session(session.id)
                                        }
                                        .contextMenu {
                                            sessionContextMenu(for: session, isArchived: true)
                                        }
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                    }
                            }
                        }
                    }
                }
            } header: {
                Text("Chats")
                    .textCase(nil)
            }

            Section {
                destinationSidebarRow(.models)
                destinationSidebarRow(.compare)
                destinationSidebarRow(.info)
                destinationSidebarRow(.status)
                destinationSidebarRow(.trust)
                destinationSidebarRow(.settings)
            }
        }
        .searchable(text: $sessionsViewModel.searchQuery, placement: .sidebar)
        .onChange(of: sessionsViewModel.searchQuery) { _, _ in
            sessionsViewModel.scheduleGlobalSearchRefresh()
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(colorScheme == .dark ? Color(red: 0.10, green: 0.10, blue: 0.11) : Color(red: 0.95, green: 0.95, blue: 0.96))
        .navigationSplitViewColumnWidth(min: 208, ideal: 220, max: 232)
        .navigationTitle("")
    }

    private func sidebarBannerRow(_ banner: RootViewModel.SidebarBannerState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(banner.text)
                .font(LoomTheme.Typography.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button(banner.actionTitle) {
                Task { await reloadSessionsFromSidebarBanner() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar.session.banner")
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var globalSearchContent: some View {
        if sessionsViewModel.isSearchingGlobally {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching all chats…")
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
        } else if sessionsViewModel.globalSearchResults.isEmpty {
            Text("No matches found")
                .font(LoomTheme.Typography.body)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
        } else {
            ForEach(sessionsViewModel.globalSearchResults) { result in
                globalSearchResultRow(result)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openSearchResult(result)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    private func collectionHeaderRow(title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(LoomTheme.Typography.captionTiny)
                .foregroundStyle(.secondary)
            Text(title)
                .font(LoomTheme.Typography.captionStrong)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(count)")
                .font(LoomTheme.Typography.captionTiny)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) chats")
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func globalSearchResultRow(_ result: SessionSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.sessionTitle)
                .font(LoomTheme.Typography.bodyStrong)
                .lineLimit(1)

            Text(result.snippet)
                .font(LoomTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(result.source == .title ? "Title" : "Message")
                if let role = result.messageRole {
                    Text(role.rawValue.capitalized)
                }
            }
            .font(LoomTheme.Typography.captionTiny)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: result))
        .accessibilityHint("Open chat and jump to this match")
    }

    private var archivedDisclosureRow: some View {
        let title = "Archived (\(sessionsViewModel.archivedSessions.count))"
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isShowingArchivedSessions.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isShowingArchivedSessions ? "chevron.down" : "chevron.right")
                    .font(LoomTheme.Typography.captionTiny)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isShowingArchivedSessions ? "Hide archived sessions" : "Show archived sessions")
        .loomSidebarItem(selected: false)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var newSessionSidebarRow: some View {
        Button {
            Task { await createSession() }
        } label: {
            Label("New Chat", systemImage: "square.and.pencil")
                .font(LoomTheme.Typography.bodyStrong)
                .foregroundStyle(Color.accentColor)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.session.new")
        .loomSidebarItem(selected: false)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSidebarSelection ?? .destination(.sessions) {
        case .destination(.models):
            ModelsView(
                onModelSelectionChanged: {
                    await statusViewModel.refresh()
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("root.detail.models")
        case .destination(.compare):
            CompareModeView()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.detail.compare")
        case .destination(.status):
            AIChatbotStatusView()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.detail.aiStatus")
        case .destination(.info):
            AppInfoView()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.detail.info")
        case .destination(.settings):
            SettingsView(store: store)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.detail.settings")
        case .destination(.trust):
            TrustCenterView()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.detail.trust")
        case .destination(.sessions):
            currentSessionDetail
        case .session:
            currentSessionDetail
        }
    }

    @ViewBuilder
    private var currentSessionDetail: some View {
        if let session = selectedSession {
            SessionDetailView(
                session: session,
                store: store,
                initialScrollMessageID: searchJumpMessageID,
                browseModels: {
                    selectedSidebarSelection = .destination(.models)
                },
                openOrInstallOllama: {
                    statusViewModel.openOrInstallOllama()
                },
                onActivity: {
                    await sessionsViewModel.touchSession(id: session.id)
                }
            )
            .id(session.id)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("root.detail.sessions")
        } else {
            ContentUnavailableView("No Session Selected", systemImage: "text.bubble")
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sessions.noSelection")
        }
    }

    private var selectedSessionID: Session.ID? {
        if case .session(let id) = selectedSidebarSelection {
            return id
        }
        return sessionsViewModel.selectedSessionID
    }

    private var selectedSession: Session? {
        sessionsViewModel.session(for: selectedSessionID)
    }

    private var isGlobalSearchActive: Bool {
        !sessionsViewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func openSearchResult(_ result: SessionSearchResult) {
        searchJumpMessageID = result.messageID
        sessionsViewModel.selectedSessionID = result.sessionID
        selectedSidebarSelection = .session(result.sessionID)
    }

    private func accessibilityLabel(for result: SessionSearchResult) -> String {
        if let role = result.messageRole {
            return "\(result.sessionTitle), \(result.source == .title ? "title match" : "message match"), \(role.rawValue), \(result.snippet)"
        }
        return "\(result.sessionTitle), \(result.source == .title ? "title match" : "message match"), \(result.snippet)"
    }

    private var showsSessionToolbarActions: Bool {
        if sessionsViewModel.sessions.isEmpty {
            return true
        }

        if case .destination(let item) = selectedSidebarSelection {
            return item == .sessions
        }
        if case .session = selectedSidebarSelection {
            return true
        }
        return false
    }

    private var isShowingRenameSheet: Binding<Bool> {
        Binding(
            get: { renameSessionID != nil },
            set: { isPresented in
                if !isPresented {
                    cancelRename()
                }
            }
        )
    }

    private var isShowingCollectionSheet: Binding<Bool> {
        Binding(
            get: { collectionSessionID != nil },
            set: { isPresented in
                if !isPresented {
                    cancelCollectionEdit()
                }
            }
        )
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Session")
                .font(LoomTheme.Typography.sectionTitle)

            TextField("Session title", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    commitRename()
                }

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    cancelRename()
                }

                Button("Save") {
                    commitRename()
                }
                .buttonStyle(.borderedProminent)
                .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private var collectionSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set Collection")
                .font(LoomTheme.Typography.sectionTitle)

            TextField("Collection name", text: $collectionDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    commitCollectionEdit()
                }

            HStack {
                Button("Remove") {
                    clearCollection()
                }
                .disabled(selectedCollectionSession?.metadata.collectionName == nil)

                Spacer()

                Button("Cancel", role: .cancel) {
                    cancelCollectionEdit()
                }

                Button("Save") {
                    commitCollectionEdit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(collectionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func destinationSidebarRow(_ item: SidebarItem) -> some View {
        let isSelected = selectedSidebarSelection == .destination(item)

        return Label(item.title, systemImage: item.systemImage)
            .foregroundStyle(isSelected ? LoomTheme.sidebarSelectedText(colorScheme) : LoomTheme.textSecondary(colorScheme))
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("sidebar.\(item.id)")
            .loomSidebarItem(selected: isSelected)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedSidebarSelection = .destination(item)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func sessionSidebarRow(_ session: Session) -> some View {
        let isSelected = selectedSidebarSelection == .session(session.id)
        let sessionTitleColor: Color = .blue

        return HStack(spacing: 10) {
            Text(session.metadata.title)
                .font(LoomTheme.Typography.bodyStrong)
                .foregroundStyle(sessionTitleColor)
                .lineLimit(1)
                .truncationMode(.tail)

            if session.metadata.isPinned {
                Image(systemName: "pin.fill")
                    .font(LoomTheme.Typography.captionTiny)
                    .foregroundStyle(LoomTheme.textSecondary(colorScheme))
            }

            if session.metadata.isArchived {
                Image(systemName: "archivebox")
                    .font(LoomTheme.Typography.captionTiny)
                    .foregroundStyle(LoomTheme.textSecondary(colorScheme))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("sidebar.session.\(session.id.uuidString)")
        .accessibilityLabel(accessibilityLabel(for: session))
        .loomSidebarItem(selected: isSelected)
    }

    @ViewBuilder
    private func sessionContextMenu(for session: Session, isArchived: Bool) -> some View {
        Button("Rename") {
            beginRename(session)
        }

        Button("Set Collection…") {
            beginCollectionEdit(session)
        }

        Button(session.metadata.isPinned ? "Unpin" : "Pin") {
            Task { await sessionsViewModel.togglePinned(id: session.id) }
        }

        Button(isArchived ? "Unarchive" : "Archive") {
            Task { await sessionsViewModel.toggleArchived(id: session.id) }
        }

        Divider()

        Button(role: .destructive) {
            Task { await deleteSession(id: session.id) }
        } label: {
            Text("Delete")
        }
    }

    private func accessibilityLabel(for session: Session) -> String {
        if let collectionName = session.metadata.collectionName {
            return "\(session.metadata.title), \(collectionName)"
        }
        return session.metadata.title
    }

    private func createSession() async {
        await sessionsViewModel.newSession()
        synchronizeSelectionAfterSessionReload(preferredSessionID: sessionsViewModel.selectedSessionID)
    }

    private func deleteSelectedSession() async {
        guard let selectedSessionID else { return }
        await deleteSession(id: selectedSessionID)
    }

    private func deleteSession(id: Session.ID) async {
        sessionsViewModel.selectedSessionID = id
        await sessionsViewModel.deleteSelected()
        synchronizeSelectionAfterSessionReload(preferredSessionID: sessionsViewModel.selectedSessionID)
    }

    private func reloadSessionsFromSidebarBanner() async {
        await sessionsViewModel.load()
        synchronizeSelectionAfterSessionReload(
            preferredSessionID: sessionsViewModel.selectedSessionID
        )
    }

    private func beginRenameForSelectedSession() {
        guard let session = selectedSession else { return }
        beginRename(session)
    }

    private func beginRename(_ session: Session) {
        renameSessionID = session.id
        renameDraft = session.metadata.title
    }

    private func cancelRename() {
        renameSessionID = nil
        renameDraft = ""
    }

    private func commitRename() {
        guard let id = renameSessionID else { return }
        let title = renameDraft
        cancelRename()

        Task {
            await sessionsViewModel.renameSession(id: id, to: title)
            synchronizeSelectionAfterSessionReload(preferredSessionID: id)
        }
    }

    private var selectedCollectionSession: Session? {
        sessionsViewModel.session(for: collectionSessionID)
    }

    private func beginCollectionEdit(_ session: Session) {
        collectionSessionID = session.id
        collectionDraft = session.metadata.collectionName ?? ""
    }

    private func cancelCollectionEdit() {
        collectionSessionID = nil
        collectionDraft = ""
    }

    private func commitCollectionEdit() {
        guard let id = collectionSessionID else { return }
        let name = collectionDraft
        cancelCollectionEdit()

        Task {
            await sessionsViewModel.updateCollection(id: id, name: name)
            synchronizeSelectionAfterSessionReload(preferredSessionID: id)
        }
    }

    private func clearCollection() {
        guard let id = collectionSessionID else { return }
        cancelCollectionEdit()

        Task {
            await sessionsViewModel.updateCollection(id: id, name: nil)
            synchronizeSelectionAfterSessionReload(preferredSessionID: id)
        }
    }

    private func synchronizeSelectionAfterSessionReload(
        preferredSessionID: Session.ID?,
        forceSessionSelection: Bool = true
    ) {
        if !forceSessionSelection,
           case .destination(let destination)? = selectedSidebarSelection,
           destination != .sessions {
            return
        }

        if let preferredSessionID,
           sessionsViewModel.session(for: preferredSessionID) != nil {
            sessionsViewModel.selectedSessionID = preferredSessionID
            selectedSidebarSelection = .session(preferredSessionID)
            return
        }

        if let existingSelection = selectedSessionID,
           sessionsViewModel.session(for: existingSelection) != nil {
            sessionsViewModel.selectedSessionID = existingSelection
            selectedSidebarSelection = .session(existingSelection)
            return
        }

        if let first = sessionsViewModel.activeSessions.first ?? sessionsViewModel.sessions.first {
            sessionsViewModel.selectedSessionID = first.id
            selectedSidebarSelection = .session(first.id)
            return
        }

        sessionsViewModel.selectedSessionID = nil
        selectedSidebarSelection = .destination(.models)
    }

    private func exportSelectedSession() async {
        guard let session = selectedSession else { return }

        do {
            let messages = try await store.loadMessages(sessionID: session.id)
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
        if let collectionName = session.metadata.collectionName {
            lines.append("Collection: \(collectionName)")
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

    private var statusPillButton: some View {
        Button {
            isShowingStatusPopover.toggle()
        } label: {
            Image(systemName: statusViewModel.displayedReadiness.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusViewModel.displayedReadiness.tintColor)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help("Loom Status")
        .accessibilityLabel("Loom status: \(statusViewModel.displayedReadiness.label)")
        .popover(isPresented: $isShowingStatusPopover, arrowEdge: .bottom) {
            LoomStatusPopoverView(
                viewModel: statusViewModel,
                browseModels: {
                    selectedSidebarSelection = .destination(.models)
                    isShowingStatusPopover = false
                }
            )
        }
    }
}

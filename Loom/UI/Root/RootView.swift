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
                url: URL(string: "https://www.llama.com")!
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
                .font(.title3.weight(.semibold))

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
                .font(.headline)

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
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Makers In Loom")
                .font(.headline)

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
                .font(.headline)

            Text("Official references for each company involved in this stack:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(citations) { citation in
                VStack(alignment: .leading, spacing: 3) {
                    Text(citation.company)
                        .font(.subheadline.weight(.semibold))
                    Text(citation.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link(citation.url.absoluteString, destination: citation.url)
                        .font(.caption.monospaced())
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
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            Rectangle()
                .fill(LoomTheme.backgroundGradient(colorScheme))
                .opacity(colorScheme == .dark ? 0.30 : 0.44)
                .ignoresSafeArea()

            Circle()
                .fill(LoomTheme.accentGradient(colorScheme).opacity(colorScheme == .dark ? 0.24 : 0.20))
                .frame(width: 520, height: 520)
                .blur(radius: 120)
                .offset(x: -290, y: -260)
                .allowsHitTesting(false)

            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.25))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: 320, y: -220)
                .allowsHitTesting(false)

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
                            Label("New Session", systemImage: "plus")
                        }
                        .accessibilityIdentifier("sessions.toolbar.new")

                        Button {
                            beginRenameForSelectedSession()
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .accessibilityIdentifier("sessions.toolbar.rename")
                        .disabled(selectedSession == nil)

                        Button {
                            Task { @MainActor in
                                await exportSelectedSession()
                            }
                        } label: {
                            Label("Export Session", systemImage: "square.and.arrow.up")
                        }
                        .disabled(selectedSession == nil)

                        Button(role: .destructive) {
                            Task { await deleteSelectedSession() }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("sessions.toolbar.delete")
                        .disabled(selectedSession == nil)
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
        .onDisappear {
            statusViewModel.stopMonitoring()
        }
    }

    private var sidebar: some View {
        List(selection: $selectedSidebarSelection) {
            Section("Sessions") {
                if sessionsViewModel.filteredSessions.isEmpty {
                    Text("No sessions yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(sessionsViewModel.filteredSessions) { session in
                        sessionSidebarRow(session)
                            .tag(SidebarSelection.session(session.id))
                            .contextMenu {
                                Button("Rename") {
                                    beginRename(session)
                                }

                                Button(session.metadata.isPinned ? "Unpin" : "Pin") {
                                    Task { await sessionsViewModel.togglePinned(id: session.id) }
                                }

                                Divider()

                                Button(role: .destructive) {
                                    Task { await deleteSession(id: session.id) }
                                } label: {
                                    Text("Delete")
                                }
                            }
                    }
                }
            }

            Section("System") {
                destinationSidebarRow(.models)
            }

            Section("App") {
                destinationSidebarRow(.info)
                destinationSidebarRow(.status)
                destinationSidebarRow(.settings)
            }
        }
        .searchable(text: $sessionsViewModel.searchQuery, placement: .automatic)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        .navigationTitle("Loom")
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

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Session")
                .font(.headline)

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

    private func destinationSidebarRow(_ item: SidebarItem) -> some View {
        let isSelected = selectedSidebarSelection == .destination(item)

        return Label(item.title, systemImage: item.systemImage)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("sidebar.\(item.id)")
            .loomSidebarItem(selected: isSelected)
            .tag(SidebarSelection.destination(item))
    }

    private func sessionSidebarRow(_ session: Session) -> some View {
        let isSelected = selectedSidebarSelection == .session(session.id)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.metadata.title)
                        .font(.headline)
                        .lineLimit(1)

                    if session.metadata.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(session.metadata.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("sidebar.session.\(session.id.uuidString)")
        .loomSidebarItem(selected: isSelected)
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

        if let first = sessionsViewModel.sessions.first {
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
            HStack(spacing: 6) {
                Image(systemName: statusViewModel.snapshot.readiness.symbolName)
                    .font(.caption.bold())
                    .foregroundStyle(statusViewModel.snapshot.readiness.tintColor)
                Text("Loom")
                    .font(.subheadline.weight(.semibold))
                Text(statusViewModel.snapshot.readiness.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusViewModel.snapshot.readiness.tintColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
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

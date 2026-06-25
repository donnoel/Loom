import AppKit
import SwiftUI

struct WorkspaceView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var vm = WorkspaceViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerCard
            if vm.sessions.isEmpty {
                emptyWorkspaceCard
            } else {
                workspaceSelectionRow
                workspaceControls

                HStack(alignment: .top, spacing: 14) {
                    transcriptCard

                    VStack(alignment: .leading, spacing: 14) {
                        toolActivityCard
                        changesCard
                    }
                    .frame(minWidth: 340, idealWidth: 360, maxWidth: 380, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("screen.workspace")
        .navigationTitle("LoomX")
        .task {
            await vm.load()
        }
        .onDisappear {
            vm.cancelSend()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("LoomX")
                    .font(LoomTheme.Typography.pageHero)

                Spacer()

                Button {
                    chooseWorkspace()
                } label: {
                    Label("Add LoomX", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("workspace.add")
            }

            if let bannerText = vm.bannerText {
                Text(bannerText)
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
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

    private var emptyWorkspaceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContentUnavailableView("No LoomX Project Selected", systemImage: "folder.badge.gearshape")
                .frame(maxWidth: .infinity, minHeight: 260)
            Button {
                chooseWorkspace()
            } label: {
                Label("Choose LoomX Project", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("workspace.choose")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .loomCard(cornerRadius: 12)
    }

    private var workspaceSelectionRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LoomX Project")
                    .font(LoomTheme.Typography.captionStrong)
                    .foregroundStyle(.secondary)

                Picker("LoomX Project", selection: selectedWorkspaceBinding) {
                    ForEach(vm.sessions) { session in
                        Text(session.displayName).tag(Optional(session.id))
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("workspace.picker")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Provider")
                    .font(LoomTheme.Typography.captionStrong)
                    .foregroundStyle(.secondary)

                Picker("Provider", selection: providerBinding) {
                    ForEach(WorkspaceProviderMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .accessibilityIdentifier("workspace.provider")
            }

            Toggle("Autonomous edits", isOn: autonomousEditsBinding)
                .toggleStyle(.switch)
                .padding(.top, 22)
                .accessibilityIdentifier("workspace.autonomousEdits")

            Spacer(minLength: 0)

            Button(role: .destructive) {
                Task { await vm.deleteSelectedWorkspace() }
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove LoomX project")
            .buttonStyle(.bordered)
            .disabled(vm.selectedSession == nil)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var workspaceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let session = vm.selectedSession {
                Text(session.rootPath)
                    .font(LoomTheme.Typography.monospacedFootnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project")
                        .font(LoomTheme.Typography.captionStrong)
                        .foregroundStyle(.secondary)
                    if vm.availableProjects.isEmpty {
                        Text("No Xcode project found")
                            .font(LoomTheme.Typography.body)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Project", selection: selectedProjectBinding) {
                            ForEach(vm.availableProjects, id: \.relativePath) { project in
                                Text(project.relativePath).tag(project.relativePath)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("workspace.project")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Scheme")
                        .font(LoomTheme.Typography.captionStrong)
                        .foregroundStyle(.secondary)
                    if vm.availableSchemes.isEmpty {
                        Text("Run readiness check")
                            .font(LoomTheme.Typography.body)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Scheme", selection: selectedSchemeBinding) {
                            ForEach(vm.availableSchemes, id: \.self) { scheme in
                                Text(scheme).tag(scheme)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("workspace.scheme")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Destination")
                        .font(LoomTheme.Typography.captionStrong)
                        .foregroundStyle(.secondary)
                    TextField("Optional destination", text: $vm.destinationDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task { await vm.updateDestination(vm.destinationDraft) }
                        }
                        .accessibilityIdentifier("workspace.destination")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await vm.runReadinessCheck() }
                } label: {
                    Label("Check", systemImage: "checkmark.seal")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("workspace.check")

                Button {
                    Task { await vm.buildSelectedWorkspace() }
                } label: {
                    Label("Build", systemImage: "hammer")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("workspace.build")

                Button {
                    Task { await vm.testSelectedWorkspace() }
                } label: {
                    Label("Test", systemImage: "testtube.2")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("workspace.test")

                Button {
                    Task { await vm.openSelectedWorkspaceInXcode() }
                } label: {
                    Label("Xcode", systemImage: "curlybraces.square")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("workspace.openXcode")

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Chat")
                    .font(LoomTheme.Typography.sectionTitle)
                Spacer()
                if vm.isSending {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if vm.messages.isEmpty {
                            Text("No LoomX messages yet")
                                .font(LoomTheme.Typography.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                        } else {
                            ForEach(vm.messages) { message in
                                messageRow(message)
                                    .id(message.id)
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("workspace.chat.bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: vm.messages.map(\.id)) {
                    scrollWorkspaceChatToBottom(proxy)
                }
                .task {
                    scrollWorkspaceChatToBottom(proxy)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $vm.draft)
                        .font(LoomTheme.Typography.body)
                        .frame(minHeight: 76, maxHeight: 112)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .disabled(vm.isSending)
                        .accessibilityIdentifier("workspace.prompt")

                    if vm.draft.isEmpty {
                        Text("Ask LoomX to inspect, edit, build, or test this project")
                            .font(LoomTheme.Typography.body)
                            .foregroundStyle(LoomTheme.inputPlaceholder(colorScheme))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )

                HStack(spacing: 10) {
                    Button {
                        vm.sendDraft()
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isSending || vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("workspace.send")

                    if vm.isSending {
                        Button {
                            vm.cancelSend()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .loomCard(cornerRadius: 12)
    }

    private var toolActivityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tool Activity")
                .font(LoomTheme.Typography.sectionTitle)

            if vm.toolEvents.isEmpty {
                Text("No tool activity yet")
                    .font(LoomTheme.Typography.body)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(vm.toolEvents.prefix(24)) { event in
                            toolEventRow(event)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160, maxHeight: 280)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var changesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Changes")
                    .font(LoomTheme.Typography.sectionTitle)
                Spacer()
                Button {
                    Task { await vm.refreshGitDiff() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh diff")
                .buttonStyle(.bordered)
                .disabled(vm.isRefreshingDiff)
            }

            if vm.changeRecords.isEmpty {
                Text("No saved edit patches yet")
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(vm.changeRecords.count) saved edit patch\(vm.changeRecords.count == 1 ? "" : "es")")
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView([.horizontal, .vertical]) {
                Text(vm.gitDiffText.nonEmptyTrimmed ?? "No uncommitted diff.")
                    .font(LoomTheme.Typography.monospacedCaption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 140, maxHeight: 260)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            Text(message.content)
                .textSelection(.enabled)
                .loomBubble(role: message.role)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(isUser ? "You" : "LoomX"): \(message.content)")
                .accessibilityIdentifier(isUser ? "workspace.message.user.bubble" : "workspace.message.assistant.bubble")
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.vertical, 3)
    }

    private func toolEventRow(_ event: DeveloperToolResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.status == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(event.status == .success ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.tool.title)
                    .font(LoomTheme.Typography.bodyStrong)
                Text(event.summary)
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                if let output = event.output.nonEmptyTrimmed {
                    Text(output)
                        .font(LoomTheme.Typography.monospacedCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedWorkspaceBinding: Binding<WorkspaceSession.ID?> {
        Binding(
            get: { vm.selectedSessionID },
            set: { id in
                guard let id else { return }
                Task { await vm.selectSession(id: id) }
            }
        )
    }

    private var providerBinding: Binding<WorkspaceProviderMode> {
        Binding(
            get: { vm.providerMode },
            set: { mode in
                Task { await vm.setProviderMode(mode) }
            }
        )
    }

    private var autonomousEditsBinding: Binding<Bool> {
        Binding(
            get: { vm.selectedSession?.allowsAutonomousEdits ?? false },
            set: { value in
                Task { await vm.setAutonomousEditsEnabled(value) }
            }
        )
    }

    private var selectedProjectBinding: Binding<String> {
        Binding(
            get: { vm.selectedSession?.selectedProject?.relativePath ?? "" },
            set: { relativePath in
                Task { await vm.selectProject(relativePath: relativePath) }
            }
        )
    }

    private var selectedSchemeBinding: Binding<String> {
        Binding(
            get: { vm.selectedSession?.selectedScheme ?? "" },
            set: { scheme in
                Task { await vm.selectScheme(scheme) }
            }
        )
    }

    private func scrollWorkspaceChatToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("workspace.chat.bottom", anchor: .bottom)
            }
        }
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a code folder for LoomX."

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        Task {
            await vm.addWorkspace(rootURL: url, bookmarkData: bookmarkData)
        }
    }
}

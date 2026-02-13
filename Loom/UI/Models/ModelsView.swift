import AppKit
import SwiftUI

struct ModelsView: View {
    let onModelSelectionChanged: () async -> Void

    @State private var viewModel: ModelsViewModel
    @State private var isShowingServeHelp: Bool = false
    @State private var isShowingAddModelSheet: Bool = false
    @State private var didCopyCommand: Bool = false

    init(onModelSelectionChanged: @escaping () async -> Void) {
        self.onModelSelectionChanged = onModelSelectionChanged
        _viewModel = State(initialValue: ModelsViewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topStatusCard
                statusDetailsCard
                if let warning = viewModel.lowDiskSpaceWarningText {
                    lowDiskWarningBanner(warning)
                }
                addModelCard
                modelsSection
                privacyFooter
            }
            .padding(24)
        }
        .accessibilityIdentifier("screen.models")
        .navigationTitle("Model Library")
        .task {
            viewModel.startMonitoring()
            await viewModel.refresh()
            await onModelSelectionChanged()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .sheet(isPresented: $isShowingServeHelp) {
            serveHelpSheet
        }
        .sheet(isPresented: $isShowingAddModelSheet) {
            AddModelSheet(viewModel: viewModel)
                .frame(minWidth: 680, minHeight: 540)
        }
        .confirmationDialog(
            "Delete model?",
            isPresented: isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if viewModel.selectedModelToDelete != nil {
                Button("Delete", role: .destructive) {
                    Task {
                        let didDelete = await viewModel.confirmDelete()
                        if didDelete {
                            await onModelSelectionChanged()
                        }
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                viewModel.cancelDeleteRequest()
            }
        } message: {
            if let modelTag = viewModel.selectedModelToDelete {
                Text("This will remove '\(modelTag)' from your Mac and free up disk space.")
            }
        }
        .alert("Can't Delete Model", isPresented: isShowingDeleteAlert) {
            Button("OK", role: .cancel) {
                viewModel.dismissDeleteAlert()
            }
        } message: {
            Text(viewModel.deleteAlertMessage ?? "")
        }
        .alert("Couldn't Check Updates", isPresented: isShowingUpdateAlert) {
            Button("OK", role: .cancel) {
                viewModel.dismissUpdateError()
            }
        } message: {
            Text(viewModel.updateErrorMessage ?? "")
        }
    }

    private var topStatusCard: some View {
        let snapshot = viewModel.statusSnapshot

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: snapshot.readiness.symbolName)
                    .foregroundStyle(snapshot.readiness.tintColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Library")
                        .font(.title3.weight(.semibold))
                    Text(snapshot.readiness.label)
                        .foregroundStyle(.secondary)
                }
            }

            Text(statusSummaryText)
                .foregroundStyle(.secondary)

            if let lastUpdateCheckAt = viewModel.lastUpdateCheckAt {
                Text("Last update check: \(lastUpdateCheckAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if !viewModel.isRunning {
                    Button(viewModel.isInstalled ? "Start Ollama" : "Install Ollama…") {
                        handleOpenOrInstall()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(viewModel.isCheckingUpdates ? "Checking…" : "Check for Updates") {
                    Task {
                        await viewModel.checkForUpdates()
                        await onModelSelectionChanged()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!canCheckForUpdates)

                Button("Refresh") {
                    Task {
                        await viewModel.refresh()
                        await onModelSelectionChanged()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRefreshing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .loomCard(cornerRadius: 12)
    }

    private var statusDetailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)
            LoomStatusLinesView(snapshot: viewModel.statusSnapshot)
        }
    }

    private func lowDiskWarningBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .loomCard(cornerRadius: 10)
    }

    private var addModelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a model")
                .font(.headline)

            Text("Browse recommended models with friendly descriptions and install them in Loom.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Add Model…") {
                    isShowingAddModelSheet = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isRunning)

                if !viewModel.isRunning {
                    Text("Start Ollama to install models.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .loomCard(cornerRadius: 12)
    }

    @ViewBuilder
    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Installed models")
                    .font(.headline)

                Spacer()

                if !viewModel.models.isEmpty {
                    Text("Total space used: \(viewModel.totalInstalledSizeText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isRunning && viewModel.models.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No models installed yet.")
                        .foregroundStyle(.secondary)
                    Button("Add Model…") {
                        isShowingAddModelSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
            } else if !viewModel.models.isEmpty {
                VStack(spacing: 8) {
                    ForEach(viewModel.models) { model in
                        modelRow(model)
                    }
                }
            } else {
                Text("Start Ollama to load models.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    private func modelRow(_ model: OllamaModel) -> some View {
        let catalogModel = viewModel.catalogModel(for: model.tag)
        let isActiveModel = model.tag == viewModel.activeModelTag

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(catalogModel?.displayName ?? model.tag)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(viewModel.installedModelCompanyCountryText(for: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(viewModel.installedModelBestForText(for: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if let sizeText = viewModel.installedSizeText(tag: model.tag) {
                        Text("Size \(sizeText)")
                    }

                    if let parameterSize = viewModel.parameterSizeText(for: model) {
                        Text("Parameters \(parameterSize)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let modifiedAt = model.modifiedAt {
                    Text("Updated \(modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                updateStatusBadge(for: model)

                HStack(spacing: 8) {
                    Button(isActiveModel ? "In Use" : "Use") {
                        viewModel.setActiveModel(tag: model.tag)
                        Task { await onModelSelectionChanged() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isActiveModel)

                    Button(updateButtonTitle(for: model)) {
                        Task {
                            let didUpdate = await viewModel.updateInstalledModel(tag: model.tag)
                            if didUpdate {
                                await onModelSelectionChanged()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canStartUpdate(model))

                    Button {
                        viewModel.requestDelete(modelTag: model.tag)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Delete model")
                    .disabled(viewModel.isDeletingModel)
                }
            }
            .frame(minWidth: 230, alignment: .trailing)
        }
        .frame(minHeight: 110)
        .padding(12)
        .background {
            if isActiveModel {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(0.18),
                                Color.mint.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .loomCard(cornerRadius: 10)
        .overlay {
            if isActiveModel {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.32), lineWidth: 1)
            }
        }
        .contextMenu {
            Button("Update") {
                Task {
                    let didUpdate = await viewModel.updateInstalledModel(tag: model.tag)
                    if didUpdate {
                        await onModelSelectionChanged()
                    }
                }
            }
            .disabled(!canStartUpdate(model))

            Button("Delete…", role: .destructive) {
                viewModel.requestDelete(modelTag: model.tag)
            }
        }
    }

    private var privacyFooter: some View {
        Text("Models and chats stay on this Mac.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private var statusSummaryText: String {
        if viewModel.isRunning {
            let activeModel = viewModel.activeModelTag ?? "None selected"
            return "\(viewModel.models.count) installed. Active model: \(activeModel)."
        }

        if viewModel.isInstalled {
            return "Ollama is installed but not running. Start Ollama to manage models."
        }

        return "Install Ollama once, then choose a model and keep it updated from this screen."
    }

    private var canCheckForUpdates: Bool {
        viewModel.isRunning
            && !viewModel.models.isEmpty
            && !viewModel.isCheckingUpdates
            && viewModel.installingTag == nil
    }

    @ViewBuilder
    private func updateStatusBadge(for model: OllamaModel) -> some View {
        if viewModel.updatingTag == model.tag {
            statusBadge(
                title: "Checking…",
                foreground: .secondary,
                background: .secondary.opacity(0.14)
            )
        } else if viewModel.isModelCurrent(tag: model.tag) {
            statusBadge(
                title: "Current",
                foreground: .green,
                background: .green.opacity(0.14)
            )
        } else {
            statusBadge(
                title: "Update",
                foreground: .orange,
                background: .orange.opacity(0.16)
            )
        }
    }

    private func statusBadge(title: String, foreground: Color, background: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }

    private func updateButtonTitle(for model: OllamaModel) -> String {
        if viewModel.updatingTag == model.tag {
            return "Checking…"
        }
        if viewModel.isModelCurrent(tag: model.tag) {
            return "Current"
        }
        return "Update"
    }

    private func canStartUpdate(_ model: OllamaModel) -> Bool {
        guard !viewModel.isModelCurrent(tag: model.tag) else { return false }
        return canUpdate(model)
    }

    private func canUpdate(_ model: OllamaModel) -> Bool {
        guard viewModel.isRunning else { return false }
        guard viewModel.installingTag == nil else { return false }
        guard !viewModel.isCheckingUpdates else { return false }
        guard viewModel.isModelInstalled(tag: model.tag) else { return false }
        return viewModel.updatingTag == nil || viewModel.updatingTag == model.tag
    }

    private var serveHelpSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start Ollama from Terminal")
                .font(.title3.weight(.semibold))
            Text("If you installed Ollama with Homebrew, run this command:")
                .foregroundStyle(.secondary)

            HStack {
                Text("ollama serve")
                    .font(.system(.body, design: .monospaced))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

                Spacer()

                Button(didCopyCommand ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("ollama serve", forType: .string)
                    didCopyCommand = true
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button("Open download page") {
                    viewModel.openDownloadPage()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Done") {
                    isShowingServeHelp = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func handleOpenOrInstall() {
        didCopyCommand = false

        switch viewModel.openOrInstallOllama() {
        case .opened:
            break
        case .showServeHelp:
            isShowingServeHelp = true
        }
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { viewModel.selectedModelToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelDeleteRequest()
                }
            }
        )
    }

    private var isShowingDeleteAlert: Binding<Bool> {
        Binding(
            get: { viewModel.deleteAlertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissDeleteAlert()
                }
            }
        )
    }

    private var isShowingUpdateAlert: Binding<Bool> {
        Binding(
            get: { viewModel.updateErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissUpdateError()
                }
            }
        )
    }
}

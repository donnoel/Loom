import AppKit
import SwiftUI

struct ModelsView: View {
    let onModelSelectionChanged: () async -> Void

    @State private var viewModel: ModelsViewModel
    @State private var isShowingServeHelp: Bool = false
    @State private var didCopyCommand: Bool = false

    init(onModelSelectionChanged: @escaping () async -> Void) {
        self.onModelSelectionChanged = onModelSelectionChanged
        _viewModel = State(initialValue: ModelsViewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topStatusCard
                diskSpaceCard
                if let warning = viewModel.lowDiskSpaceWarningText {
                    lowDiskWarningBanner(warning)
                }
                modelsSection
                privacyFooter
            }
            .padding(24)
        }
        .accessibilityIdentifier("screen.models")
        .navigationTitle("Models")
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
    }

    private var topStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isRunning {
                Text("Loom can use local models.")
                    .font(.title3.weight(.semibold))
                Text("Choose an active model below.")
                    .foregroundStyle(.secondary)
            } else if viewModel.isInstalled {
                Text("Ollama is installed but not running.")
                    .font(.title3.weight(.semibold))
                Text("Start Ollama, then refresh to load your models.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Start Ollama") {
                        handleOpenOrInstall()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refresh") {
                        Task {
                            await viewModel.refresh()
                            await onModelSelectionChanged()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRefreshing)
                }
            } else {
                Text("Ollama is not installed yet.")
                    .font(.title3.weight(.semibold))
                Text("Install it once, then come back and pick a model.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Install Ollama…") {
                        handleOpenOrInstall()
                    }
                    .buttonStyle(.borderedProminent)

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
        }
        .padding(16)
        .loomCard(cornerRadius: 12)
    }

    private var diskSpaceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Disk")
                .font(.headline)
            Text(viewModel.diskFreeSpaceText)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .padding(14)
        .loomCard(cornerRadius: 12)
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

    @ViewBuilder
    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Installed models")
                .font(.headline)

            if viewModel.isRunning && viewModel.models.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No models installed yet.")
                        .foregroundStyle(.secondary)
                    Link("Browse model library", destination: URL(string: "https://ollama.com/library")!)
                        .font(.subheadline)
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
        HStack(spacing: 12) {
            Text(model.tag)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            if model.tag == viewModel.activeModelTag {
                Text("Active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.12), in: Capsule())
            }

            Button(model.tag == viewModel.activeModelTag ? "In Use" : "Use") {
                viewModel.setActiveModel(tag: model.tag)
                Task { await onModelSelectionChanged() }
            }
            .buttonStyle(.bordered)
            .disabled(model.tag == viewModel.activeModelTag)

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
        .padding(12)
        .loomCard(cornerRadius: 10)
        .contextMenu {
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
}

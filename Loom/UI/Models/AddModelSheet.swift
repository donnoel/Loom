import Observation
import SwiftUI

struct AddModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ModelsViewModel

    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    diskSpaceCard

                    if let warning = viewModel.lowDiskSpaceWarningText {
                        lowDiskWarningBanner(warning)
                    }

                    modelsSection(title: "Recommended", models: filteredRecommendedModels)
                    modelsSection(title: "All Models", models: filteredOtherModels)
                }
                .padding(20)
            }
            .navigationTitle("Add Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search models")
        .alert("Low disk space", isPresented: isShowingLowSpaceAlert) {
            Button("Continue", role: .destructive) {
                viewModel.continueInstallAfterLowSpaceConfirmation()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelLowSpaceInstallRequest()
            }
        } message: {
            Text("Less than 10% of disk space is free. Installing may fail.")
        }
        .alert("Install Failed", isPresented: isShowingInstallErrorAlert) {
            Button("OK", role: .cancel) {
                viewModel.dismissInstallError()
            }
        } message: {
            Text(viewModel.installErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private func modelsSection(title: String, models: [CatalogModel]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            if models.isEmpty {
                Text(emptyStateText(for: title))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(models) { model in
                        modelRow(model)
                    }
                }
            }
        }
    }

    private var diskSpaceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Disk")
                .font(.headline)
            Text(viewModel.diskFreeSpaceText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .loomCard(cornerRadius: 10)
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

    private func modelRow(_ model: CatalogModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)

                    HStack(spacing: 8) {
                        Text(model.vendor)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(model.tag)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Text(model.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text("Best at: \(model.bestAt.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let sizeText = viewModel.catalogSizeText(model: model) {
                        Text(sizeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 10)

                installControl(for: model)
            }

            if let notes = model.notes?.nonEmptyTrimmed {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .loomCard(cornerRadius: 10)
    }

    @ViewBuilder
    private func installControl(for model: CatalogModel) -> some View {
        if viewModel.isModelInstalled(tag: model.tag) {
            Text("Installed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.12), in: Capsule())
        } else if viewModel.installingTag == model.tag {
            VStack(alignment: .trailing, spacing: 6) {
                if let fraction = viewModel.pullProgress(for: model.tag)?.fraction {
                    ProgressView(value: fraction)
                        .frame(width: 120)
                } else {
                    ProgressView()
                        .frame(width: 120)
                }

                Text(viewModel.pullProgress(for: model.tag)?.status ?? "Installing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button("Cancel") {
                    viewModel.cancelInstall()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .frame(minWidth: 120, alignment: .trailing)
        } else {
            Button("Install") {
                viewModel.beginInstall(tag: model.tag)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isRunning || !viewModel.canInstallModel(tag: model.tag))
        }
    }

    private var filteredRecommendedModels: [CatalogModel] {
        viewModel.recommendedCatalogModels.filter(matchesSearch)
    }

    private var filteredOtherModels: [CatalogModel] {
        viewModel.catalogModels
            .filter { !$0.recommended }
            .filter(matchesSearch)
    }

    private var normalizedSearchText: String? {
        searchText.nonEmptyTrimmed?.lowercased()
    }

    private func matchesSearch(_ model: CatalogModel) -> Bool {
        guard let normalizedSearchText else { return true }

        let bestAtText = model.bestAt.joined(separator: " ")
        let searchableText = [
            model.displayName,
            model.tag,
            model.vendor,
            model.summary,
            bestAtText,
            model.notes ?? ""
        ].joined(separator: " ").lowercased()

        return searchableText.contains(normalizedSearchText)
    }

    private func emptyStateText(for sectionTitle: String) -> String {
        if searchText.nonEmptyTrimmed != nil {
            return "No matching models found."
        }

        if sectionTitle == "Recommended" {
            return "No recommended models available right now."
        }

        return "No models available."
    }

    private var isShowingLowSpaceAlert: Binding<Bool> {
        Binding(
            get: { viewModel.pendingLowSpaceInstallTag != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelLowSpaceInstallRequest()
                }
            }
        )
    }

    private var isShowingInstallErrorAlert: Binding<Bool> {
        Binding(
            get: { viewModel.installErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissInstallError()
                }
            }
        )
    }
}

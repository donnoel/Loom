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

                    modelsSection(title: "Available", models: filteredRecommendedModels)
                    modelsSection(title: "", models: filteredOtherModels)
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
            if let sectionTitle = title.nonEmptyTrimmed {
                Text(sectionTitle)
                    .font(LoomTheme.Typography.sectionTitle)
            }

            if models.isEmpty {
                Text(emptyStateText(for: title))
                    .font(LoomTheme.Typography.body)
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
                .font(LoomTheme.Typography.sectionTitle)
            Text(viewModel.diskFreeSpaceText)
                .font(LoomTheme.Typography.body)
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
                .font(LoomTheme.Typography.body)
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
                        .font(LoomTheme.Typography.bodyStrong)

                    HStack(spacing: 8) {
                        Text(model.vendor)
                            .font(LoomTheme.Typography.caption)
                            .foregroundStyle(.secondary)

                        Text(model.tag)
                            .font(LoomTheme.Typography.monospacedCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Text(model.summary)
                        .font(LoomTheme.Typography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text("Best at: \(model.bestAt.joined(separator: ", "))")
                        .font(LoomTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(viewModel.catalogModelCapabilitiesText(for: model))
                        .font(LoomTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let sizeText = viewModel.catalogSizeText(model: model) {
                        Text(sizeText)
                            .font(LoomTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 10)

                installControl(for: model)
            }

            if let notes = model.notes?.nonEmptyTrimmed {
                Text(notes)
                    .font(LoomTheme.Typography.caption)
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
                .font(LoomTheme.Typography.captionStrong)
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
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button("Cancel") {
                    viewModel.cancelInstall()
                }
                .buttonStyle(.borderless)
                .font(LoomTheme.Typography.caption)
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

        if sectionTitle == "Available" {
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

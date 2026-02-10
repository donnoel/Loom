import SwiftUI

struct ModelsView: View {
    let openOrInstallOllama: () -> Void
    let ollamaActionTitle: String
    let onModelSelectionChanged: () async -> Void

    @State private var viewModel: ModelsViewModel

    init(
        openOrInstallOllama: @escaping () -> Void,
        ollamaActionTitle: String,
        onModelSelectionChanged: @escaping () async -> Void
    ) {
        self.openOrInstallOllama = openOrInstallOllama
        self.ollamaActionTitle = ollamaActionTitle
        self.onModelSelectionChanged = onModelSelectionChanged
        _viewModel = State(initialValue: ModelsViewModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Models")
                .font(.largeTitle.bold())

            Text("Pick a model for Loom. Everything stays on your Mac.")
                .foregroundStyle(.secondary)

            if viewModel.ollamaReachable {
                modelsContent
            } else {
                unreachableContent
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .task {
            await viewModel.refresh()
            await onModelSelectionChanged()
        }
    }

    @ViewBuilder
    private var modelsContent: some View {
        if viewModel.models.isEmpty {
            ContentUnavailableView("No Models Installed", systemImage: "cube.box")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("Installed models (\(viewModel.models.count))")
                .font(.headline)

            List(viewModel.models) { model in
                Button {
                    viewModel.selectModel(model)
                    Task { await onModelSelectionChanged() }
                } label: {
                    HStack {
                        Text(model.tag)
                        Spacer()
                        if model.tag == viewModel.activeModelTag {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var unreachableContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ollama isn’t running.")
                .font(.headline)
            Text("Start Ollama to see your installed models.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(ollamaActionTitle) {
                    openOrInstallOllama()
                }
                .buttonStyle(.borderedProminent)

                Button("Try again") {
                    Task {
                        await viewModel.refresh()
                        await onModelSelectionChanged()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

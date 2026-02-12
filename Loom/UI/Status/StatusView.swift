import SwiftUI

struct StatusView: View {
    let viewModel: StatusViewModel
    let browseModels: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.snapshot.readiness.symbolName)
                        .foregroundStyle(viewModel.snapshot.readiness.tintColor)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Loom Ready")
                            .font(.title2.weight(.semibold))
                        Text(viewModel.snapshot.readiness.label)
                            .foregroundStyle(.secondary)
                    }
                }

                LoomStatusLinesView(snapshot: viewModel.snapshot)

                HStack(spacing: 10) {
                    primaryAction
                    Button("Refresh") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRefreshing)
                }
            }
            .padding(24)
        }
        .accessibilityIdentifier("screen.status")
        .navigationTitle("Status")
    }

    @ViewBuilder
    private var primaryAction: some View {
        if !viewModel.snapshot.ollamaReachable {
            Button(viewModel.ollamaActionTitle) {
                viewModel.openOrInstallOllama()
            }
            .buttonStyle(.borderedProminent)
        } else if viewModel.snapshot.installedModelCount == 0 {
            Button("Browse Models") {
                browseModels()
            }
            .buttonStyle(.borderedProminent)
        } else if viewModel.snapshot.activeModelTag == nil {
            Button("Select model") {
                browseModels()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct LoomStatusPopoverView: View {
    let viewModel: StatusViewModel
    let browseModels: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.snapshot.readiness.symbolName)
                    .foregroundStyle(viewModel.snapshot.readiness.tintColor)
                Text("Loom Ready")
                    .font(.headline)
                Spacer()
                Text(viewModel.snapshot.readiness.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.snapshot.readiness.tintColor)
            }

            LoomStatusLinesView(snapshot: viewModel.snapshot)

            HStack(spacing: 10) {
                popoverPrimaryAction
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRefreshing)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private var popoverPrimaryAction: some View {
        if !viewModel.snapshot.ollamaReachable {
            Button(viewModel.ollamaActionTitle) {
                viewModel.openOrInstallOllama()
            }
            .buttonStyle(.borderedProminent)
        } else if viewModel.snapshot.installedModelCount == 0 {
            Button("Browse Models") {
                browseModels()
            }
            .buttonStyle(.borderedProminent)
        } else if viewModel.snapshot.activeModelTag == nil {
            Button("Select model") {
                browseModels()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct LoomStatusLinesView: View {
    let snapshot: LoomStatusSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            line("Ollama", snapshot.ollamaReachable ? "Running" : "Not running")
            line(
                "Models",
                snapshot.installedModelCount > 0
                    ? "Installed (\(snapshot.installedModelCount))"
                    : "None installed"
            )
            line("Active model", snapshot.activeModelTag ?? "Not selected")
            line("Offline", snapshot.offlineAvailable ? "Available" : "Not available")
            line("Disk", diskSummaryText)

            if let warning = snapshot.lowDiskSpaceWarning {
                Text(warning)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .loomCard(cornerRadius: 10)
    }

    @ViewBuilder
    private func line(_ title: String, _ value: String) -> some View {
        HStack {
            Text("\(title):")
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }

    private var diskSummaryText: String {
        guard let disk = snapshot.diskSpace else { return "Unavailable" }
        return "\(DiskSpaceSnapshot.formattedBytes(disk.availableBytes)) free (\(disk.availablePercentDisplay))"
    }
}

extension LoomReadiness {
    var tintColor: Color {
        switch self {
        case .ready: .green
        case .needsSetup: .yellow
        case .notReady: .red
        }
    }

    var symbolName: String {
        switch self {
        case .ready: "checkmark.seal.fill"
        case .needsSetup: "exclamationmark.triangle.fill"
        case .notReady: "xmark.octagon.fill"
        }
    }
}

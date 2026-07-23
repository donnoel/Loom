import SwiftUI

struct LoomStatusPopoverView: View {
    let viewModel: StatusViewModel
    let browseModels: () -> Void

    var body: some View {
        let readiness = viewModel.displayedReadiness

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: readiness.symbolName)
                    .foregroundStyle(readiness.tintColor)
                Text("Loom Ready")
                    .font(LoomTheme.Typography.sectionTitle)
                Spacer()
                Text(readiness.label)
                    .font(LoomTheme.Typography.captionStrong)
                    .foregroundStyle(readiness.tintColor)
            }

            LoomStatusLinesView(
                snapshot: viewModel.snapshot,
                isChecking: readiness == .checking
            )

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
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: LoomStatusSnapshot
    var isChecking: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            line("Ollama", isChecking ? "Checking…" : (snapshot.ollamaReachable ? "Running" : "Not running"))
            line(
                "Models",
                isChecking
                    ? "Checking…"
                    : snapshot.installedModelCount > 0
                    ? "Installed (\(snapshot.installedModelCount))"
                    : "None installed"
            )
            line("Active model", isChecking ? "Checking…" : (snapshot.activeModelTag ?? "Not selected"))
            line("Offline", isChecking ? "Checking…" : (snapshot.offlineAvailable ? "Available" : "Not available"))
            line("Disk", isChecking ? "Checking…" : diskSummaryText)

            if !isChecking, let warning = snapshot.lowDiskSpaceWarning {
                Text(warning)
                    .font(LoomTheme.Typography.footnoteStrong)
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
                .foregroundStyle(LoomTheme.textSecondary(colorScheme))
            Spacer()
            Text(value)
        }
        .font(LoomTheme.Typography.body)
    }

    private var diskSummaryText: String {
        guard let disk = snapshot.diskSpace else { return "Unavailable" }
        return "\(DiskSpaceSnapshot.formattedBytes(disk.availableBytes)) free (\(disk.availablePercentDisplay))"
    }
}

extension LoomReadiness {
    var tintColor: Color {
        switch self {
        case .checking: .secondary
        case .ready: .green
        case .needsSetup: .yellow
        case .notReady: .red
        }
    }

    var symbolName: String {
        switch self {
        case .checking: "clock.fill"
        case .ready: "checkmark.seal.fill"
        case .needsSetup: "exclamationmark.triangle.fill"
        case .notReady: "xmark.octagon.fill"
        }
    }
}

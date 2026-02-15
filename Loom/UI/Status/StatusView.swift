import SwiftUI
import UniformTypeIdentifiers

struct LoomStatusPopoverView: View {
    let viewModel: StatusViewModel
    let browseModels: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.snapshot.readiness.symbolName)
                    .foregroundStyle(viewModel.snapshot.readiness.tintColor)
                Text("Loom Ready")
                    .font(LoomTheme.Typography.sectionTitle)
                Spacer()
                Text(viewModel.snapshot.readiness.label)
                    .font(LoomTheme.Typography.captionStrong)
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
                .foregroundStyle(.secondary)
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

struct AIChatbotStatusView: View {
    @State private var viewModel = AIChatbotStatusViewModel()
    @State private var draggingServiceID: String?

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard

                VStack(spacing: 10) {
                    ForEach(viewModel.services) { service in
                        draggableServiceCard(service)
                    }

                    Color.clear
                        .frame(height: 12)
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: AIStatusServiceDropToEndDelegate(
                                draggingServiceID: $draggingServiceID,
                                viewModel: viewModel
                            )
                        )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen.aiStatus")
        .navigationTitle("AI Status")
        .task {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top AI Chatbot Monitor")
                .font(LoomTheme.Typography.pageHero)
            Text("Loom checks official public status feeds for major chatbot services. Refresh any time to see live uptime and known issues.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(viewModel.isRefreshing ? "Refreshing…" : "Refresh") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRefreshing)

                if let lastRefreshAt = viewModel.lastRefreshAt {
                    Text("Last checked \(Self.timestampFormatter.string(from: lastRefreshAt))")
                        .font(LoomTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private func draggableServiceCard(_ service: AIChatbotServiceSnapshot) -> some View {
        serviceCard(service)
            .onDrag {
                draggingServiceID = service.id
                return NSItemProvider(object: service.id as NSString)
            }
            .onDrop(
                of: [UTType.plainText],
                delegate: AIStatusServiceDropDelegate(
                    destinationID: service.id,
                    draggingServiceID: $draggingServiceID,
                    viewModel: viewModel
                )
            )
    }

    private func serviceCard(_ service: AIChatbotServiceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .help("Drag to reorder")

                Text(service.name)
                    .font(LoomTheme.Typography.sectionTitle)

                Spacer()

                Label(service.state.label, systemImage: service.state.symbolName)
                    .font(LoomTheme.Typography.captionStrong)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(service.state.tintColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(service.state.tintColor)
            }

            Text(service.summary)
                .font(LoomTheme.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if service.knownIssues.isEmpty {
                Text("Known issues: none reported right now.")
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Known issues:")
                        .font(LoomTheme.Typography.captionStrong)
                        .foregroundStyle(.secondary)
                    ForEach(service.knownIssues, id: \.self) { issue in
                        Text("• \(issue)")
                            .font(LoomTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 12) {
                Link("Open status page", destination: service.statusPageURL)
                    .font(LoomTheme.Typography.caption)
                Link("Open service", destination: service.homepageURL)
                    .font(LoomTheme.Typography.caption)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }
}

extension AIChatbotOperationalState {
    var tintColor: Color {
        switch self {
        case .operational: .green
        case .degraded: .yellow
        case .outage: .red
        case .unknown: .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .operational: "checkmark.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .outage: "xmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

private struct AIStatusServiceDropDelegate: DropDelegate {
    let destinationID: String
    @Binding var draggingServiceID: String?
    let viewModel: AIChatbotStatusViewModel

    func dropEntered(info: DropInfo) {
        guard let draggingServiceID,
              draggingServiceID != destinationID else { return }
        viewModel.moveService(id: draggingServiceID, before: destinationID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingServiceID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct AIStatusServiceDropToEndDelegate: DropDelegate {
    @Binding var draggingServiceID: String?
    let viewModel: AIChatbotStatusViewModel

    func dropEntered(info: DropInfo) {
        guard let draggingServiceID else { return }
        viewModel.moveServiceToEnd(id: draggingServiceID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingServiceID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

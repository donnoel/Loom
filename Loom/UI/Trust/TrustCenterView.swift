import AppKit
import SwiftUI

private struct TrustCenterLocalSnapshot: Sendable, Equatable {
    let sessionsRootURL: URL?
    let sessionCount: Int
    let totalBytes: Int64
    let metadataBytes: Int64
    let messageLogBytes: Int64
    let retainedAttachmentBytes: Int64

    static let unavailable = TrustCenterLocalSnapshot(
        sessionsRootURL: nil,
        sessionCount: 0,
        totalBytes: 0,
        metadataBytes: 0,
        messageLogBytes: 0,
        retainedAttachmentBytes: 0
    )
}

private actor TrustCenterInspector {
    func loadSnapshot() -> TrustCenterLocalSnapshot {
        guard let sessionsRoot = try? LoomPaths.sessionsRoot() else {
            return TrustCenterLocalSnapshot(
                sessionsRootURL: nil,
                sessionCount: 0,
                totalBytes: 0,
                metadataBytes: 0,
                messageLogBytes: 0,
                retainedAttachmentBytes: 0
            )
        }

        let manager = FileManager.default
        var sessionCount = 0
        var totalBytes: Int64 = 0
        var metadataBytes: Int64 = 0
        var messageLogBytes: Int64 = 0

        if let sessionFolders = try? manager.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for folder in sessionFolders {
                guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey]),
                      values.isDirectory == true,
                      UUID(uuidString: folder.lastPathComponent) != nil else {
                    continue
                }
                sessionCount += 1
            }
        }

        if let enumerator = manager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true else {
                    continue
                }

                let size = Int64(values.fileSize ?? 0)
                totalBytes += size

                switch fileURL.lastPathComponent {
                case "metadata.json":
                    metadataBytes += size
                case "messages.jsonl":
                    messageLogBytes += size
                default:
                    break
                }
            }
        }

        return TrustCenterLocalSnapshot(
            sessionsRootURL: sessionsRoot,
            sessionCount: sessionCount,
            totalBytes: totalBytes,
            metadataBytes: metadataBytes,
            messageLogBytes: messageLogBytes,
            retainedAttachmentBytes: 0
        )
    }
}

struct TrustCenterView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var statusViewModel = StatusViewModel()
    @State private var inspector = TrustCenterInspector()
    @State private var localSnapshot: TrustCenterLocalSnapshot = .unavailable

    private static let healthTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                introCard
                localStorageCard
                attachmentFootprintCard
                runtimeHealthCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen.trustCenter")
        .navigationTitle("Trust Center")
        .task {
            await refreshAll()
            statusViewModel.startMonitoring()
        }
        .onDisappear {
            statusViewModel.stopMonitoring()
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Local-Only Trust Center")
                .font(LoomTheme.Typography.pageHero)

            Text("Loom stores your sessions on this Mac and sends chat requests only to your local Ollama runtime.")
                .foregroundStyle(.secondary)

            Text("No cloud sync is enabled by default, and attachment excerpts are not retained in Loom storage.")
                .font(LoomTheme.Typography.caption)
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

    private var localStorageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data Location")
                .font(LoomTheme.Typography.sectionTitle)

            valueRow("Sessions", value: "\(localSnapshot.sessionCount)")
            valueRow("Total local storage", value: formattedBytes(localSnapshot.totalBytes))
            valueRow("Message logs", value: formattedBytes(localSnapshot.messageLogBytes))
            valueRow("Session metadata", value: formattedBytes(localSnapshot.metadataBytes))

            VStack(alignment: .leading, spacing: 4) {
                Text("Sessions folder")
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                Text(localSnapshot.sessionsRootURL?.path ?? "Unavailable")
                    .font(LoomTheme.Typography.monospacedFootnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Button("Open Sessions Folder") {
                    guard let url = localSnapshot.sessionsRootURL else { return }
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .disabled(localSnapshot.sessionsRootURL == nil)

                Button("Refresh") {
                    Task { await refreshAll() }
                }
                .buttonStyle(.bordered)
                .disabled(statusViewModel.isRefreshing)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var attachmentFootprintCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attachment Footprint")
                .font(LoomTheme.Typography.sectionTitle)

            valueRow("Retained by Loom", value: formattedBytes(localSnapshot.retainedAttachmentBytes))

            Text("Attachments are read at send time for context and not persisted into Loom’s session storage.")
                .font(LoomTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var runtimeHealthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Local Runtime Health")
                .font(LoomTheme.Typography.sectionTitle)

            valueRow("Current readiness", value: statusViewModel.snapshot.readiness.label)
            valueRow("Ollama", value: statusViewModel.snapshot.ollamaReachable ? "Reachable" : "Not reachable")
            valueRow("Installed models", value: "\(statusViewModel.snapshot.installedModelCount)")
            if let warning = statusViewModel.snapshot.lowDiskSpaceWarning {
                Text(warning)
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.orange)
            }

            if !statusViewModel.recentRuntimeHealth.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(statusViewModel.recentRuntimeHealth.suffix(6).reversed())) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.readiness.symbolName)
                                .font(LoomTheme.Typography.captionTinyStrong)
                                .foregroundStyle(entry.readiness.tintColor)

                            Text(Self.healthTimestampFormatter.string(from: entry.checkedAt))
                                .font(LoomTheme.Typography.monospacedCaption)
                                .foregroundStyle(.secondary)

                            Text(entry.readiness.label)
                                .font(LoomTheme.Typography.caption)

                            Spacer(minLength: 0)

                            Text("Models: \(entry.installedModelCount)")
                                .font(LoomTheme.Typography.captionTiny)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    @ViewBuilder
    private func valueRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
        }
        .font(LoomTheme.Typography.body)
    }

    private func refreshAll() async {
        await statusViewModel.refresh()
        localSnapshot = await inspector.loadSnapshot()
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

import SwiftUI
import AppKit

struct SettingsView: View {
    private let store: SessionStore
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(LoomPreferenceKeys.statusAutoRefreshEnabled)
    private var statusAutoRefreshEnabled: Bool = true

    @AppStorage(LoomPreferenceKeys.modelsAutoCheckEnabled)
    private var modelsAutoCheckEnabled: Bool = true

    @State private var isShowingDeleteAllConfirmation: Bool = false

    private var sessionsRootURL: URL? {
        try? LoomPaths.sessionsRoot()
    }

    init(store: SessionStore) {
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                introCard
                automationCard
                localDataCard
                dangerCard
                footerCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen.settings")
        .navigationTitle("Settings")
        .confirmationDialog(
            "Delete all sessions?",
            isPresented: $isShowingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                deleteAllSessions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all local sessions and cannot be undone.")
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.title3.weight(.semibold))

            Text("Control how Loom stays up to date and where your local session data is stored.")
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

    private var automationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automation")
                .font(.headline)

            Toggle("Refresh status automatically", isOn: $statusAutoRefreshEnabled)
            Toggle("Check model availability automatically", isOn: $modelsAutoCheckEnabled)

            Text("Turn these off if you prefer manual refresh while troubleshooting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var localDataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Data & Privacy")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sessions folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(sessionsRootURL?.path ?? "Unavailable")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Open Sessions Folder") {
                guard let url = sessionsRootURL else { return }
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.bordered)
            .disabled(sessionsRootURL == nil)
            .accessibilityIdentifier("settings.openSessionsFolder")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Danger Zone")
                .font(.headline)

            Text("Delete all sessions from this Mac. This cannot be undone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Delete All Sessions…", role: .destructive) {
                isShowingDeleteAllConfirmation = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("settings.deleteAllSessions")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var footerCard: some View {
        Text("More settings are coming soon.")
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .loomCard(cornerRadius: 12)
    }

    private func deleteAllSessions() {
        Task {
            try? await store.deleteAllSessions()
            NotificationCenter.default.post(name: .loomSessionsDidChange, object: nil)
        }
    }
}

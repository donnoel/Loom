import SwiftUI
import AppKit

struct SettingsView: View {
    private let store: SessionStore

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
        Form {
            Section("Automation") {
                Toggle("Refresh status automatically", isOn: $statusAutoRefreshEnabled)
                Toggle("Check model availability automatically", isOn: $modelsAutoCheckEnabled)
            }

            Section("Local Data & Privacy") {
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
                .disabled(sessionsRootURL == nil)

                Button("Delete All Sessions…", role: .destructive) {
                    isShowingDeleteAllConfirmation = true
                }
            }

            Section {
                Text("More settings are coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("screen.settings")
        .formStyle(.grouped)
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

    private func deleteAllSessions() {
        Task {
            try? await store.deleteAllSessions()
            NotificationCenter.default.post(name: .loomSessionsDidChange, object: nil)
        }
    }
}

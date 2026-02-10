import SwiftUI

struct SettingsView: View {
    @AppStorage("statusAutoRefreshEnabled")
    private var statusAutoRefreshEnabled: Bool = true

    @AppStorage("modelsAutoCheckEnabled")
    private var modelsAutoCheckEnabled: Bool = true

    var body: some View {
        Form {
            Section("Automation") {
                Toggle("Refresh status automatically", isOn: $statusAutoRefreshEnabled)
                Toggle("Check model availability automatically", isOn: $modelsAutoCheckEnabled)
            }

            Section {
                Text("More settings are coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

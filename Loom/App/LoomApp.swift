import SwiftUI

@main
struct LoomApp: App {
    private let store = SessionStore()
    private static let uiTestResetDefaultsEnvironmentKey = "LOOM_UI_TEST_RESET_DEFAULTS"
    private static let xCTestConfigurationPathEnvironmentKey = "XCTestConfigurationFilePath"

    init() {
        let environment = ProcessInfo.processInfo.environment
        guard environment[Self.uiTestResetDefaultsEnvironmentKey] == "1",
              environment[Self.xCTestConfigurationPathEnvironmentKey] != nil else {
            return
        }

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: LoomPreferenceKeys.activeModelTag)
        defaults.removeObject(forKey: LoomPreferenceKeys.statusAutoRefreshEnabled)
        defaults.removeObject(forKey: LoomPreferenceKeys.modelsAutoCheckEnabled)
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Export Session…") {
                    NotificationCenter.default.post(name: .loomExportSessionRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let loomExportSessionRequested = Notification.Name("loom.exportSessionRequested")
    static let loomSessionsDidChange = Notification.Name("loom.sessionsDidChange")
}

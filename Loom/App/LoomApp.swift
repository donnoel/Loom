import SwiftUI
import AppKit

@main
struct LoomApp: App {
    private let store = SessionStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private static let uiTestResetDefaultsEnvironmentKey = "LOOM_UI_TEST_RESET_DEFAULTS"
    private static let uiTestResetStorageEnvironmentKey = "LOOM_UI_TEST_RESET_STORAGE"
    private static let uiTestActiveModelTagEnvironmentKey = "LOOM_UI_TEST_ACTIVE_MODEL_TAG"
    private static let uiTestChatScenarioDefaultsKey = "loom.uiTest.chatScenario"

    init() {
        let environment = ProcessInfo.processInfo.environment
        guard environment[Self.uiTestResetDefaultsEnvironmentKey] == "1" else {
            return
        }

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: LoomPreferenceKeys.activeModelTag)
        defaults.removeObject(forKey: LoomPreferenceKeys.statusAutoRefreshEnabled)
        defaults.removeObject(forKey: LoomPreferenceKeys.modelsAutoCheckEnabled)
        defaults.removeObject(forKey: Self.uiTestChatScenarioDefaultsKey)

        if environment[Self.uiTestResetStorageEnvironmentKey] == "1" {
            if let sessionsRoot = try? LoomPaths.sessionsRoot(),
               FileManager.default.fileExists(atPath: sessionsRoot.path) {
                try? FileManager.default.removeItem(at: sessionsRoot)
            }
            if let workspacesRoot = try? LoomPaths.workspacesRoot(),
               FileManager.default.fileExists(atPath: workspacesRoot.path) {
                try? FileManager.default.removeItem(at: workspacesRoot)
            }
        }

        if let activeModelTag = environment[Self.uiTestActiveModelTagEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !activeModelTag.isEmpty {
            defaults.set(activeModelTag, forKey: LoomPreferenceKeys.activeModelTag)
        }

        // Chat stream stubs are read from launch environment only so test state cannot leak into normal app runs.
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
    static let loomChatTemplatesDidChange = Notification.Name("loom.chatTemplatesDidChange")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the window title text ("Loom") in the unified toolbar/titlebar.
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.title = ""
            }
        }
    }
}

import SwiftUI
import AppKit

@main
struct LoomApp: App {
    private let store = SessionStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private static let uiTestResetDefaultsEnvironmentKey = "LOOM_UI_TEST_RESET_DEFAULTS"
    private static let uiTestResetStorageEnvironmentKey = "LOOM_UI_TEST_RESET_STORAGE"
    private static let uiTestActiveModelTagEnvironmentKey = "LOOM_UI_TEST_ACTIVE_MODEL_TAG"
    private static let uiTestChatScenarioEnvironmentKey = "LOOM_UI_TEST_CHAT_STUB_SCENARIO"
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
        }

        if let activeModelTag = environment[Self.uiTestActiveModelTagEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !activeModelTag.isEmpty {
            defaults.set(activeModelTag, forKey: LoomPreferenceKeys.activeModelTag)
        }

        if let chatScenario = environment[Self.uiTestChatScenarioEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !chatScenario.isEmpty {
            defaults.set(chatScenario.lowercased(), forKey: Self.uiTestChatScenarioDefaultsKey)
        }
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

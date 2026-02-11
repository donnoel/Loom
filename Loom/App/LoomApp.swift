import SwiftUI

@main
struct LoomApp: App {
    private let store = SessionStore()

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

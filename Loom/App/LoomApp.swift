import SwiftUI

@main
struct LoomApp: App {
    private let store = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}

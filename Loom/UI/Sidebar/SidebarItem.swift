import Foundation

nonisolated enum SidebarItem: String, Hashable, Identifiable, Sendable {
    case sessions
    case models
    case compare
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: "Sessions"
        case .models: "Models"
        case .compare: "Compare"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions: "bubble.left.and.bubble.right"
        case .models: "cube.box"
        case .compare: "square.split.2x1"
        case .settings: "gearshape"
        }
    }
}

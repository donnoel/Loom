import Foundation

nonisolated enum SidebarItem: String, Hashable, Identifiable, Sendable {
    case sessions
    case models
    case status
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: "Sessions"
        case .models: "Models"
        case .status: "Status"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions: "bubble.left.and.bubble.right"
        case .models: "cube.box"
        case .status: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }
}

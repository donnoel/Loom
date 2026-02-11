import Foundation

nonisolated enum LoomReadiness: String, Sendable {
    case ready
    case needsSetup
    case notReady

    var label: String {
        switch self {
        case .ready: "Ready"
        case .needsSetup: "Needs setup"
        case .notReady: "Not ready"
        }
    }
}

nonisolated enum LoomIssue: Hashable, Sendable {
    case ollamaNotRunning
    case noModelsInstalled
    case noModelSelected
}

nonisolated struct LoomStatusSnapshot: Sendable, Equatable {
    var ollamaReachable: Bool
    var installedModelCount: Int
    var activeModelTag: String?
    var offlineAvailable: Bool

    var issues: [LoomIssue] {
        if !ollamaReachable {
            return [.ollamaNotRunning]
        }
        if installedModelCount == 0 {
            return [.noModelsInstalled]
        }
        if activeModelTag == nil {
            return [.noModelSelected]
        }
        return []
    }

    var readiness: LoomReadiness {
        if !ollamaReachable {
            return .notReady
        }
        if installedModelCount == 0 || activeModelTag == nil {
            return .needsSetup
        }
        return .ready
    }

    static let unavailable = LoomStatusSnapshot(
        ollamaReachable: false,
        installedModelCount: 0,
        activeModelTag: nil,
        offlineAvailable: false
    )
}

nonisolated enum LoomPreferenceKeys {
    static let activeModelTag = "activeModelTag"
    static let statusAutoRefreshEnabled = "statusAutoRefreshEnabled"
    static let modelsAutoCheckEnabled = "modelsAutoCheckEnabled"
}

nonisolated extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

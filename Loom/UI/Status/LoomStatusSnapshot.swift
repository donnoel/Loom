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
    var diskSpace: DiskSpaceSnapshot?

    init(
        ollamaReachable: Bool,
        installedModelCount: Int,
        activeModelTag: String?,
        offlineAvailable: Bool,
        diskSpace: DiskSpaceSnapshot? = nil
    ) {
        self.ollamaReachable = ollamaReachable
        self.installedModelCount = installedModelCount
        self.activeModelTag = activeModelTag
        self.offlineAvailable = offlineAvailable
        self.diskSpace = diskSpace
    }

    var lowDiskSpaceWarning: String? {
        guard let diskSpace, diskSpace.isLowSpace else { return nil }
        return DiskSpaceSnapshot.lowSpaceWarningMessage
    }

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
        offlineAvailable: false,
        diskSpace: nil
    )
}

nonisolated enum LoomPreferenceKeys {
    static let activeModelTag = "activeModelTag"
    static let statusAutoRefreshEnabled = "statusAutoRefreshEnabled"
    static let modelsAutoCheckEnabled = "modelsAutoCheckEnabled"
    static let modelLibraryOrder = "modelLibraryOrder"
    static let aiStatusServiceOrder = "aiStatusServiceOrder"
    static let voiceReplyEnabled = "voiceReplyEnabled"
    static let voiceReplyVoiceIdentifier = "voiceReplyVoiceIdentifier"
    static let voiceReplyRate = "voiceReplyRate"
    static let composerHistoryContextLevel = "composerHistoryContextLevel"
    static let composerFileContextLevel = "composerFileContextLevel"
    static let sessionLastStreamModelKeyPrefix = "sessionLastStreamModel."

    static func sessionLastStreamModelKey(for sessionID: UUID) -> String {
        "\(sessionLastStreamModelKeyPrefix)\(sessionID.uuidString)"
    }
}

nonisolated enum VoiceReplyPreferences {
    static let defaultRate: Double = 0.46
    static let minRate: Double = 0.35
    static let maxRate: Double = 0.60
    static let previewText = "This is Loom. Adjust my voice and speaking speed until it sounds right to you."

    static func normalizedRate(_ value: Double) -> Double {
        guard value.isFinite else { return defaultRate }
        return min(max(value, minRate), maxRate)
    }
}

nonisolated extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

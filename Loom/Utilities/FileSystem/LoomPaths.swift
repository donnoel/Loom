import Foundation

nonisolated enum LoomPaths {
    static let appFolderName = "Loom"
    static let sessionsFolderName = "Sessions"
    static let metadataFileName = "metadata.json"
    static let messagesFileName = "messages.jsonl"
    private static let overrideRootEnvironmentKey = "LOOM_APP_SUPPORT_ROOT"

    static func applicationSupportRoot() throws -> URL {
        if let override = ProcessInfo.processInfo.environment[overrideRootEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        }

        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent(appFolderName, isDirectory: true)
    }

    static func sessionsRoot() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["LOOM_SESSIONS_ROOT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        }

        return try applicationSupportRoot().appendingPathComponent(sessionsFolderName, isDirectory: true)
    }

    static func sessionFolder(for id: UUID) throws -> URL {
        try sessionsRoot().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func sessionMetadataURL(for id: UUID) throws -> URL {
        try sessionFolder(for: id).appendingPathComponent(metadataFileName, isDirectory: false)
    }

    static func sessionMessagesURL(for id: UUID) throws -> URL {
        try sessionFolder(for: id).appendingPathComponent(messagesFileName, isDirectory: false)
    }
}

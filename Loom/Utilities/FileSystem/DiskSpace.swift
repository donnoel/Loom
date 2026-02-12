import Foundation

nonisolated struct DiskSpaceSnapshot: Equatable, Sendable {
    static let lowSpaceWarningMessage = "Low disk space: less than 10% free. Installing models may fail."

    let totalBytes: Int64
    let availableBytes: Int64

    var availablePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(availableBytes) / Double(totalBytes)
    }

    var isLowSpace: Bool {
        availablePercent < 0.10
    }

    var availablePercentDisplay: String {
        "\(Int((availablePercent * 100).rounded()))%"
    }

    static func currentForOllamaModels(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> DiskSpaceSnapshot? {
        for url in preferredProbeURLs(environment: environment, homeDirectory: homeDirectory) {
            if let snapshot = current(for: url) {
                return snapshot
            }
        }
        return nil
    }

    static func current(for url: URL = URL(fileURLWithPath: "/")) -> DiskSpaceSnapshot? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]

        guard let values = try? url.resourceValues(forKeys: keys),
              let totalCapacity = values.volumeTotalCapacity
        else {
            return nil
        }

        let availableCapacity: Int64
        if let importantCapacity = values.volumeAvailableCapacityForImportantUsage {
            availableCapacity = importantCapacity
        } else if let fallbackCapacity = values.volumeAvailableCapacity {
            availableCapacity = Int64(fallbackCapacity)
        } else {
            return nil
        }

        return DiskSpaceSnapshot(
            totalBytes: Int64(totalCapacity),
            availableBytes: availableCapacity
        )
    }

    static func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    static func preferredProbeURLs(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> [URL] {
        var candidates: [URL] = []

        if let configuredPath = trimmedNonEmpty(environment["OLLAMA_MODELS"]) {
            candidates.append(URL(fileURLWithPath: expandTilde(in: configuredPath), isDirectory: true))
        }

        candidates.append(homeDirectory.appendingPathComponent(".ollama/models", isDirectory: true))
        candidates.append(homeDirectory)
        candidates.append(URL(fileURLWithPath: "/", isDirectory: true))

        var seenPaths: Set<String> = []
        var deduped: [URL] = []

        for candidate in candidates {
            let standardizedPath = candidate.standardizedFileURL.path
            if seenPaths.insert(standardizedPath).inserted {
                deduped.append(candidate)
            }
        }

        return deduped
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func expandTilde(in path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}

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
}

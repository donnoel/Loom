import Foundation

nonisolated enum WorkspaceIndexer {
    private static let ignoredPathComponents: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        "DerivedData",
        "Pods",
        "build",
        "node_modules"
    ]

    private static let includedExtensions: Set<String> = [
        "c",
        "cc",
        "cpp",
        "h",
        "hpp",
        "json",
        "md",
        "m",
        "mm",
        "plist",
        "swift",
        "txt",
        "xcodeproj",
        "xcworkspace",
        "yaml",
        "yml"
    ]

    static func snapshot(
        for session: WorkspaceSession,
        runner: any DeveloperToolRunning,
        limit: Int = 400
    ) async -> WorkspaceIndexSnapshot {
        let (_, fileList) = await runner.listFiles(session: session)
        let files = fileList.files
            .filter(shouldInclude(relativePath:))
            .prefix(limit)
        return WorkspaceIndexSnapshot(files: Array(files), source: fileList.source)
    }

    static func shouldDescend(into relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        return !components.contains { ignoredPathComponents.contains($0) }
    }

    static func shouldInclude(relativePath: String) -> Bool {
        guard shouldDescend(into: relativePath) else { return false }
        let url = URL(fileURLWithPath: relativePath)
        if url.pathExtension.isEmpty {
            return ["Makefile", "Package.swift", "README", "LICENSE"].contains(url.lastPathComponent)
        }
        return includedExtensions.contains(url.pathExtension.lowercased())
    }
}

nonisolated enum WorkspaceProjectDetector {
    static func detectProject(in rootURL: URL) -> WorkspaceSession.ProjectSelection? {
        let candidates = detectProjects(in: rootURL)
        return candidates.first
    }

    static func detectProjects(in rootURL: URL) -> [WorkspaceSession.ProjectSelection] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var workspaces: [WorkspaceSession.ProjectSelection] = []
        var projects: [WorkspaceSession.ProjectSelection] = []

        for case let url as URL in enumerator {
            let relativePath = relativePath(for: url, rootURL: rootURL)
            if !WorkspaceIndexer.shouldDescend(into: relativePath) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else {
                continue
            }

            switch url.pathExtension {
            case "xcworkspace":
                workspaces.append(WorkspaceSession.ProjectSelection(kind: .xcodeWorkspace, relativePath: relativePath))
                enumerator.skipDescendants()
            case "xcodeproj":
                projects.append(WorkspaceSession.ProjectSelection(kind: .xcodeProject, relativePath: relativePath))
                enumerator.skipDescendants()
            default:
                break
            }
        }

        return (workspaces + projects).sorted { lhs, rhs in
            lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }
}

import Foundation

nonisolated enum WorkspaceProjectKind: String, Codable, Sendable, CaseIterable {
    case xcodeProject
    case xcodeWorkspace

    var displayName: String {
        switch self {
        case .xcodeProject: "Xcode Project"
        case .xcodeWorkspace: "Xcode Workspace"
        }
    }
}

nonisolated enum WorkspaceProviderMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case localOllama
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localOllama: "Local"
        case .cloud: "Cloud"
        }
    }
}

nonisolated struct WorkspaceGitState: Codable, Equatable, Sendable {
    var branch: String?
    var statusSummary: String
    var checkedAt: Date

    init(branch: String?, statusSummary: String, checkedAt: Date = Date()) {
        self.branch = branch
        self.statusSummary = statusSummary
        self.checkedAt = checkedAt
    }
}

nonisolated struct WorkspaceSession: Identifiable, Codable, Equatable, Sendable {
    struct ProjectSelection: Codable, Equatable, Sendable {
        var kind: WorkspaceProjectKind
        var relativePath: String
        var schemes: [String]

        init(kind: WorkspaceProjectKind, relativePath: String, schemes: [String] = []) {
            self.kind = kind
            self.relativePath = relativePath
            self.schemes = schemes
        }
    }

    let id: UUID
    var displayName: String
    var rootPath: String
    var rootBookmarkData: Data?
    var selectedProject: ProjectSelection?
    var selectedScheme: String?
    var selectedDestination: String?
    var providerMode: WorkspaceProviderMode
    var allowsAutonomousEdits: Bool
    var lastKnownGitState: WorkspaceGitState?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        rootPath: String,
        rootBookmarkData: Data? = nil,
        selectedProject: ProjectSelection? = nil,
        selectedScheme: String? = nil,
        selectedDestination: String? = nil,
        providerMode: WorkspaceProviderMode = .localOllama,
        allowsAutonomousEdits: Bool = true,
        lastKnownGitState: WorkspaceGitState? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.rootPath = rootPath
        self.rootBookmarkData = rootBookmarkData
        self.selectedProject = selectedProject
        self.selectedScheme = selectedScheme
        self.selectedDestination = selectedDestination
        self.providerMode = providerMode
        self.allowsAutonomousEdits = allowsAutonomousEdits
        self.lastKnownGitState = lastKnownGitState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var rootURL: URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
    }
}

nonisolated enum DeveloperToolName: String, Codable, Sendable, CaseIterable, Identifiable {
    case readFile
    case search
    case listFiles
    case writeFile
    case applyPatch
    case gitDiff
    case gitStatus
    case xcodebuildList
    case build
    case test
    case openInXcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readFile: "Read File"
        case .search: "Search"
        case .listFiles: "List Files"
        case .writeFile: "Write File"
        case .applyPatch: "Apply Patch"
        case .gitDiff: "Git Diff"
        case .gitStatus: "Git Status"
        case .xcodebuildList: "Xcode Metadata"
        case .build: "Build"
        case .test: "Test"
        case .openInXcode: "Open in Xcode"
        }
    }

    var isEditingTool: Bool {
        switch self {
        case .writeFile, .applyPatch:
            return true
        case .readFile, .search, .listFiles, .gitDiff, .gitStatus, .xcodebuildList, .build, .test, .openInXcode:
            return false
        }
    }
}

nonisolated enum DeveloperToolStatus: String, Codable, Sendable {
    case success
    case failure
    case skipped
}

nonisolated struct DeveloperToolResult: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let tool: DeveloperToolName
    let status: DeveloperToolStatus
    let summary: String
    let output: String
    let startedAt: Date
    let finishedAt: Date

    init(
        id: UUID = UUID(),
        tool: DeveloperToolName,
        status: DeveloperToolStatus,
        summary: String,
        output: String,
        startedAt: Date = Date(),
        finishedAt: Date = Date()
    ) {
        self.id = id
        self.tool = tool
        self.status = status
        self.summary = summary
        self.output = output
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

nonisolated struct WorkspaceChangeRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let toolResultID: UUID
    let patch: String
    let createdAt: Date

    init(id: UUID = UUID(), toolResultID: UUID, patch: String, createdAt: Date = Date()) {
        self.id = id
        self.toolResultID = toolResultID
        self.patch = patch
        self.createdAt = createdAt
    }
}

nonisolated struct WorkspaceFileList: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case git
        case fileSystem
    }

    let files: [String]
    let source: Source
}

nonisolated struct WorkspaceIndexSnapshot: Equatable, Sendable {
    let files: [String]
    let source: WorkspaceFileList.Source
    let indexedAt: Date

    init(files: [String], source: WorkspaceFileList.Source, indexedAt: Date = Date()) {
        self.files = files
        self.source = source
        self.indexedAt = indexedAt
    }
}

nonisolated struct WorkspaceAgentToolCall: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var tool: DeveloperToolName
    var relativePath: String?
    var contents: String?
    var pattern: String?
    var patch: String?

    init(
        id: UUID = UUID(),
        tool: DeveloperToolName,
        relativePath: String? = nil,
        contents: String? = nil,
        pattern: String? = nil,
        patch: String? = nil
    ) {
        self.id = id
        self.tool = tool
        self.relativePath = relativePath
        self.contents = contents
        self.pattern = pattern
        self.patch = patch
    }

    enum CodingKeys: String, CodingKey {
        case id
        case tool
        case relativePath
        case contents
        case pattern
        case patch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        tool = try container.decode(DeveloperToolName.self, forKey: .tool)
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath)?.nonEmptyTrimmed
        contents = try container.decodeIfPresent(String.self, forKey: .contents)
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern)?.nonEmptyTrimmed
        patch = try container.decodeIfPresent(String.self, forKey: .patch)
    }
}

nonisolated struct WorkspaceAgentProviderResponse: Equatable, Sendable {
    let message: String
    let toolCalls: [WorkspaceAgentToolCall]

    init(message: String, toolCalls: [WorkspaceAgentToolCall] = []) {
        self.message = message
        self.toolCalls = toolCalls
    }
}

nonisolated struct WorkspaceAgentRequest: Sendable {
    let session: WorkspaceSession
    let messages: [ChatMessage]
    let indexSnapshot: WorkspaceIndexSnapshot
    let toolResults: [DeveloperToolResult]
}

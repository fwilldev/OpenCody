import Foundation

// MARK: - FileNode

/// Maps to `FileNode` in types.gen.ts
struct FileNode: Codable, Identifiable, Sendable {
    let name: String
    let path: String
    let absolute: String
    let type: FileNodeType
    let ignored: Bool

    /// Use `path` as the identifier
    var id: String { path }
}

enum FileNodeType: String, Codable, Sendable {
    case file
    case directory
}

// MARK: - FileContent

/// Maps to `FileContent` in types.gen.ts
struct FileContent: Codable, Sendable {
    let type: FileContentType
    let content: String
    let diff: String?
    let patch: FilePatch?
    let encoding: String?
    let mimeType: String?
}

enum FileContentType: String, Codable, Sendable {
    case text
    case binary
}

// MARK: - FilePatch

struct FilePatch: Codable, Sendable {
    let oldFileName: String
    let newFileName: String
    let oldHeader: String?
    let newHeader: String?
    let hunks: [PatchHunk]
    let index: String?
}

struct PatchHunk: Codable, Sendable {
    let oldStart: Int
    let oldLines: Int
    let newStart: Int
    let newLines: Int
    let lines: [String]
}

// MARK: - File (diff summary)

/// Maps to `File` in types.gen.ts — represents a changed file summary
struct ChangedFile: Codable, Identifiable, Sendable {
    let path: String
    let added: Int
    let removed: Int
    let status: ChangedFileStatus

    var id: String { path }
}

enum ChangedFileStatus: String, Codable, Sendable {
    case added
    case deleted
    case modified
}

// MARK: - VcsInfo

/// Version-control information for a project. Maps to `VcsInfo`.
///
/// Both fields are optional — a directory that is not a git repository returns
/// an empty object.
struct VcsInfo: Codable, Sendable {
    let branch: String?
    /// The repository's default branch (e.g. `main`), used as the base for branch diffs.
    let defaultBranch: String?

    /// Whether the project is under version control at all.
    var isRepository: Bool { branch != nil }

    enum CodingKeys: String, CodingKey {
        case branch
        case defaultBranch = "default_branch"
    }
}

// MARK: - Path

/// Maps to `Path` in types.gen.ts
struct PathInfo: Codable, Sendable {
    let home: String
    let state: String
    let config: String
    let worktree: String
    let directory: String
}

// MARK: - Project

/// A project opened with opencode. Maps to `Project`.
struct Project: Codable, Identifiable, Sendable {
    let id: String
    /// Absolute path of the project's primary worktree.
    let worktree: String
    /// `"git"` when the project is a git repository, `nil` otherwise.
    let vcs: String?
    /// User-assigned display name.
    let name: String?
    let icon: ProjectIcon?
    let commands: ProjectCommands?
    let time: ProjectTime
    /// Directories of sandbox worktrees created for this project.
    let sandboxes: [String]?

    /// Name for display — the assigned name, else the worktree's last path component.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return (worktree as NSString).lastPathComponent
    }

    /// Whether the project is a git repository.
    var isGitRepository: Bool { vcs == "git" }
}

/// Project icon override. Maps to `Project.icon`.
struct ProjectIcon: Codable, Sendable {
    let url: String?
    /// An SF Symbol / emoji override chosen by the user instead of a fetched icon.
    let override: String?
    /// Hex tint colour.
    let color: String?

    init(url: String? = nil, override: String? = nil, color: String? = nil) {
        self.url = url
        self.override = override
        self.color = color
    }
}

/// Project-level scripts. Maps to `Project.commands`.
struct ProjectCommands: Codable, Sendable {
    /// Startup script run when creating a new workspace (worktree).
    let start: String?

    init(start: String? = nil) {
        self.start = start
    }
}

struct ProjectTime: Codable, Sendable {
    let created: Double
    let updated: Double?
    /// Set once opencode has run its project initialization.
    let initialized: Double?
}

// MARK: - Symbol

struct SymbolInfo: Codable, Sendable {
    let name: String
    let kind: Int
    let location: SymbolLocation
}

struct SymbolLocation: Codable, Sendable {
    let uri: String
    let range: SourceRange
}

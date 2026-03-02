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

struct VcsInfo: Codable, Sendable {
    let branch: String
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

/// Maps to `Project` in types.gen.ts
/// Maps to `Project` in types.gen.ts
    struct Project: Codable, Identifiable, Sendable {
    let id: String
    let worktree: String
    let vcs: String?
    let time: ProjectTime
}

struct ProjectTime: Codable, Sendable {
    let created: Double
    let updated: Double?
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

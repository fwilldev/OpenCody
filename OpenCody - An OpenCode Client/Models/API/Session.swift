import Foundation

// MARK: - Session

/// Represents an OpenCode session.
/// Maps to `Session` in types.gen.ts
struct Session: Codable, Identifiable, Sendable, Hashable {
    let id: String
    /// URL-safe short name the server derives from the title.
    let slug: String?
    let projectID: String
    /// Workspace (worktree) the session is attached to, when the server uses workspaces.
    let workspaceID: String?
    let directory: String
    /// Subdirectory within the project the session is scoped to.
    let path: String?
    let parentID: String?
    let summary: SessionSummary?
    let share: SessionShare?
    let title: String
    /// Agent bound to the session.
    let agent: String?
    /// Model bound to the session.
    let model: SessionModel?
    /// Accumulated cost in USD across all messages.
    let cost: Double?
    /// Accumulated token usage across all messages.
    let tokens: SessionTokens?
    let version: String
    let time: SessionTime
    let revert: SessionRevert?

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case projectID
        case workspaceID
        case directory
        case path
        case parentID
        case summary
        case share
        case title
        case agent
        case model
        case cost
        case tokens
        case version
        case time
        case revert
    }

    /// Whether the session has been archived by the user.
    var isArchived: Bool { time.archived != nil }

    /// Whether the server is currently compacting this session's context.
    var isCompacting: Bool { time.compacting != nil }

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SessionSummary

struct SessionSummary: Codable, Sendable {
    let additions: Int
    let deletions: Int
    let files: Int
    let diffs: [FileDiff]?
}

// MARK: - SessionModel

/// Model bound to a session. Note the server names the model identifier `id` here,
/// unlike message payloads which use `modelID`.
struct SessionModel: Codable, Sendable, Hashable {
    let id: String
    let providerID: String
    let variant: String?
}

// MARK: - SessionTokens

/// Cumulative token usage for a session.
struct SessionTokens: Codable, Sendable, Hashable {
    let input: Double
    let output: Double
    let reasoning: Double
    let cache: SessionTokenCache?

    /// Total tokens billed as input, including cache reads.
    var totalInput: Double { input + (cache?.read ?? 0) + (cache?.write ?? 0) }

    private enum CodingKeys: String, CodingKey {
        case input, output, reasoning, cache
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = (try? c.decodeIfPresent(Double.self, forKey: .input)) ?? 0
        output = (try? c.decodeIfPresent(Double.self, forKey: .output)) ?? 0
        reasoning = (try? c.decodeIfPresent(Double.self, forKey: .reasoning)) ?? 0
        cache = try? c.decodeIfPresent(SessionTokenCache.self, forKey: .cache)
    }
}

struct SessionTokenCache: Codable, Sendable, Hashable {
    let read: Double
    let write: Double

    private enum CodingKeys: String, CodingKey { case read, write }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        read = (try? c.decodeIfPresent(Double.self, forKey: .read)) ?? 0
        write = (try? c.decodeIfPresent(Double.self, forKey: .write)) ?? 0
    }
}

// MARK: - FileDiff

/// A per-file change produced by a session.
///
/// Maps to `SnapshotFileDiff` (session diffs) and `VcsFileDiff` (working-tree diffs).
/// Both carry the change as a **unified diff patch** in `patch`; the older
/// `before`/`after` full-content fields no longer exist in the schema, so
/// consumers must read `patch`.
struct FileDiff: Codable, Sendable, Identifiable {
    /// Repository-relative path. Optional in `SnapshotFileDiff`.
    let file: String
    /// Unified diff text for this file, when the server computed one.
    let patch: String?
    let additions: Int
    let deletions: Int
    let status: FileDiffStatus

    var id: String { file }

    enum CodingKeys: String, CodingKey {
        case file, patch, additions, deletions, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `file` is optional in SnapshotFileDiff — tolerate its absence.
        file = (try? container.decodeIfPresent(String.self, forKey: .file)) ?? ""
        patch = try? container.decodeIfPresent(String.self, forKey: .patch)
        additions = (try? container.decodeIfPresent(Int.self, forKey: .additions)) ?? 0
        deletions = (try? container.decodeIfPresent(Int.self, forKey: .deletions)) ?? 0
        status = (try? container.decodeIfPresent(FileDiffStatus.self, forKey: .status)) ?? .modified
    }

    init(file: String, patch: String?, additions: Int, deletions: Int, status: FileDiffStatus) {
        self.file = file
        self.patch = patch
        self.additions = additions
        self.deletions = deletions
        self.status = status
    }
}

enum FileDiffStatus: String, Codable, Sendable {
    case modified
    case added
    case deleted

    var label: String {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        }
    }
}

// MARK: - SessionShare

struct SessionShare: Codable, Sendable {
    let url: String
}

// MARK: - SessionTime

struct SessionTime: Codable, Sendable {
    /// Unix timestamp (seconds)
    let created: Double
    /// Unix timestamp (seconds)
    let updated: Double
    /// Unix timestamp (seconds), present during compaction
    let compacting: Double?
    /// Unix timestamp (seconds), present when session is archived
    let archived: Double?
}

// MARK: - SessionRevert

struct SessionRevert: Codable, Sendable {
    let messageID: String
    let partID: String?
    let snapshot: String?
    let diff: String?
}

// MARK: - SessionStatus

/// Status of a session. This is a discriminated union in TS.
/// `{ type: "idle" } | { type: "retry", attempt, message, next } | { type: "busy" }`
enum SessionStatus: Codable, Sendable {
    case idle
    case retry(attempt: Int, message: String, next: Double)
    case busy

    private enum TypeKey: String, Codable {
        case idle, retry, busy
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case attempt
        case message
        case next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Tolerate future status types rather than failing the whole payload.
        guard let type = try? container.decode(TypeKey.self, forKey: .type) else {
            self = .busy
            return
        }
        switch type {
        case .idle:
            self = .idle
        case .busy:
            self = .busy
        case .retry:
            let attempt = (try? container.decodeIfPresent(Int.self, forKey: .attempt)) ?? 0
            let message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
            let next = (try? container.decodeIfPresent(Double.self, forKey: .next)) ?? 0
            self = .retry(attempt: attempt, message: message, next: next)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(TypeKey.idle, forKey: .type)
        case .busy:
            try container.encode(TypeKey.busy, forKey: .type)
        case .retry(let attempt, let message, let next):
            try container.encode(TypeKey.retry, forKey: .type)
            try container.encode(attempt, forKey: .attempt)
            try container.encode(message, forKey: .message)
            try container.encode(next, forKey: .next)
        }
    }
}

// MARK: - GlobalSession

/// A session returned by `GET /experimental/session`, which spans all projects
/// and attaches a project summary so the client can group results.
struct GlobalSession: Decodable, Identifiable, Sendable {
    let session: Session
    let project: ProjectSummary?

    var id: String { session.id }

    private enum CodingKeys: String, CodingKey {
        case project
    }

    init(from decoder: Decoder) throws {
        // The payload is a Session with one extra `project` key.
        session = try Session(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        project = try? c.decodeIfPresent(ProjectSummary.self, forKey: .project)
    }
}

/// Minimal project descriptor attached to a `GlobalSession`.
struct ProjectSummary: Decodable, Identifiable, Sendable {
    let id: String
    let name: String?
    let worktree: String
}

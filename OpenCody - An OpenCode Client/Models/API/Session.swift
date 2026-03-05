import Foundation

// MARK: - Session

/// Represents an OpenCode session.
/// Maps to `Session` in types.gen.ts
struct Session: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let projectID: String
    let directory: String
    let parentID: String?
    let summary: SessionSummary?
    let share: SessionShare?
    let title: String
    let version: String
    let time: SessionTime
    let revert: SessionRevert?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID
        case directory
        case parentID
        case summary
        case share
        case title
        case version
        case time
        case revert
    }

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

// MARK: - FileDiff

struct FileDiff: Codable, Sendable {
    let file: String
    let before: String
    let after: String
    let additions: Int
    let deletions: Int
    let status: FileDiffStatus

    enum CodingKeys: String, CodingKey {
        case file, before, after, additions, deletions, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decode(String.self, forKey: .file)
        // before/after can be null for added/deleted files
        before = try container.decodeIfPresent(String.self, forKey: .before) ?? ""
        after = try container.decodeIfPresent(String.self, forKey: .after) ?? ""
        additions = try container.decodeIfPresent(Int.self, forKey: .additions) ?? 0
        deletions = try container.decodeIfPresent(Int.self, forKey: .deletions) ?? 0
        status = try container.decodeIfPresent(FileDiffStatus.self, forKey: .status) ?? .modified
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
        let type = try container.decode(TypeKey.self, forKey: .type)
        switch type {
        case .idle:
            self = .idle
        case .busy:
            self = .busy
        case .retry:
            let attempt = try container.decode(Int.self, forKey: .attempt)
            let message = try container.decode(String.self, forKey: .message)
            let next = try container.decode(Double.self, forKey: .next)
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

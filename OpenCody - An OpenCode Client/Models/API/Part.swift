import Foundation

// Local duplicates to avoid cross-file SourceKit cycles
struct PartTokenUsage: Codable, Sendable {
    let input: Int
    let output: Int
    let reasoning: Int
    let cache: PartTokenCache?
    let total: Int?

    private enum CodingKeys: String, CodingKey {
        case input, output, reasoning, cache, total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = (try? container.decodeIfPresent(Int.self, forKey: .input)) ?? 0
        output = (try? container.decodeIfPresent(Int.self, forKey: .output)) ?? 0
        reasoning = (try? container.decodeIfPresent(Int.self, forKey: .reasoning)) ?? 0
        cache = try? container.decodeIfPresent(PartTokenCache.self, forKey: .cache)
        total = try? container.decodeIfPresent(Int.self, forKey: .total)
    }
}

struct PartTokenCache: Codable, Sendable {
    let read: Int
    let write: Int

    private enum CodingKeys: String, CodingKey {
        case read, write
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        read = (try? container.decodeIfPresent(Int.self, forKey: .read)) ?? 0
        write = (try? container.decodeIfPresent(Int.self, forKey: .write)) ?? 0
    }
}

struct PartAPIErrorData: Codable, Sendable {
    let message: String
    let statusCode: Int?
    let isRetryable: Bool
    let responseHeaders: [String: String]?
    let responseBody: String?
}

// MARK: - Part

/// Discriminated union of all message part types.
/// Decoded based on the `type` field.
enum Part: Codable, Identifiable, Sendable {
    case text(TextPart)
    case subtask(SubtaskPart)
    case reasoning(ReasoningPart)
    case file(FilePart)
    case tool(ToolPart)
    case stepStart(StepStartPart)
    case stepFinish(StepFinishPart)
    case snapshot(SnapshotPart)
    case patch(PatchPart)
    case agent(AgentPart)
    case retry(RetryPart)
    case compaction(CompactionPart)
    /// Catch-all for unknown/future part types — never throws during decode.
    case unknown(UnknownPart)

    var id: String {
        switch self {
        case .text(let p): return p.id
        case .subtask(let p): return p.id
        case .reasoning(let p): return p.id
        case .file(let p): return p.id
        case .tool(let p): return p.id
        case .stepStart(let p): return p.id
        case .stepFinish(let p): return p.id
        case .snapshot(let p): return p.id
        case .patch(let p): return p.id
        case .agent(let p): return p.id
        case .retry(let p): return p.id
        case .compaction(let p): return p.id
        case .unknown(let p): return p.id
        }
    }

    var type: String {
        switch self {
        case .text: return "text"
        case .subtask: return "subtask"
        case .reasoning: return "reasoning"
        case .file: return "file"
        case .tool: return "tool"
        case .stepStart: return "step-start"
        case .stepFinish: return "step-finish"
        case .snapshot: return "snapshot"
        case .patch: return "patch"
        case .agent: return "agent"
        case .retry: return "retry"
        case .compaction: return "compaction"
        case .unknown(let p): return p.type
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try TextPart(from: decoder))
        case "subtask":
            self = .subtask(try SubtaskPart(from: decoder))
        case "reasoning":
            self = .reasoning(try ReasoningPart(from: decoder))
        case "file":
            self = .file(try FilePart(from: decoder))
        case "tool":
            self = .tool(try ToolPart(from: decoder))
        case "step-start":
            self = .stepStart(try StepStartPart(from: decoder))
        case "step-finish":
            self = .stepFinish(try StepFinishPart(from: decoder))
        case "snapshot":
            self = .snapshot(try SnapshotPart(from: decoder))
        case "patch":
            self = .patch(try PatchPart(from: decoder))
        case "agent":
            self = .agent(try AgentPart(from: decoder))
        case "retry":
            self = .retry(try RetryPart(from: decoder))
        case "compaction":
            self = .compaction(try CompactionPart(from: decoder))
        default:
            // Unknown/future part type — decode gracefully, never throw
            self = .unknown(try UnknownPart(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let p): try p.encode(to: encoder)
        case .subtask(let p): try p.encode(to: encoder)
        case .reasoning(let p): try p.encode(to: encoder)
        case .file(let p): try p.encode(to: encoder)
        case .tool(let p): try p.encode(to: encoder)
        case .stepStart(let p): try p.encode(to: encoder)
        case .stepFinish(let p):
            var container = encoder.container(keyedBy: StepFinishPart.CodingKeys.self)
            try container.encode(p.id, forKey: .id)
            try container.encode(p.sessionID, forKey: .sessionID)
            try container.encode(p.messageID, forKey: .messageID)
            try container.encode(p.type, forKey: .type)
            try container.encode(p.reason, forKey: .reason)
            try container.encodeIfPresent(p.snapshot, forKey: .snapshot)
            try container.encodeIfPresent(p.cost, forKey: .cost)
            try container.encodeIfPresent(p.tokens, forKey: .tokens)
        case .snapshot(let p): try p.encode(to: encoder)
        case .patch(let p): try p.encode(to: encoder)
        case .agent(let p): try p.encode(to: encoder)
        case .retry(let p): try p.encode(to: encoder)
        case .compaction(let p): try p.encode(to: encoder)
        case .unknown(let p): try p.encode(to: encoder)
        }
    }
}

// MARK: - Common Part Fields

/// Base fields shared by all parts
protocol PartFields {
    var id: String { get }
    var sessionID: String { get }
    var messageID: String { get }
    var type: String { get }
}

// MARK: - UnknownPart

/// Catch-all for unrecognised part types. Never fails to decode.
struct UnknownPart: Codable, Identifiable, Sendable {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, messageID, type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        sessionID = (try? container.decodeIfPresent(String.self, forKey: .sessionID)) ?? ""
        messageID = (try? container.decodeIfPresent(String.self, forKey: .messageID)) ?? ""
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "unknown"
    }
}

// MARK: - TimeRange

struct TimeRange: Codable, Sendable {
    let start: Double
    let end: Double?
}

struct TimeRangeRequired: Codable, Sendable {
    let start: Double
    let end: Double?
    let compacted: Double?

    private enum CodingKeys: String, CodingKey {
        case start, end, compacted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = (try? container.decodeIfPresent(Double.self, forKey: .start)) ?? 0
        end = try? container.decodeIfPresent(Double.self, forKey: .end)
        compacted = try? container.decodeIfPresent(Double.self, forKey: .compacted)
    }
}

// MARK: - TextPart

struct TextPart: Codable, Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let text: String
    let synthetic: Bool?
    let ignored: Bool?
    let time: TimeRange?
    let metadata: [String: AnyCodable]?
}

// MARK: - SubtaskPart

struct SubtaskPart: Codable, Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let prompt: String?
    let description: String?
    let agent: String?

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, messageID, type, prompt, description, agent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        sessionID = (try? container.decodeIfPresent(String.self, forKey: .sessionID)) ?? ""
        messageID = (try? container.decodeIfPresent(String.self, forKey: .messageID)) ?? ""
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "subtask"
        prompt = try? container.decodeIfPresent(String.self, forKey: .prompt)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        agent = try? container.decodeIfPresent(String.self, forKey: .agent)
    }
}

// MARK: - ReasoningPart

struct ReasoningPart: Codable, Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let text: String
    let metadata: [String: AnyCodable]?
    let time: TimeRange?

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, messageID, type, text, metadata, time
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        sessionID = (try? container.decodeIfPresent(String.self, forKey: .sessionID)) ?? ""
        messageID = (try? container.decodeIfPresent(String.self, forKey: .messageID)) ?? ""
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "reasoning"
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        metadata = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .metadata)
        time = try? container.decodeIfPresent(TimeRange.self, forKey: .time)
    }

    init(id: String, sessionID: String, messageID: String, type: String, text: String, metadata: [String: AnyCodable]?, time: TimeRange?) {
        self.id = id
        self.sessionID = sessionID
        self.messageID = messageID
        self.type = type
        self.text = text
        self.metadata = metadata
        self.time = time
    }
}

// MARK: - FilePart

struct FilePart: Codable, Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let mime: String
    let filename: String?
    let url: String?
    let source: FilePartSource?

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, messageID, type, mime, filename, url, source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        sessionID = (try? container.decodeIfPresent(String.self, forKey: .sessionID)) ?? ""
        messageID = (try? container.decodeIfPresent(String.self, forKey: .messageID)) ?? ""
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "file"
        mime = (try? container.decodeIfPresent(String.self, forKey: .mime)) ?? ""
        filename = try? container.decodeIfPresent(String.self, forKey: .filename)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        source = try? container.decodeIfPresent(FilePartSource.self, forKey: .source)
    }
}

/// FileSource | SymbolSource — discriminated on `type`
enum FilePartSource: Codable, Sendable {
    case file(FileSource)
    case symbol(SymbolSource)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "file":
            self = .file(try FileSource(from: decoder))
        case "symbol":
            self = .symbol(try SymbolSource(from: decoder))
        default:
            // Unknown source type — fall back to a minimal FileSource
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown FilePartSource type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .file(let s): try s.encode(to: encoder)
        case .symbol(let s): try s.encode(to: encoder)
        }
    }
}

struct FilePartSourceText: Codable, Sendable {
    let value: String
    let start: Int
    let end: Int
}

struct FileSource: Codable, Sendable {
    let text: FilePartSourceText
    let type: String
    let path: String
}

struct SymbolSource: Codable, Sendable {
    let text: FilePartSourceText
    let type: String
    let path: String
    let range: SourceRange
    let name: String
    let kind: Int
}

struct SourceRange: Codable, Sendable {
    let start: SourcePosition
    let end: SourcePosition
}

struct SourcePosition: Codable, Sendable {
    let line: Int
    let character: Int
}

// MARK: - ToolPart

struct ToolPart: Codable, Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let callID: String
    let tool: String
    let state: ToolState
    let metadata: [String: AnyCodable]?

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
        case messageID
        case messageIDCamel = "messageId"
        case messageIDSnake = "message_id"
        case type
        case callID
        case callIDCamel = "callId"
        case callIDSnake = "call_id"
        case tool
        case state
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        sessionID =
            (try? container.decodeIfPresent(String.self, forKey: .sessionID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDSnake))
            ?? ""
        messageID =
            (try? container.decodeIfPresent(String.self, forKey: .messageID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .messageIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .messageIDSnake))
            ?? ""
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "tool"
        callID =
            (try? container.decodeIfPresent(String.self, forKey: .callID))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .callID)).map(String.init)
            ?? (try? container.decodeIfPresent(String.self, forKey: .callIDCamel))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .callIDCamel)).map(String.init)
            ?? (try? container.decodeIfPresent(String.self, forKey: .callIDSnake))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .callIDSnake)).map(String.init)
            ?? ""
        tool = (try? container.decodeIfPresent(String.self, forKey: .tool)) ?? ""
        state = try container.decode(ToolState.self, forKey: .state)
        metadata = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .metadata)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(messageID, forKey: .messageID)
        try container.encode(type, forKey: .type)
        try container.encode(callID, forKey: .callID)
        try container.encode(tool, forKey: .tool)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

/// Discriminated union: ToolStatePending | ToolStateRunning | ToolStateCompleted | ToolStateError
enum ToolState: Codable, Sendable {
    case pending(ToolStatePending)
    case running(ToolStateRunning)
    case completed(ToolStateCompleted)
    case error(ToolStateError)

    var status: ToolStatus {
        switch self {
        case .pending: return .pending
        case .running: return .running
        case .completed: return .completed
        case .error: return .error
        }
    }

    private enum CodingKeys: String, CodingKey {
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(ToolStatus.self, forKey: .status)
        switch status {
        case .pending:
            self = .pending(try ToolStatePending(from: decoder))
        case .running:
            self = .running(try ToolStateRunning(from: decoder))
        case .completed:
            self = .completed(try ToolStateCompleted(from: decoder))
        case .error:
            self = .error(try ToolStateError(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .pending(let s): try s.encode(to: encoder)
        case .running(let s): try s.encode(to: encoder)
        case .completed(let s): try s.encode(to: encoder)
        case .error(let s): try s.encode(to: encoder)
        }
    }
}

enum ToolStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case error
}

struct ToolStatePending: Codable, Sendable {
    let status: String
    let input: [String: AnyCodable]?
    let raw: String?

    private enum CodingKeys: String, CodingKey {
        case status, input, raw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? "pending"
        input = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .input)
        raw = try? container.decodeIfPresent(String.self, forKey: .raw)
    }
}

struct ToolStateRunning: Codable, Sendable {
    let status: String
    let input: [String: AnyCodable]?
    let title: String?
    let metadata: [String: AnyCodable]?
    let time: ToolTimeStart?

    private enum CodingKeys: String, CodingKey {
        case status, input, title, metadata, time
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? "running"
        input = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .input)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        metadata = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .metadata)
        time = try? container.decodeIfPresent(ToolTimeStart.self, forKey: .time)
    }
}

struct ToolTimeStart: Codable, Sendable {
    let start: Double
}

struct ToolStateCompleted: Codable, Sendable {
    let status: String
    let input: [String: AnyCodable]?
    let output: String?
    let title: String?
    let metadata: [String: AnyCodable]?
    let time: TimeRangeRequired?
    let attachments: [FilePart]?

    private enum CodingKeys: String, CodingKey {
        case status, input, output, title, metadata, time, attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? "completed"
        input = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .input)
        output = try? container.decodeIfPresent(String.self, forKey: .output)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        metadata = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .metadata)
        time = try? container.decodeIfPresent(TimeRangeRequired.self, forKey: .time)
        attachments = try? container.decodeIfPresent([FilePart].self, forKey: .attachments)
    }
}

struct ToolStateError: Codable, Sendable {
    let status: String
    let input: [String: AnyCodable]?
    let error: String
    let metadata: [String: AnyCodable]?
    let time: TimeRange?

    private enum CodingKeys: String, CodingKey {
        case status, input, error, metadata, time
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? "error"
        input = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .input)
        error = (try? container.decodeIfPresent(String.self, forKey: .error)) ?? ""
        metadata = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .metadata)
        time = try? container.decodeIfPresent(TimeRange.self, forKey: .time)
    }
}

// MARK: - StepStartPart

struct StepStartPart: Codable, Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let snapshot: String?
}

// MARK: - StepFinishPart

struct StepFinishPart: Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let reason: String
    let snapshot: String?
    let cost: Double?
    let tokens: PartTokenUsage?

    enum CodingKeys: String, CodingKey {
        case id, sessionID, messageID, type, reason, snapshot, cost, tokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        sessionID = (try? container.decodeIfPresent(String.self, forKey: .sessionID)) ?? ""
        messageID = (try? container.decodeIfPresent(String.self, forKey: .messageID)) ?? ""
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "step-finish"
        reason = (try? container.decodeIfPresent(String.self, forKey: .reason)) ?? ""
        snapshot = try? container.decodeIfPresent(String.self, forKey: .snapshot)
        cost = try? container.decodeIfPresent(Double.self, forKey: .cost)
        tokens = try? container.decodeIfPresent(PartTokenUsage.self, forKey: .tokens)
    }
}


// MARK: - SnapshotPart

struct SnapshotPart: Codable, Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let snapshot: String
}

// MARK: - PatchPart

struct PatchPart: Codable, Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let hash: String?
    let files: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, messageID, type, hash, files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        sessionID = (try? container.decodeIfPresent(String.self, forKey: .sessionID)) ?? ""
        messageID = (try? container.decodeIfPresent(String.self, forKey: .messageID)) ?? ""
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "patch"
        hash = try? container.decodeIfPresent(String.self, forKey: .hash)
        files = try? container.decodeIfPresent([String].self, forKey: .files)
    }
}

// MARK: - AgentPart

struct AgentPart: Codable, Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let name: String
    let source: AgentPartSource?
}

struct AgentPartSource: Codable, Sendable {
    let value: String
    let start: Int
    let end: Int
}

// MARK: - RetryPart

struct RetryPart: Codable, Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let attempt: Int
    let error: RetryError
    let time: RetryTime
}

struct RetryError: Codable, Sendable {
    let name: String
    let data: PartAPIErrorData
}

struct RetryTime: Codable, Sendable {
    let created: Double
}



// MARK: - CompactionPart

struct CompactionPart: Codable, Identifiable, Sendable, PartFields {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let auto: Bool
}

// MARK: - AnyCodable

/// A type-erased Codable value for `[key: string]: unknown` fields.
struct AnyCodable: Codable, Sendable {
    let value: AnyCodableValue

    init(_ value: AnyCodableValue) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = .null
        } else if let bool = try? container.decode(Bool.self) {
            value = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            value = .int(int)
        } else if let double = try? container.decode(Double.self) {
            value = .double(double)
        } else if let string = try? container.decode(String.self) {
            value = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            value = .array(array.map(\.value))
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = .object(dict.mapValues(\.value))
        } else {
            value = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .int(let i):
            try container.encode(i)
        case .double(let d):
            try container.encode(d)
        case .string(let s):
            try container.encode(s)
        case .array(let arr):
            try container.encode(arr.map { AnyCodable($0) })
        case .object(let dict):
            try container.encode(dict.mapValues { AnyCodable($0) })
        }
    }
}

enum AnyCodableValue: Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
}

// MARK: - AnyCodableValue Accessors

extension AnyCodableValue {
    /// The value as a `String`, or `nil` if it is another type.
    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// The value as an `Int`, widening from `.double` when it is integral.
    var asInt: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(exactly: d.rounded())
        default: return nil
        }
    }

    /// The value as a `Double`, widening from `.int`.
    var asDouble: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    /// The value as a `Bool`, or `nil` if it is another type.
    var asBool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// The value as an array, or `nil` if it is another type.
    var asArray: [AnyCodableValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// The value as an object, or `nil` if it is another type.
    var asObject: [String: AnyCodableValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Whether the value is JSON `null`.
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

extension AnyCodable {
    var asString: String? { value.asString }
    var asInt: Int? { value.asInt }
    var asDouble: Double? { value.asDouble }
    var asBool: Bool? { value.asBool }
    var asArray: [AnyCodableValue]? { value.asArray }
    var asObject: [String: AnyCodableValue]? { value.asObject }
}

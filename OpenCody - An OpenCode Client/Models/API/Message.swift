import Foundation

// MARK: - Message

/// Discriminated union: UserMessage | AssistantMessage
/// The `role` field determines which variant.
enum Message: Codable, Identifiable, Sendable {
    case user(UserMessage)
    case assistant(AssistantMessage)

    var id: String {
        switch self {
        case .user(let m): return m.id
        case .assistant(let m): return m.id
        }
    }

    var sessionID: String {
        switch self {
        case .user(let m): return m.sessionID ?? ""
        case .assistant(let m): return m.sessionID ?? ""
        }
    }

    var role: MessageRole {
        switch self {
        case .user: return .user
        case .assistant: return .assistant
        }
    }

    private enum CodingKeys: String, CodingKey {
        case role
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(MessageRole.self, forKey: .role)
        switch role {
        case .user:
            self = .user(try UserMessage(from: decoder))
        case .assistant:
            self = .assistant(try AssistantMessage(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .user(let m): try m.encode(to: encoder)
        case .assistant(let m): try m.encode(to: encoder)
        }
    }
}

// MARK: - MessageRole

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}

// MARK: - UserMessage

struct UserMessage: Codable, Identifiable, Sendable {
    let id: String
    let sessionID: String?
    let role: String // always "user"
    let time: UserMessageTime
    let summary: UserMessageSummary?
    let agent: String?
    let model: MessageModel?
    let system: String?
    let tools: [String: Bool]?

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, role, time, summary, agent, model, system, tools
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // id may be missing in some API responses — generate fallback
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        sessionID = try? container.decodeIfPresent(String.self, forKey: .sessionID)
        role = (try? container.decodeIfPresent(String.self, forKey: .role)) ?? "user"
        time = try container.decode(UserMessageTime.self, forKey: .time)
        summary = try? container.decodeIfPresent(UserMessageSummary.self, forKey: .summary)
        agent = try? container.decodeIfPresent(String.self, forKey: .agent)
        model = try? container.decodeIfPresent(MessageModel.self, forKey: .model)
        system = try? container.decodeIfPresent(String.self, forKey: .system)
        tools = try? container.decodeIfPresent([String: Bool].self, forKey: .tools)
    }

    init(
        id: String,
        sessionID: String?,
        role: String,
        time: UserMessageTime,
        summary: UserMessageSummary?,
        agent: String?,
        model: MessageModel?,
        system: String?,
        tools: [String: Bool]?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.time = time
        self.summary = summary
        self.agent = agent
        self.model = model
        self.system = system
        self.tools = tools
    }
}

struct UserMessageTime: Codable, Sendable {
    let created: Double
}

struct UserMessageSummary: Codable, Sendable {
    let title: String?
    let body: String?
    let diffs: [FileDiff]?

    private enum CodingKeys: String, CodingKey {
        case title, body, diffs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        body = try? container.decodeIfPresent(String.self, forKey: .body)
        diffs = try? container.decodeIfPresent([FileDiff].self, forKey: .diffs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(diffs, forKey: .diffs)
    }
}

struct MessageModel: Codable, Sendable {
    let providerID: String
    let modelID: String
}

// MARK: - AssistantMessage

struct AssistantMessage: Codable, Identifiable, Sendable {
    let id: String
    let sessionID: String?
    let role: String // always "assistant"
    let time: AssistantMessageTime
    let error: MessageError?
    let parentID: String?
    let modelID: String?
    let providerID: String?
    let mode: String?
    let path: MessagePath?
    let summary: Bool?
    let cost: Double?
    let tokens: TokenUsage?
    let finish: String?

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, role, time, error, parentID, modelID, providerID, mode, path, summary, cost, tokens, finish
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        sessionID = try? container.decodeIfPresent(String.self, forKey: .sessionID)
        role = (try? container.decodeIfPresent(String.self, forKey: .role)) ?? "assistant"
        time = (try? container.decode(AssistantMessageTime.self, forKey: .time)) ?? AssistantMessageTime(created: 0, completed: nil)
        error = try? container.decodeIfPresent(MessageError.self, forKey: .error)
        parentID = try? container.decodeIfPresent(String.self, forKey: .parentID)
        modelID = try? container.decodeIfPresent(String.self, forKey: .modelID)
        providerID = try? container.decodeIfPresent(String.self, forKey: .providerID)
        mode = try? container.decodeIfPresent(String.self, forKey: .mode)
        path = try? container.decodeIfPresent(MessagePath.self, forKey: .path)
        summary = try? container.decodeIfPresent(Bool.self, forKey: .summary)
        cost = try? container.decodeIfPresent(Double.self, forKey: .cost)
        tokens = try? container.decodeIfPresent(TokenUsage.self, forKey: .tokens)
        finish = try? container.decodeIfPresent(String.self, forKey: .finish)
    }
}

struct AssistantMessageTime: Codable, Sendable {
    let created: Double
    let completed: Double?
}

struct MessagePath: Codable, Sendable {
    let cwd: String
    let root: String
}

// MARK: - TokenUsage

struct TokenUsage: Codable, Sendable {
    let input: Int
    let output: Int
    let reasoning: Int
    let cache: TokenCache?
    let total: Int?

    private enum CodingKeys: String, CodingKey {
        case input, output, reasoning, cache, total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = (try? container.decodeIfPresent(Int.self, forKey: .input)) ?? 0
        output = (try? container.decodeIfPresent(Int.self, forKey: .output)) ?? 0
        reasoning = (try? container.decodeIfPresent(Int.self, forKey: .reasoning)) ?? 0
        cache = try? container.decodeIfPresent(TokenCache.self, forKey: .cache)
        total = try? container.decodeIfPresent(Int.self, forKey: .total)
    }
}

struct TokenCache: Codable, Sendable {
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

// MARK: - MessageError

/// Discriminated union for assistant message errors.
/// ProviderAuthError | UnknownError | MessageOutputLengthError | MessageAbortedError | ApiError
enum MessageError: Codable, Sendable {
    case providerAuth(providerID: String, message: String)
    case unknown(message: String)
    case outputLength
    case aborted(message: String)
    case api(APIErrorData)

    private enum CodingKeys: String, CodingKey {
        case name
        case data
    }

    private enum ErrorName: String, Codable {
        case providerAuth = "ProviderAuthError"
        case unknown = "UnknownError"
        case outputLength = "MessageOutputLengthError"
        case aborted = "MessageAbortedError"
        case api = "APIError"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(ErrorName.self, forKey: .name)
        switch name {
        case .providerAuth:
            let data = try container.decode(ProviderAuthErrorData.self, forKey: .data)
            self = .providerAuth(providerID: data.providerID, message: data.message)
        case .unknown:
            let data = try container.decode(UnknownErrorData.self, forKey: .data)
            self = .unknown(message: data.message)
        case .outputLength:
            self = .outputLength
        case .aborted:
            let data = try container.decode(AbortedErrorData.self, forKey: .data)
            self = .aborted(message: data.message)
        case .api:
            let data = try container.decode(APIErrorData.self, forKey: .data)
            self = .api(data)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .providerAuth(let providerID, let message):
            try container.encode(ErrorName.providerAuth, forKey: .name)
            try container.encode(ProviderAuthErrorData(providerID: providerID, message: message), forKey: .data)
        case .unknown(let message):
            try container.encode(ErrorName.unknown, forKey: .name)
            try container.encode(UnknownErrorData(message: message), forKey: .data)
        case .outputLength:
            try container.encode(ErrorName.outputLength, forKey: .name)
            try container.encode([String: String](), forKey: .data)
        case .aborted(let message):
            try container.encode(ErrorName.aborted, forKey: .name)
            try container.encode(AbortedErrorData(message: message), forKey: .data)
        case .api(let data):
            try container.encode(ErrorName.api, forKey: .name)
            try container.encode(data, forKey: .data)
        }
    }
}

struct ProviderAuthErrorData: Codable, Sendable {
    let providerID: String
    let message: String
}

struct UnknownErrorData: Codable, Sendable {
    let message: String
}

struct AbortedErrorData: Codable, Sendable {
    let message: String
}

struct APIErrorData: Codable, Sendable {
    let message: String
    let statusCode: Int?
    let isRetryable: Bool
    let responseHeaders: [String: String]?
    let responseBody: String?
}

// MARK: - MessageWithParts

/// Convenience wrapper combining a message with its parts.
struct MessageWithParts: Identifiable, Sendable {
    let message: Message
    var parts: [Part]

    var id: String { message.id }
}

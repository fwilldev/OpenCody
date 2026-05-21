import Foundation

// MARK: - SSEEvent

/// All server-sent event types from the OpenCode API.
/// Decoded from SSE `event` name + JSON `data` payload.
enum SSEEvent: Sendable {
    // Session events
    case sessionCreated(Session)
    case sessionUpdated(Session)
    case sessionDeleted(Session)
    case sessionStatus(SessionStatusPayload)
    case sessionIdle(sessionID: String)
    case sessionCompacted(sessionID: String)
    case sessionDiff(SessionDiffPayload)
    case sessionError(SessionErrorPayload)

    // Message events
    case messageUpdated(Message)
    case messageRemoved(MessageRemovedPayload)
    case messagePartUpdated(PartUpdatePayload)
    case messagePartRemoved(PartRemovePayload)
    case messagePartDelta(PartDeltaPayload)

    // Permission events
    case permissionUpdated(Permission)
    case permissionReplied(PermissionRepliedPayload)

    // Question events
    case questionAsked(QuestionRequest)
    case questionReplied(QuestionRepliedPayload)
    case questionRejected(QuestionRejectedPayload)

    // Todo events
    case todoUpdated(TodoUpdatePayload)

    // Command events
    case commandExecuted(CommandExecutedPayload)

    // File events
    case fileEdited(FileEditedPayload)
    case fileWatcherUpdated(FileWatcherUpdatedPayload)

    // VCS events
    case vcsBranchUpdated(VcsBranchUpdatedPayload)

    // Server events
    case serverConnected
    case serverInstanceDisposed(ServerInstanceDisposedPayload)

    // Installation events
    case installationUpdated(InstallationUpdatedPayload)
    case installationUpdateAvailable(InstallationUpdateAvailablePayload)

    // LSP events
    case lspClientDiagnostics(LspClientDiagnosticsPayload)
    case lspUpdated

    // Unknown catch-all
    case unknown(eventName: String, data: String)

    // MARK: - Parsing

    /// Parse an SSE event from its event name and JSON data string.
    static func parse(eventName: String, data: String) throws -> SSEEvent {
        let jsonData = Data(data.utf8)
        let decoder = JSONDecoder()

        switch eventName {
        case "session.created":
            let payload = try decoder.decode(EventPayload<SessionInfoPayload>.self, from: jsonData)
            return .sessionCreated(payload.properties.info)

        case "session.updated":
            let payload = try decoder.decode(EventPayload<SessionInfoPayload>.self, from: jsonData)
            return .sessionUpdated(payload.properties.info)

        case "session.deleted":
            let payload = try decoder.decode(EventPayload<SessionInfoPayload>.self, from: jsonData)
            return .sessionDeleted(payload.properties.info)

        case "session.status":
            let payload = try decoder.decode(EventPayload<SessionStatusPayload>.self, from: jsonData)
            return .sessionStatus(payload.properties)

        case "session.idle":
            let payload = try decoder.decode(EventPayload<SessionIDPayload>.self, from: jsonData)
            return .sessionIdle(sessionID: payload.properties.sessionID)

        case "session.compacted":
            let payload = try decoder.decode(EventPayload<SessionIDPayload>.self, from: jsonData)
            return .sessionCompacted(sessionID: payload.properties.sessionID)

        case "session.diff":
            let payload = try decoder.decode(EventPayload<SessionDiffPayload>.self, from: jsonData)
            return .sessionDiff(payload.properties)

        case "session.error":
            let payload = try decoder.decode(EventPayload<SessionErrorPayload>.self, from: jsonData)
            return .sessionError(payload.properties)

        case "message.updated":
            let payload = try decoder.decode(EventPayload<MessageInfoPayload>.self, from: jsonData)
            return .messageUpdated(payload.properties.info)

        case "message.removed":
            let payload = try decoder.decode(EventPayload<MessageRemovedPayload>.self, from: jsonData)
            return .messageRemoved(payload.properties)

        case "message.part.updated":
            let payload = try decoder.decode(EventPayload<PartUpdatePayload>.self, from: jsonData)
            return .messagePartUpdated(payload.properties)

        case "message.part.removed":
            let payload = try decoder.decode(EventPayload<PartRemovePayload>.self, from: jsonData)
            return .messagePartRemoved(payload.properties)

        case "message.part.delta":
            let payload = try decoder.decode(EventPayload<PartDeltaPayload>.self, from: jsonData)
            return .messagePartDelta(payload.properties)
        case "permission.updated", "permission.asked":
            let payload = try decoder.decode(EventPayload<Permission>.self, from: jsonData)
            return .permissionUpdated(payload.properties)

        case "permission.replied":
            let payload = try decoder.decode(EventPayload<PermissionRepliedPayload>.self, from: jsonData)
            return .permissionReplied(payload.properties)

        case "question.asked":
            let payload = try decoder.decode(EventPayload<QuestionRequest>.self, from: jsonData)
            return .questionAsked(payload.properties)

        case "question.replied":
            let payload = try decoder.decode(EventPayload<QuestionRepliedPayload>.self, from: jsonData)
            return .questionReplied(payload.properties)

        case "question.rejected":
            let payload = try decoder.decode(EventPayload<QuestionRejectedPayload>.self, from: jsonData)
            return .questionRejected(payload.properties)

        case "todo.updated":
            let payload = try decoder.decode(EventPayload<TodoUpdatePayload>.self, from: jsonData)
            return .todoUpdated(payload.properties)

        case "command.executed":
            let payload = try decoder.decode(EventPayload<CommandExecutedPayload>.self, from: jsonData)
            return .commandExecuted(payload.properties)

        case "file.edited":
            let payload = try decoder.decode(EventPayload<FileEditedPayload>.self, from: jsonData)
            return .fileEdited(payload.properties)

        case "file.watcher.updated":
            let payload = try decoder.decode(EventPayload<FileWatcherUpdatedPayload>.self, from: jsonData)
            return .fileWatcherUpdated(payload.properties)

        case "vcs.branch.updated":
            let payload = try decoder.decode(EventPayload<VcsBranchUpdatedPayload>.self, from: jsonData)
            return .vcsBranchUpdated(payload.properties)

        case "server.connected":
            return .serverConnected

        case "server.instance.disposed":
            let payload = try decoder.decode(EventPayload<ServerInstanceDisposedPayload>.self, from: jsonData)
            return .serverInstanceDisposed(payload.properties)

        case "installation.updated":
            let payload = try decoder.decode(EventPayload<InstallationUpdatedPayload>.self, from: jsonData)
            return .installationUpdated(payload.properties)

        case "installation.update-available":
            let payload = try decoder.decode(EventPayload<InstallationUpdateAvailablePayload>.self, from: jsonData)
            return .installationUpdateAvailable(payload.properties)

        case "lsp.client.diagnostics":
            let payload = try decoder.decode(EventPayload<LspClientDiagnosticsPayload>.self, from: jsonData)
            return .lspClientDiagnostics(payload.properties)

        case "lsp.updated":
            return .lspUpdated

        default:
            return .unknown(eventName: eventName, data: data)
        }
    }
}

// MARK: - Event Envelope

/// Generic envelope for SSE event JSON: `{ "type": "...", "properties": { ... } }`
private struct EventPayload<T: Decodable>: Decodable {
    let properties: T
}

// MARK: - Event Payload Types

struct SessionInfoPayload: Codable, Sendable {
    let info: Session
}
struct SessionStatusPayload: Decodable, Sendable {
    let sessionID: String
    let status: SessionStatus

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID =
            (try? container.decodeIfPresent(String.self, forKey: .sessionID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDSnake))
            ?? ""
        status = try container.decode(SessionStatus.self, forKey: .status)
    }
}

struct SessionIDPayload: Decodable, Sendable {
    let sessionID: String

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID =
            (try? container.decodeIfPresent(String.self, forKey: .sessionID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDSnake))
            ?? ""
    }
}

struct SessionDiffPayload: Decodable, Sendable {
    let sessionID: String
    let diff: [FileDiff]

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
        case diff
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID =
            (try? container.decodeIfPresent(String.self, forKey: .sessionID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDSnake))
            ?? ""
        diff = (try? container.decodeIfPresent([FileDiff].self, forKey: .diff)) ?? []
    }
}

struct SessionErrorPayload: Codable, Sendable {
    let sessionID: String?
    let error: MessageError?
}

struct MessageInfoPayload: Codable, Sendable {
    let info: Message
}

struct MessageRemovedPayload: Decodable, Sendable {
    let sessionID: String
    let messageID: String

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
        case messageID
        case messageIDCamel = "messageId"
        case messageIDSnake = "message_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
    }
}

struct PartUpdatePayload: Codable, Sendable {
    let part: Part
    let delta: String?
}

struct PartRemovePayload: Decodable, Sendable {
    let sessionID: String
    let messageID: String
    let partID: String

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
        case messageID
        case messageIDCamel = "messageId"
        case messageIDSnake = "message_id"
        case partID
        case partIDCamel = "partId"
        case partIDSnake = "part_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
        partID =
            (try? container.decodeIfPresent(String.self, forKey: .partID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .partIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .partIDSnake))
            ?? ""
    }
}

struct PartDeltaPayload: Decodable, Sendable {
    let sessionID: String
    let messageID: String
    let partID: String
    let field: String
    let delta: String

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
        case messageID
        case messageIDCamel = "messageId"
        case messageIDSnake = "message_id"
        case partID
        case partIDCamel = "partId"
        case partIDSnake = "part_id"
        case field
        case delta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
        partID =
            (try? container.decodeIfPresent(String.self, forKey: .partID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .partIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .partIDSnake))
            ?? ""
        field = (try? container.decodeIfPresent(String.self, forKey: .field)) ?? ""
        delta = (try? container.decodeIfPresent(String.self, forKey: .delta)) ?? ""
    }

    init(sessionID: String, messageID: String, partID: String, field: String, delta: String) {
        self.sessionID = sessionID
        self.messageID = messageID
        self.partID = partID
        self.field = field
        self.delta = delta
    }
}

struct PermissionRepliedPayload: Decodable, Sendable {
    let sessionID: String
    let permissionID: String
    let response: String

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
        case permissionID
        case permissionIDCamel = "permissionId"
        case permissionIDSnake = "permission_id"
        case response
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID =
            (try? container.decodeIfPresent(String.self, forKey: .sessionID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDSnake))
            ?? ""
        permissionID =
            (try? container.decodeIfPresent(String.self, forKey: .permissionID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .permissionIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .permissionIDSnake))
            ?? ""
        response = (try? container.decodeIfPresent(String.self, forKey: .response)) ?? ""
    }
}

struct TodoUpdatePayload: Codable, Sendable {
    let sessionID: String
    let todos: [TodoItem]
}

struct CommandExecutedPayload: Codable, Sendable {
    let name: String
    let sessionID: String
    let arguments: String
    let messageID: String
}

struct FileEditedPayload: Codable, Sendable {
    let file: String
}

struct FileWatcherUpdatedPayload: Codable, Sendable {
    let file: String
    let event: FileWatcherEvent
}

enum FileWatcherEvent: String, Codable, Sendable {
    case add
    case change
    case unlink
}

struct VcsBranchUpdatedPayload: Codable, Sendable {
    let branch: String?
}

struct ServerInstanceDisposedPayload: Codable, Sendable {
    let directory: String
}

struct InstallationUpdatedPayload: Codable, Sendable {
    let version: String
}

struct InstallationUpdateAvailablePayload: Codable, Sendable {
    let version: String
}

struct LspClientDiagnosticsPayload: Codable, Sendable {
    let serverID: String
    let path: String
}

// MARK: - GlobalEvent

/// Wrapper for events scoped to a project directory.
struct GlobalEvent: Codable, Sendable {
    let directory: String
    let payload: GlobalEventPayload
}

/// The raw event payload with type + properties.
/// We decode the event name then use SSEEvent.parse for typed dispatch.
struct GlobalEventPayload: Codable, Sendable {
    let type: String
    let properties: AnyCodable
}

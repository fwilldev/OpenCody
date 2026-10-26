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

    // Permission events (covers both `permission.asked` and `permission.v2.asked`)
    case permissionUpdated(Permission)
    case permissionReplied(PermissionRepliedPayload)

    // Question events (covers both `question.asked` and `question.v2.asked`)
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

    // Project events
    case projectUpdated(Project)
    case projectDirectoriesUpdated(projectID: String)

    // Workspace / worktree events
    case workspaceReady(name: String)
    case workspaceFailed(message: String)
    case workspaceStatus(WorkspaceStatusPayload)
    case worktreeReady(name: String, branch: String?)
    case worktreeFailed(message: String)

    // MCP events
    case mcpToolsChanged(server: String)
    case mcpBrowserOpenFailed(McpBrowserOpenFailedPayload)

    // Server events
    case serverConnected
    case serverInstanceDisposed(ServerInstanceDisposedPayload)
    case globalDisposed
    /// Periodic keep-alive. Carries no data, but receiving it resets the client's
    /// heartbeat watchdog so an idle stream is not mistaken for a dead one.
    case serverHeartbeat

    /// A `sync` envelope wrapping a versioned event (`session.created.1`, …).
    ///
    /// Intentionally inert: the server emits every sync event **alongside** its
    /// plain equivalent (`session.created`), so acting on both would apply each
    /// change twice. Kept as a distinct case rather than `.unknown` to record
    /// that the omission is deliberate.
    case syncEnvelope

    /// A server-side catalog/config reload that invalidates cached lists
    /// (integrations, references, catalog entries). The associated value is the
    /// originating event name.
    case serverStateChanged(String)

    // Installation events
    case installationUpdated(InstallationUpdatedPayload)
    case installationUpdateAvailable(InstallationUpdateAvailablePayload)

    // LSP events
    case lspClientDiagnostics(LspClientDiagnosticsPayload)
    case lspUpdated

    // Catalog / provider events
    case catalogModelUpdated
    case modelsDevRefreshed
    case pluginAdded(id: String)
    case accountChanged

    /// Streaming lifecycle events from the `session.next.*` family.
    ///
    /// The server emits these alongside the `message.*` events the UI already
    /// consumes; they are surfaced as one case so subscribers can react to
    /// generation progress without matching ~30 individual event names.
    case sessionStreamEvent(SessionStreamPayload)

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
        // `Permission` decodes both the v1 and v2 payload shapes and records which
        // one it saw, so the reply can be routed to the matching endpoint.
        case "permission.updated", "permission.asked", "permission.v2.asked":
            let payload = try decoder.decode(EventPayload<Permission>.self, from: jsonData)
            return .permissionUpdated(payload.properties)

        case "permission.replied", "permission.v2.replied":
            let payload = try decoder.decode(EventPayload<PermissionRepliedPayload>.self, from: jsonData)
            return .permissionReplied(payload.properties)

        case "question.asked", "question.v2.asked":
            let payload = try decoder.decode(EventPayload<QuestionRequest>.self, from: jsonData)
            return .questionAsked(payload.properties)

        case "question.replied", "question.v2.replied":
            let payload = try decoder.decode(EventPayload<QuestionRepliedPayload>.self, from: jsonData)
            return .questionReplied(payload.properties)

        case "question.rejected", "question.v2.rejected":
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

        // MARK: Project

        case "project.updated":
            let payload = try decoder.decode(EventPayload<Project>.self, from: jsonData)
            return .projectUpdated(payload.properties)

        case "project.directories.updated":
            let payload = try decoder.decode(EventPayload<ProjectIDPayload>.self, from: jsonData)
            return .projectDirectoriesUpdated(projectID: payload.properties.projectID)

        // MARK: Workspace / worktree

        case "workspace.ready":
            let payload = try decoder.decode(EventPayload<NamePayload>.self, from: jsonData)
            return .workspaceReady(name: payload.properties.name)

        case "workspace.failed":
            let payload = try decoder.decode(EventPayload<MessagePayload>.self, from: jsonData)
            return .workspaceFailed(message: payload.properties.message)

        case "workspace.status":
            let payload = try decoder.decode(EventPayload<WorkspaceStatusPayload>.self, from: jsonData)
            return .workspaceStatus(payload.properties)

        case "worktree.ready":
            let payload = try decoder.decode(EventPayload<WorktreeReadyPayload>.self, from: jsonData)
            return .worktreeReady(name: payload.properties.name, branch: payload.properties.branch)

        case "worktree.failed":
            let payload = try decoder.decode(EventPayload<MessagePayload>.self, from: jsonData)
            return .worktreeFailed(message: payload.properties.message)

        // MARK: MCP

        case "mcp.tools.changed":
            let payload = try decoder.decode(EventPayload<ServerNamePayload>.self, from: jsonData)
            return .mcpToolsChanged(server: payload.properties.server)

        case "mcp.browser.open.failed":
            let payload = try decoder.decode(EventPayload<McpBrowserOpenFailedPayload>.self, from: jsonData)
            return .mcpBrowserOpenFailed(payload.properties)

        // MARK: Catalog / providers / plugins

        case "catalog.model.updated", "catalog.updated":
            return .catalogModelUpdated

        case "models-dev.refreshed":
            return .modelsDevRefreshed

        case "integration.updated", "reference.updated":
            return .serverStateChanged(eventName)

        case "server.heartbeat":
            return .serverHeartbeat

        case "sync":
            // Duplicate of the plain event emitted next to it — see `syncEnvelope`.
            return .syncEnvelope

        case "plugin.added":
            let payload = try decoder.decode(EventPayload<IDPayload>.self, from: jsonData)
            return .pluginAdded(id: payload.properties.id)

        case "account.added", "account.removed", "account.switched":
            // Any account change invalidates the cached provider list.
            return .accountChanged

        case "global.disposed":
            return .globalDisposed

        default:
            // The `session.next.*` family carries streaming progress. They are
            // collapsed into one case so subscribers can observe generation
            // progress without enumerating every event name.
            if eventName.hasPrefix("session.next.") {
                let stage = String(eventName.dropFirst("session.next.".count))
                if let payload = try? decoder.decode(EventPayload<SessionStreamPayload>.self, from: jsonData) {
                    return .sessionStreamEvent(payload.properties.withStage(stage))
                }
                return .sessionStreamEvent(SessionStreamPayload(stage: stage, sessionID: ""))
            }
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

/// Payload of `permission.replied` / `permission.v2.replied`.
///
/// Older servers named the fields `permissionID` / `response`; current ones use
/// `requestID` / `reply`. Both are accepted.
struct PermissionRepliedPayload: Decodable, Sendable {
    let sessionID: String
    let requestID: String
    let reply: String

    /// Legacy alias for `requestID`.
    var permissionID: String { requestID }
    /// Legacy alias for `reply`.
    var response: String { reply }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
        case requestID
        case requestIDCamel = "requestId"
        case permissionID
        case permissionIDCamel = "permissionId"
        case permissionIDSnake = "permission_id"
        case reply
        case response
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID =
            (try? container.decodeIfPresent(String.self, forKey: .sessionID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDSnake))
            ?? ""
        requestID =
            (try? container.decodeIfPresent(String.self, forKey: .requestID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .requestIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .permissionID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .permissionIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .permissionIDSnake))
            ?? ""
        reply =
            (try? container.decodeIfPresent(String.self, forKey: .reply))
            ?? (try? container.decodeIfPresent(String.self, forKey: .response))
            ?? ""
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

// MARK: - Generic Single-Field Payloads

/// `{ id }` — used by `plugin.added`.
struct IDPayload: Decodable, Sendable {
    let id: String
}

/// `{ name }` — used by `workspace.ready`.
struct NamePayload: Decodable, Sendable {
    let name: String
}

/// `{ message }` — used by `workspace.failed` and `worktree.failed`.
struct MessagePayload: Decodable, Sendable {
    let message: String
}

/// `{ projectID }` — used by `project.directories.updated`.
struct ProjectIDPayload: Decodable, Sendable {
    let projectID: String
}

/// `{ server }` — used by `mcp.tools.changed`.
struct ServerNamePayload: Decodable, Sendable {
    let server: String
}

// MARK: - Workspace Payloads

/// Payload of `workspace.status`.
struct WorkspaceStatusPayload: Decodable, Sendable {
    enum Status: String, Decodable, Sendable {
        case connected
        case connecting
        case disconnected
        case error
    }

    let workspaceID: String
    let status: Status
}

/// Payload of `worktree.ready`.
struct WorktreeReadyPayload: Decodable, Sendable {
    let name: String
    let branch: String?
}

// MARK: - MCP Payloads

/// Payload of `mcp.browser.open.failed` — the host could not open the OAuth URL,
/// so the client should present it instead.
struct McpBrowserOpenFailedPayload: Decodable, Sendable {
    let mcpName: String
    let url: String
}

// MARK: - SessionStreamPayload

/// Payload of the `session.next.*` streaming event family.
///
/// The family covers text/reasoning/tool deltas, step boundaries, compaction, and
/// retries. All members share `sessionID` and a timestamp; the remaining fields
/// vary, so everything beyond the common core is optional. `stage` holds the event
/// name with the `session.next.` prefix stripped (e.g. `"text.delta"`).
struct SessionStreamPayload: Decodable, Sendable {
    /// Event name minus the `session.next.` prefix.
    var stage: String
    let sessionID: String
    let timestamp: Double?
    let messageID: String?
    let assistantMessageID: String?
    /// Incremental text for `text.delta`, `reasoning.delta`, `tool.input.delta`.
    let delta: String?
    /// Completed text for `*.ended` events.
    let text: String?
    let callID: String?
    /// Tool name for `tool.called`.
    let tool: String?
    let attempt: Int?
    let finish: String?
    let cost: Double?

    /// Whether this event carries streamed text the UI can append.
    var isTextDelta: Bool { stage == "text.delta" }
    /// Whether this event carries streamed reasoning the UI can append.
    var isReasoningDelta: Bool { stage == "reasoning.delta" }
    /// Whether this event ends an assistant step.
    var isStepEnd: Bool { stage == "step.ended" || stage == "step.failed" }

    private enum CodingKeys: String, CodingKey {
        case sessionID, timestamp, messageID, assistantMessageID
        case delta, text, callID, tool, attempt, finish, cost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stage = ""
        sessionID = (try? c.decodeIfPresent(String.self, forKey: .sessionID)) ?? ""
        timestamp = try? c.decodeIfPresent(Double.self, forKey: .timestamp)
        messageID = try? c.decodeIfPresent(String.self, forKey: .messageID)
        assistantMessageID = try? c.decodeIfPresent(String.self, forKey: .assistantMessageID)
        delta = try? c.decodeIfPresent(String.self, forKey: .delta)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        callID = try? c.decodeIfPresent(String.self, forKey: .callID)
        tool = try? c.decodeIfPresent(String.self, forKey: .tool)
        attempt = try? c.decodeIfPresent(Int.self, forKey: .attempt)
        finish = try? c.decodeIfPresent(String.self, forKey: .finish)
        cost = try? c.decodeIfPresent(Double.self, forKey: .cost)
    }

    init(stage: String, sessionID: String) {
        self.stage = stage
        self.sessionID = sessionID
        self.timestamp = nil
        self.messageID = nil
        self.assistantMessageID = nil
        self.delta = nil
        self.text = nil
        self.callID = nil
        self.tool = nil
        self.attempt = nil
        self.finish = nil
        self.cost = nil
    }

    /// Return a copy tagged with the event's stage.
    func withStage(_ stage: String) -> SessionStreamPayload {
        var copy = self
        copy.stage = stage
        return copy
    }
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

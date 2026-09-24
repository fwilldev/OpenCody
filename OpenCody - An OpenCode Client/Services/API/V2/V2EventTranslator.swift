import Foundation

// MARK: - V2EventTranslator

/// Turns the OpenCode 2.x event stream (`GET /api/event`) into the v1 events the app
/// already consumes.
///
/// 2.x is event-sourced: instead of publishing a changed message or part, it publishes
/// the fact that changed it (`session.text.delta`, `session.tool.called`, …) and each
/// client folds those into its own view — the server's `SessionMessageUpdater` is the
/// reference fold. This type performs the same fold, but emits the result as the v1
/// `message.updated` / `message.part.updated` / `message.part.delta` events, using the
/// part IDs `V2Adapter` derives for REST loads so both land on the same parts.
///
/// Output events are wrapped as v1 `GlobalEvent`s (`{ directory, payload }`), so
/// `SSEClient` can apply its usual directory filter and parser unchanged.
///
/// Events arrive strictly in order through one consumer, and a translation may await a
/// REST read (e.g. the full session after a rename), so this is an actor.
actor V2EventTranslator {
    typealias JSON = V2Adapter.JSON

    private let client: APIClient

    /// v1 assistant info per message ID, updated as steps progress.
    private var assistants: [String: JSON] = [:]
    /// v1 tool part per part ID, so each tool event can re-emit the whole part.
    private var tools: [String: JSON] = [:]
    /// Accumulated text per text/reasoning part ID, for deltas that arrive before a start.
    private var fragments: [String: String] = [:]
    /// User prompts announced by `session.inbox.enqueued`, awaiting delivery.
    private var pendingInbox: [String: JSON] = [:]
    /// Latest user message per session — the parent of the assistant reply.
    private var lastUserMessage: [String: String] = [:]
    /// Last known v1 session per ID, for `session.deleted` (which carries only the ID).
    private var sessions: [String: JSON] = [:]
    /// Transcript message ID per running shell, fixed by its start event.
    private var shellMessages: [String: String] = [:]

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Entry point

    /// Translate one raw SSE `data` payload into zero or more v1 `GlobalEvent` JSON strings.
    func translate(_ raw: String) async -> [String] {
        guard let data = raw.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? JSON,
              let type = event["type"] as? String
        else { return [] }

        let directory = (event["location"] as? JSON)?["directory"] as? String
        let payload = event["data"] as? JSON ?? [:]
        let created = event["created"] ?? Date().timeIntervalSince1970 * 1000

        var out: [String] = []
        func emit(_ name: String, _ properties: JSON) {
            var wrapper: JSON = ["payload": ["type": name, "properties": properties] as JSON]
            if let directory { wrapper["directory"] = directory }
            if let string = V2Adapter.string(from: wrapper) { out.append(string) }
        }

        let sessionID = payload["sessionID"] as? String ?? ""
        let messageID = payload["assistantMessageID"] as? String ?? ""

        switch type {
        // MARK: Connection & status
        case "server.connected":
            emit("server.connected", [:])
        case "global.disposed":
            emit("global.disposed", [:])
        case "session.status":
            emit("session.status", payload)
        case "session.idle":
            emit("session.idle", payload)

        // MARK: Session records
        case "session.created":
            if let session = await fetchSession(sessionID) { emit("session.created", ["info": session]) }
        case "session.renamed", "session.moved", "session.metadata.updated", "session.forked",
             "session.revert.staged", "session.revert.cleared", "session.revert.committed",
             "session.agent.selected", "session.model.selected":
            if let session = await fetchSession(sessionID) { emit("session.updated", ["info": session]) }
        // 2.x publishes no `session.status` of its own; a run's lifecycle is the
        // `session.execution.*` family, which v1 clients read as busy → idle.
        case "session.execution.started":
            emit("session.status", ["sessionID": sessionID, "status": ["type": "busy"] as JSON])
        case "session.execution.succeeded", "session.execution.failed", "session.execution.interrupted":
            // A shutdown interrupt keeps the run claimed; it resumes when the server returns.
            if type == "session.execution.interrupted", (payload["reason"] as? String) == "shutdown" { break }
            emit("session.status", ["sessionID": sessionID, "status": ["type": "idle"] as JSON])
            emit("session.idle", ["sessionID": sessionID])
            // Totals (cost, tokens) and generated titles settle when a run ends.
            if let session = await fetchSession(sessionID) { emit("session.updated", ["info": session]) }
        case "session.deleted":
            let session = sessions.removeValue(forKey: sessionID) ?? placeholderSession(sessionID, directory: directory)
            emit("session.deleted", ["info": session])
        case "session.compaction.ended":
            emit("session.compacted", ["sessionID": sessionID])

        // MARK: User messages
        case "session.inbox.enqueued":
            if let item = payload["item"] as? JSON, (item["type"] as? String) == "user",
               let inboxID = payload["inboxID"] as? String {
                pendingInbox[inboxID] = item["payload"] as? JSON ?? [:]
            }
        case "session.inbox.cancelled":
            if let inboxID = payload["inboxID"] as? String { pendingInbox.removeValue(forKey: inboxID) }
        case "session.inbox.delivered":
            guard let inboxID = payload["inboxID"] as? String else { break }
            let record: JSON?
            if let prompt = pendingInbox.removeValue(forKey: inboxID) {
                var message = prompt
                message["id"] = inboxID
                message["type"] = "user"
                message["time"] = ["created": created]
                record = V2Adapter.userMessage(message, sessionID: sessionID, agent: nil, model: nil)
            } else {
                // Enqueued before this stream connected — read the delivered message.
                record = await fetchMessage(sessionID: sessionID, messageID: inboxID)
            }
            guard let record, let info = record["info"] as? JSON else { break }
            if (info["role"] as? String) == "user" { lastUserMessage[sessionID] = inboxID }
            emitRecord(record, emit)

        // MARK: Assistant steps
        case "session.step.started":
            var info = assistants[messageID] ?? V2Adapter.assistantInfo(
                ["id": messageID], sessionID: sessionID, parentID: lastUserMessage[sessionID]
            )
            info["time"] = ["created": payload["started"] ?? created]
            if let agent = payload["agent"] { info["mode"] = agent }
            if let model = payload["model"] as? JSON {
                info["modelID"] = model["id"]
                info["providerID"] = model["providerID"]
            }
            info["finish"] = nil
            info["error"] = nil
            assistants[messageID] = info
            emit("message.updated", ["info": info])
        case "session.step.ended", "session.step.failed":
            var info = assistants[messageID] ?? V2Adapter.assistantInfo(
                ["id": messageID], sessionID: sessionID, parentID: lastUserMessage[sessionID]
            )
            var time = info["time"] as? JSON ?? ["created": created]
            time["completed"] = created
            info["time"] = time
            info["finish"] = payload["finish"] ?? (type == "session.step.failed" ? "error" : "stop")
            if let cost = payload["cost"] { info["cost"] = cost }
            if let tokens = payload["tokens"] { info["tokens"] = tokens }
            if let error = payload["error"] as? JSON { info["error"] = V2Adapter.messageError(error) }
            assistants[messageID] = info
            emit("message.updated", ["info": info])
            if type == "session.step.failed", let error = payload["error"] as? JSON {
                emit("session.error", ["sessionID": sessionID, "error": V2Adapter.messageError(error)])
            }

        // MARK: Text & reasoning
        case "session.text.started", "session.reasoning.started":
            let isText = type == "session.text.started"
            let id = partID(isText: isText, messageID: messageID, payload: payload)
            let text = fragments[id] ?? ""
            emitPart(isText ? textPart(id, messageID, sessionID, text)
                            : reasoningPart(id, messageID, sessionID, text, start: created, end: nil), emit)
        case "session.text.delta", "session.reasoning.delta":
            let isText = type == "session.text.delta"
            let id = partID(isText: isText, messageID: messageID, payload: payload)
            let delta = payload["delta"] as? String ?? ""
            fragments[id, default: ""] += delta
            emit("message.part.delta", [
                "sessionID": sessionID,
                "messageID": messageID,
                "partID": id,
                "field": "text",
                "delta": delta,
            ])
        case "session.text.ended", "session.reasoning.ended":
            let isText = type == "session.text.ended"
            let id = partID(isText: isText, messageID: messageID, payload: payload)
            fragments.removeValue(forKey: id)
            let text = payload["text"] as? String ?? ""
            emitPart(isText ? textPart(id, messageID, sessionID, text)
                            : reasoningPart(id, messageID, sessionID, text, start: nil, end: created), emit)

        // MARK: Tools
        case "session.tool.input.started":
            let callID = payload["id"] as? String ?? ""
            let id = V2Adapter.toolPartID(messageID: messageID, callID: callID)
            let part: JSON = [
                "id": id,
                "sessionID": sessionID,
                "messageID": messageID,
                "type": "tool",
                "callID": callID,
                "tool": payload["name"] as? String ?? "",
                "state": ["status": "pending", "input": JSON(), "raw": ""] as JSON,
            ]
            tools[id] = part
            emitPart(part, emit)
        case "session.tool.input.ended":
            updateTool(payload, messageID: messageID, sessionID: sessionID, emit) { state in
                state["raw"] = payload["text"] ?? ""
            }
        case "session.tool.called":
            updateTool(payload, messageID: messageID, sessionID: sessionID, emit) { state in
                state = [
                    "status": "running",
                    "input": payload["input"] as? JSON ?? [:],
                    "time": ["start": created],
                ]
            }
        case "session.tool.progress":
            updateTool(payload, messageID: messageID, sessionID: sessionID, emit) { state in
                guard (state["status"] as? String) == "running" else { return }
                let metadata = payload["metadata"] as? JSON ?? [:]
                state["metadata"] = metadata
                if let title = metadata["title"] as? String { state["title"] = title }
            }
        case "session.tool.success":
            updateTool(payload, messageID: messageID, sessionID: sessionID, emit) { state in
                let metadata = payload["metadata"] as? JSON
                let start = (state["time"] as? JSON)?["start"] ?? created
                var completed: JSON = [
                    "status": "completed",
                    "input": state["input"] as? JSON ?? [:],
                    "output": V2Adapter.contentText(payload["content"] as? [JSON] ?? []),
                    "title": metadata?["title"] as? String ?? "",
                    "time": ["start": start, "end": created],
                ]
                if let metadata { completed["metadata"] = metadata }
                state = completed
            }
        case "session.tool.failed":
            updateTool(payload, messageID: messageID, sessionID: sessionID, emit) { state in
                let start = (state["time"] as? JSON)?["start"] ?? created
                var failed: JSON = [
                    "status": "error",
                    "input": state["input"] as? JSON ?? [:],
                    "error": (payload["error"] as? JSON)?["message"] as? String ?? "Tool failed",
                    "time": ["start": start, "end": created],
                ]
                if let metadata = payload["metadata"] { failed["metadata"] = metadata }
                state = failed
            }

        // MARK: Shell runs
        case "session.shell.started", "session.shell.ended":
            guard let shell = payload["shell"] as? JSON, let shellID = shell["id"] as? String else { break }
            // The transcript names a shell message after its start event, as
            // `SessionMessage.ID.fromEvent` does: `evt_…` → `msg_…`.
            let eventID = event["id"] as? String ?? shellID
            let shellMessageID = type == "session.shell.started"
                ? eventID.replacingOccurrences(of: "evt_", with: "msg_")
                : shellMessages[shellID] ?? "msg_\(shellID)"
            if type == "session.shell.started" {
                shellMessages[shellID] = shellMessageID
            } else {
                shellMessages.removeValue(forKey: shellID)
            }
            var time: JSON = ["created": (shell["time"] as? JSON)?["started"] ?? created]
            if type == "session.shell.ended" { time["completed"] = created }
            var message: JSON = [
                "id": shellMessageID,
                "type": "shell",
                "shellID": shellID,
                "command": shell["command"] ?? "",
                "status": type == "session.shell.ended" ? (shell["status"] ?? "exited") : "running",
                "time": time,
            ]
            if let output = payload["output"] { message["output"] = output }
            emitRecord(V2Adapter.shellMessage(message, sessionID: sessionID), emit)

        // MARK: Permissions & questions
        case "permission.asked":
            emit("permission.v2.asked", V2Adapter.permission(payload))
        case "permission.replied":
            emit("permission.replied", payload)
        case "form.created":
            if let form = payload["form"] as? JSON, let question = V2Adapter.question(fromForm: form) {
                emit("question.asked", question)
            }
        case "form.replied":
            let answer = payload["answer"] as? JSON ?? [:]
            let answers: [[String]] = answer.keys.sorted { formIndex($0) < formIndex($1) }.map { key in
                if let list = answer[key] as? [String] { return list }
                if let value = answer[key] { return ["\(value)"] }
                return []
            }
            emit("question.replied", [
                "sessionID": payload["sessionID"] ?? "",
                "requestID": payload["id"] ?? "",
                "answers": answers,
            ])
        case "form.cancelled":
            emit("question.rejected", ["sessionID": payload["sessionID"] ?? "", "requestID": payload["id"] ?? ""])

        // MARK: Workspace
        case "project.updated":
            emit("project.updated", V2Adapter.project(payload))
        case "vcs.branch.updated":
            emit("vcs.branch.updated", payload)
        case "filesystem.changed":
            emit("file.watcher.updated", payload)
        case "mcp.tools.changed", "mcp.status.changed":
            emit("mcp.tools.changed", ["server": payload["server"] ?? ""])
        case "location.shutdown":
            emit("server.instance.disposed", ["directory": directory ?? ""])

        default:
            break
        }
        return out
    }

    // MARK: - Helpers

    private func partID(isText: Bool, messageID: String, payload: JSON) -> String {
        let ordinal = payload["ordinal"] as? Int ?? 0
        return isText
            ? V2Adapter.textPartID(messageID: messageID, ordinal: ordinal)
            : V2Adapter.reasoningPartID(messageID: messageID, ordinal: ordinal)
    }

    private func textPart(_ id: String, _ messageID: String, _ sessionID: String, _ text: String) -> JSON {
        V2Adapter.textPart(id: id, messageID: messageID, sessionID: sessionID, text: text)
    }

    private func reasoningPart(
        _ id: String, _ messageID: String, _ sessionID: String, _ text: String, start: Any?, end: Any?
    ) -> JSON {
        var time: JSON?
        if let start { time = ["created": start] }
        if let end { time = ["created": end, "completed": end] }
        return V2Adapter.reasoningPart(id: id, messageID: messageID, sessionID: sessionID, text: text, time: time)
    }

    private func emitPart(_ part: JSON, _ emit: (String, JSON) -> Void) {
        emit("message.part.updated", ["part": part])
    }

    /// Emit a `{ info, parts }` record as a message update followed by its parts.
    private func emitRecord(_ record: JSON, _ emit: (String, JSON) -> Void) {
        guard let info = record["info"] as? JSON else { return }
        emit("message.updated", ["info": info])
        for part in record["parts"] as? [JSON] ?? [] { emitPart(part, emit) }
    }

    /// Apply a state change to a tracked tool part and re-emit it.
    private func updateTool(
        _ payload: JSON,
        messageID: String,
        sessionID: String,
        _ emit: (String, JSON) -> Void,
        change: (inout JSON) -> Void
    ) {
        let callID = payload["id"] as? String ?? ""
        let id = V2Adapter.toolPartID(messageID: messageID, callID: callID)
        var part = tools[id] ?? [
            "id": id,
            "sessionID": sessionID,
            "messageID": messageID,
            "type": "tool",
            "callID": callID,
            "tool": payload["name"] as? String ?? "",
            "state": ["status": "pending", "input": JSON()] as JSON,
        ]
        var state = part["state"] as? JSON ?? [:]
        change(&state)
        part["state"] = state
        let status = state["status"] as? String
        if status == "completed" || status == "error" {
            tools.removeValue(forKey: id)
        } else {
            tools[id] = part
        }
        emitPart(part, emit)
    }

    /// `q3` → 3, so form answers keep question order.
    private func formIndex(_ key: String) -> Int {
        Int(key.drop { !$0.isNumber }) ?? Int.max
    }

    private func fetchSession(_ id: String) async -> JSON? {
        guard !id.isEmpty,
              let data = try? await client.v2Data(.get("/api/session/\(id)")) as? JSON
        else { return nil }
        let session = V2Adapter.session(data)
        sessions[id] = session
        return session
    }

    private func fetchMessage(sessionID: String, messageID: String) async -> JSON? {
        guard let data = try? await client.v2Data(.get("/api/session/\(sessionID)/message/\(messageID)")) as? JSON
        else { return nil }
        return V2Adapter.message(data, sessionID: sessionID)
    }

    /// Minimal v1 session for a deletion the translator never saw loaded.
    private func placeholderSession(_ id: String, directory: String?) -> JSON {
        V2Adapter.session(["id": id, "location": ["directory": directory ?? ""], "time": ["created": 0, "updated": 0]])
    }
}

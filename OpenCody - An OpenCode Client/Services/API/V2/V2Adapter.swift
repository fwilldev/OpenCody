import Foundation

// MARK: - V2Adapter

/// Translates OpenCode 2.x payloads into the shapes the app's v1 models decode.
///
/// 2.x is not a renamed v1: sessions carry a `location` instead of a directory, a
/// message is one typed record (`user`, `assistant`, `shell`, …) whose assistant
/// content is inline instead of a separate part list, and questions are generic
/// forms. Rather than teaching every model and view a second schema, each 2.x payload
/// is rebuilt as the equivalent v1 JSON and decoded with the existing `Codable` types.
/// The rest of the app never sees a 2.x shape.
///
/// Part identifiers do not exist in 2.x, so they are derived deterministically from
/// the message ID and the content item's position — `V2EventTranslator` derives the
/// same IDs from stream events, which is what lets live updates land on parts that
/// were loaded over REST.
nonisolated enum V2Adapter {
    typealias JSON = [String: Any]

    // MARK: - Decoding helpers

    /// Parse a response body into a JSON value.
    static func object(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw OpenCodeError.decoding(error)
        }
    }

    /// The `data` member of a `{ data, location?, cursor? }` envelope.
    static func envelope(from data: Data) throws -> Any {
        let root = try object(from: data)
        guard let object = root as? JSON, let payload = object["data"] else {
            throw OpenCodeError.decoding(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing `data` envelope"))
            )
        }
        return payload
    }

    /// Decode a v1 model from a JSON value built by this adapter.
    static func decode<T: Decodable>(_ type: T.Type, from value: Any) throws -> T {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as OpenCodeError {
            throw error
        } catch {
            throw OpenCodeError.decoding(error)
        }
    }

    /// Serialize a JSON value to a string (for synthesized SSE payloads).
    static func string(from value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Part identifiers

    static func textPartID(messageID: String, ordinal: Int) -> String { "\(messageID)-text-\(ordinal)" }
    static func reasoningPartID(messageID: String, ordinal: Int) -> String { "\(messageID)-reasoning-\(ordinal)" }
    static func toolPartID(messageID: String, callID: String) -> String { "\(messageID)-tool-\(callID)" }
    static func userTextPartID(messageID: String) -> String { "\(messageID)-text" }
    static func userFilePartID(messageID: String, index: Int) -> String { "\(messageID)-file-\(index)" }

    // MARK: - Sessions

    /// `Session.Info` → v1 `Session`.
    static func session(_ s: JSON) -> JSON {
        // The location is the session's working directory; `subpath` is that same
        // directory relative to the project root (v1 `path`). It can climb out with
        // `..` when the location was requested under another spelling of the folder
        // (`/tmp` vs `/private/tmp`), and is then meaningless.
        let directory = (s["location"] as? JSON)?["directory"] as? String ?? ""
        let subpath = (s["subpath"] as? String).flatMap { $0.hasPrefix("..") ? nil : $0 }

        let time = s["time"] as? JSON ?? [:]
        var v1Time: JSON = [
            "created": time["created"] ?? 0,
            "updated": time["updated"] ?? time["created"] ?? 0,
        ]
        if let archived = time["archived"] { v1Time["archived"] = archived }

        var out: JSON = [
            "id": s["id"] ?? "",
            "projectID": s["projectID"] ?? "",
            "directory": directory,
            "title": (s["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "New session",
            "version": "2",
            "time": v1Time,
        ]
        if let subpath, !subpath.isEmpty { out["path"] = subpath }
        if let parentID = s["parentID"] { out["parentID"] = parentID }
        if let agent = s["agent"] { out["agent"] = agent }
        // `Model.Ref` is `{ id, providerID, variant? }` — the same shape as v1 `SessionModel`.
        if let model = s["model"] as? JSON { out["model"] = model }
        if let cost = s["cost"] { out["cost"] = cost }
        if let tokens = s["tokens"] { out["tokens"] = tokens }
        if let revert = s["revert"] as? JSON {
            var v1Revert: JSON = ["messageID": revert["messageID"] ?? ""]
            if let partID = revert["partID"] { v1Revert["partID"] = partID }
            if let snapshot = revert["snapshot"] { v1Revert["snapshot"] = snapshot }
            out["revert"] = v1Revert
        }
        return out
    }

    // MARK: - Messages

    /// Agent/model most recently in effect, tracked while walking a transcript.
    private struct Selection {
        var agent: String?
        var model: JSON?
    }

    /// A 2.x transcript → v1 `{ info, parts }` records, in order.
    ///
    /// 2.x user messages carry no agent/model; v1 ones do, and the chat restores its
    /// pickers from the last user message. So each user message is stamped with the
    /// selection of the turn it started — the next assistant message's, falling back
    /// to the last explicit switch.
    static func messages(_ list: [JSON], sessionID: String) -> [JSON] {
        var output: [JSON] = []
        var selection = Selection()
        var lastUserID: String?

        for (index, message) in list.enumerated() {
            let type = message["type"] as? String
            switch type {
            case "agent-switched":
                selection.agent = message["agent"] as? String
            case "model-switched":
                selection.model = message["model"] as? JSON
            case "user":
                let upcoming = list[(index + 1)...].first { ($0["type"] as? String) == "assistant" }
                let agent = (upcoming?["agent"] as? String) ?? selection.agent
                let model = (upcoming?["model"] as? JSON) ?? selection.model
                output.append(userMessage(message, sessionID: sessionID, agent: agent, model: model))
                lastUserID = message["id"] as? String
            case "assistant":
                selection.agent = (message["agent"] as? String) ?? selection.agent
                selection.model = (message["model"] as? JSON) ?? selection.model
                output.append(assistantMessage(message, sessionID: sessionID, parentID: lastUserID))
            case "shell":
                output.append(shellMessage(message, sessionID: sessionID))
            case "compaction":
                if let compaction = compactionMessage(message, sessionID: sessionID) {
                    output.append(compaction)
                }
            default:
                // `synthetic`, `system`, `skill`, `idle`, `location-switched` are
                // bookkeeping records v1 had no message for.
                continue
            }
        }
        return output
    }

    /// One 2.x message → a v1 record, or `nil` for record types v1 has no message for.
    ///
    /// Used where a single message arrives on its own (live events, `GET …/message/{id}`),
    /// so the agent/model can only come from the message itself.
    static func message(_ message: JSON, sessionID: String) -> JSON? {
        messages([message], sessionID: sessionID).first
    }

    static func userMessage(_ m: JSON, sessionID: String, agent: String?, model: JSON?) -> JSON {
        let id = m["id"] as? String ?? ""
        let created = (m["time"] as? JSON)?["created"] ?? 0
        var info: JSON = [
            "id": id,
            "sessionID": sessionID,
            "role": "user",
            "time": ["created": created],
        ]
        if let agent { info["agent"] = agent }
        if let model, let modelID = model["id"], let providerID = model["providerID"] {
            info["model"] = ["providerID": providerID, "modelID": modelID]
        }

        var parts: [JSON] = []
        let text = m["text"] as? String ?? ""
        if !text.isEmpty || (m["files"] as? [JSON] ?? []).isEmpty {
            parts.append([
                "id": userTextPartID(messageID: id),
                "sessionID": sessionID,
                "messageID": id,
                "type": "text",
                "text": text,
            ])
        }
        for (index, file) in (m["files"] as? [JSON] ?? []).enumerated() {
            parts.append(filePart(file, id: userFilePartID(messageID: id, index: index), messageID: id, sessionID: sessionID))
        }
        return ["info": info, "parts": parts]
    }

    /// `Prompt.FileAttachment` → v1 `FilePart`.
    private static func filePart(_ file: JSON, id: String, messageID: String, sessionID: String) -> JSON {
        let mime = file["mime"] as? String ?? "application/octet-stream"
        var url: String?
        if let source = file["source"] as? JSON, (source["type"] as? String) == "uri" {
            url = source["uri"] as? String
        }
        if url == nil, let data = file["data"] as? String, !data.isEmpty {
            url = "data:\(mime);base64,\(data)"
        }
        var part: JSON = [
            "id": id,
            "sessionID": sessionID,
            "messageID": messageID,
            "type": "file",
            "mime": mime,
        ]
        if let name = file["name"] { part["filename"] = name }
        if let url { part["url"] = url }
        return part
    }

    /// v1 `AssistantMessage` info for a 2.x assistant record, without parts.
    static func assistantInfo(_ m: JSON, sessionID: String, parentID: String?) -> JSON {
        let time = m["time"] as? JSON ?? [:]
        var v1Time: JSON = ["created": time["created"] ?? 0]
        if let completed = time["completed"] { v1Time["completed"] = completed }

        var info: JSON = [
            "id": m["id"] ?? "",
            "sessionID": sessionID,
            "role": "assistant",
            "time": v1Time,
        ]
        if let parentID { info["parentID"] = parentID }
        if let agent = m["agent"] { info["mode"] = agent }
        if let model = m["model"] as? JSON {
            if let id = model["id"] { info["modelID"] = id }
            if let providerID = model["providerID"] { info["providerID"] = providerID }
        }
        if let cost = m["cost"] { info["cost"] = cost }
        if let tokens = m["tokens"] { info["tokens"] = tokens }
        if let finish = m["finish"] { info["finish"] = finish }
        if let error = m["error"] as? JSON { info["error"] = messageError(error) }
        return info
    }

    /// `Session.StructuredError` → v1 `MessageError` (`UnknownError`).
    static func messageError(_ error: JSON) -> JSON {
        ["name": "UnknownError", "data": ["message": error["message"] as? String ?? "Unknown error"]]
    }

    static func assistantMessage(_ m: JSON, sessionID: String, parentID: String?) -> JSON {
        let id = m["id"] as? String ?? ""
        let messageTime = m["time"] as? JSON ?? [:]
        var parts: [JSON] = []
        var textOrdinal = 0
        var reasoningOrdinal = 0

        for item in m["content"] as? [JSON] ?? [] {
            switch item["type"] as? String {
            case "text":
                parts.append(textPart(
                    id: textPartID(messageID: id, ordinal: textOrdinal),
                    messageID: id, sessionID: sessionID,
                    text: item["text"] as? String ?? ""
                ))
                textOrdinal += 1
            case "reasoning":
                parts.append(reasoningPart(
                    id: reasoningPartID(messageID: id, ordinal: reasoningOrdinal),
                    messageID: id, sessionID: sessionID,
                    text: item["text"] as? String ?? "",
                    time: item["time"] as? JSON
                ))
                reasoningOrdinal += 1
            case "tool":
                parts.append(toolPart(item, messageID: id, sessionID: sessionID, fallbackTime: messageTime))
            default:
                continue
            }
        }
        return ["info": assistantInfo(m, sessionID: sessionID, parentID: parentID), "parts": parts]
    }

    static func textPart(id: String, messageID: String, sessionID: String, text: String) -> JSON {
        ["id": id, "sessionID": sessionID, "messageID": messageID, "type": "text", "text": text]
    }

    static func reasoningPart(id: String, messageID: String, sessionID: String, text: String, time: JSON?) -> JSON {
        var part: JSON = ["id": id, "sessionID": sessionID, "messageID": messageID, "type": "reasoning", "text": text]
        if let time, let created = time["created"] {
            var range: JSON = ["start": created]
            if let completed = time["completed"] { range["end"] = completed }
            part["time"] = range
        }
        return part
    }

    /// `Session.Message.Assistant.Tool` → v1 `ToolPart`.
    static func toolPart(_ tool: JSON, messageID: String, sessionID: String, fallbackTime: JSON = [:]) -> JSON {
        let callID = tool["id"] as? String ?? ""
        let time = tool["time"] as? JSON ?? fallbackTime
        let state = tool["state"] as? JSON ?? [:]
        return [
            "id": toolPartID(messageID: messageID, callID: callID),
            "sessionID": sessionID,
            "messageID": messageID,
            "type": "tool",
            "callID": callID,
            "tool": tool["name"] as? String ?? "",
            "state": toolState(state, time: time, messageID: messageID, sessionID: sessionID),
        ]
    }

    /// 2.x tool state (`streaming | running | completed | error`) → v1 `ToolState`.
    static func toolState(_ state: JSON, time: JSON, messageID: String, sessionID: String) -> JSON {
        let start = time["ran"] ?? time["created"] ?? 0
        let metadata = state["metadata"] as? JSON
        let title = metadata?["title"] as? String
        let input = state["input"] as? JSON ?? [:]

        switch state["status"] as? String {
        case "streaming":
            return ["status": "pending", "input": [String: Any](), "raw": state["input"] as? String ?? ""]
        case "running":
            var out: JSON = ["status": "running", "input": input, "time": ["start": start]]
            if let metadata { out["metadata"] = metadata }
            if let title { out["title"] = title }
            return out
        case "completed":
            let content = state["content"] as? [JSON] ?? []
            var out: JSON = [
                "status": "completed",
                "input": input,
                "output": contentText(content),
                "title": title ?? "",
                "time": ["start": start, "end": time["completed"] ?? start],
            ]
            if let metadata { out["metadata"] = metadata }
            let attachments = fileAttachments(content, messageID: messageID, sessionID: sessionID)
            if !attachments.isEmpty { out["attachments"] = attachments }
            return out
        case "error":
            var out: JSON = [
                "status": "error",
                "input": input,
                "error": (state["error"] as? JSON)?["message"] as? String ?? "Tool failed",
                "time": ["start": start, "end": time["completed"] ?? start],
            ]
            if let metadata { out["metadata"] = metadata }
            return out
        default:
            return ["status": "pending", "input": input]
        }
    }

    /// Text of a tool's model-facing content, joined.
    static func contentText(_ content: [JSON]) -> String {
        content.compactMap { item in
            (item["type"] as? String) == "text" ? item["text"] as? String : nil
        }.joined(separator: "\n")
    }

    private static func fileAttachments(_ content: [JSON], messageID: String, sessionID: String) -> [JSON] {
        content.enumerated().compactMap { index, item in
            guard (item["type"] as? String) == "file", let uri = item["uri"] as? String else { return nil }
            var part: JSON = [
                "id": "\(messageID)-attachment-\(index)",
                "sessionID": sessionID,
                "messageID": messageID,
                "type": "file",
                "mime": item["mime"] as? String ?? "application/octet-stream",
                "url": uri,
            ]
            if let name = item["name"] as? String { part["filename"] = name }
            return part
        }
    }

    /// A session shell run (`!command`) → an assistant message with one `shell` tool part.
    static func shellMessage(_ m: JSON, sessionID: String) -> JSON {
        let id = m["id"] as? String ?? ""
        let time = m["time"] as? JSON ?? [:]
        let created = time["created"] ?? 0
        let running = (m["status"] as? String) == "running"
        let output = (m["output"] as? JSON)?["output"] as? String ?? ""
        let input: JSON = ["command": m["command"] ?? ""]

        let state: JSON = running
            ? ["status": "running", "input": input, "time": ["start": created]]
            : [
                "status": "completed",
                "input": input,
                "output": output,
                "title": m["command"] as? String ?? "",
                "time": ["start": created, "end": time["completed"] ?? created],
            ]

        var infoTime: JSON = ["created": created]
        if !running { infoTime["completed"] = time["completed"] ?? created }
        let info: JSON = [
            "id": id,
            "sessionID": sessionID,
            "role": "assistant",
            "time": infoTime,
            "mode": "shell",
        ]
        let part: JSON = [
            "id": toolPartID(messageID: id, callID: m["shellID"] as? String ?? id),
            "sessionID": sessionID,
            "messageID": id,
            "type": "tool",
            "callID": m["shellID"] as? String ?? id,
            "tool": "shell",
            "state": state,
        ]
        return ["info": info, "parts": [part]]
    }

    /// A finished compaction → an assistant message with a v1 `compaction` part.
    static func compactionMessage(_ m: JSON, sessionID: String) -> JSON? {
        guard (m["status"] as? String) == "completed" else { return nil }
        let id = m["id"] as? String ?? ""
        let created = (m["time"] as? JSON)?["created"] ?? 0
        let info: JSON = [
            "id": id,
            "sessionID": sessionID,
            "role": "assistant",
            "time": ["created": created, "completed": created],
            "summary": true,
        ]
        let part: JSON = [
            "id": "\(id)-compaction",
            "sessionID": sessionID,
            "messageID": id,
            "type": "compaction",
            "auto": (m["reason"] as? String) == "auto",
        ]
        return ["info": info, "parts": [part]]
    }

    // MARK: - Permissions & questions

    /// `Permission.Request` → the v2-variant payload `Permission` already decodes.
    ///
    /// Only the tool reference differs: 2.x names the call ID `id`.
    static func permission(_ p: JSON) -> JSON {
        var out = p
        if var source = p["source"] as? JSON, source["callID"] == nil, let id = source["id"] {
            source["callID"] = id
            out["source"] = source
        }
        return out
    }

    /// A question-style `Form.Info` → v1 `QuestionRequest`, or `nil` for other forms.
    ///
    /// 2.x asks questions through generic forms: the `question` tool turns each
    /// question into a `string` (single choice) or `multiselect` field with options,
    /// keyed `q0`, `q1`, … and tags the form `metadata.kind == "question"`.
    static func question(fromForm form: JSON) -> JSON? {
        let metadata = form["metadata"] as? JSON
        let fields = form["fields"] as? [JSON] ?? []
        let isQuestion = (metadata?["kind"] as? String) == "question"
        let answerable = !fields.isEmpty && fields.allSatisfy {
            let type = $0["type"] as? String
            return type == "string" || type == "multiselect"
        }
        guard isQuestion || answerable else { return nil }

        let questions: [JSON] = fields.map { field in
            let options: [JSON] = (field["options"] as? [JSON] ?? []).map {
                ["label": $0["label"] ?? $0["value"] ?? "", "description": $0["description"] ?? ""]
            }
            let title = field["title"] as? String
            return [
                "question": field["description"] as? String ?? title ?? "",
                "header": title ?? "",
                "options": options,
                "multiple": (field["type"] as? String) == "multiselect",
                "custom": field["custom"] as? Bool ?? true,
            ]
        }

        var out: JSON = [
            "id": form["id"] ?? "",
            "sessionID": form["sessionID"] ?? "",
            "questions": questions,
        ]
        if let tool = metadata?["tool"] as? JSON, let messageID = tool["messageID"], let callID = tool["id"] {
            out["tool"] = ["messageID": messageID, "callID": callID]
        }
        return out
    }

    /// v1 answers (one label array per question) → a `Form.Answer` for the given fields.
    static func formAnswer(_ answers: [QuestionAnswer], fields: [JSON]) -> JSON {
        var answer: JSON = [:]
        for (index, field) in fields.enumerated() {
            guard let key = field["key"] as? String, index < answers.count else { continue }
            let values = answers[index]
            if (field["type"] as? String) == "multiselect" {
                answer[key] = values
            } else if let first = values.first {
                answer[key] = first
            }
        }
        return answer
    }

    // MARK: - Catalog

    /// `Agent.Info` → v1 `Agent`. The v2 `id` is what prompts and switches refer to,
    /// so it becomes the v1 `name` (the app's identifier).
    static func agent(_ a: JSON) -> JSON {
        var out: JSON = [
            "name": a["id"] ?? a["name"] ?? "",
            "mode": a["mode"] ?? "all",
            "permission": [JSON](),
            "options": JSON(),
            "hidden": a["hidden"] as? Bool ?? false,
        ]
        if let description = a["description"] { out["description"] = description }
        if let color = a["color"] { out["color"] = color }
        if let system = a["system"] { out["prompt"] = system }
        if let model = a["model"] as? JSON, let id = model["id"], let providerID = model["providerID"] {
            out["model"] = ["modelID": id, "providerID": providerID]
        }
        return out
    }

    /// `Command.Info` → v1 `SlashCommand`.
    static func command(_ c: JSON) -> JSON {
        var out: JSON = ["name": c["name"] ?? "", "hints": [String]()]
        if let description = c["description"] { out["description"] = description }
        return out
    }

    /// `Skill.Info` → the app's `Skill`.
    static func skill(_ s: JSON) -> JSON {
        var out: JSON = [
            "name": s["name"] ?? s["id"] ?? "",
            "location": s["path"] ?? "",
            "content": s["content"] ?? "",
        ]
        if let description = s["description"] { out["description"] = description }
        return out
    }

    /// `Model.Info` → v1 `Model`.
    static func model(_ m: JSON, providerPackage: String?) -> JSON {
        let capabilities = m["capabilities"] as? JSON ?? [:]
        let inputs = Set(capabilities["input"] as? [String] ?? ["text"])
        let outputs = Set(capabilities["output"] as? [String] ?? ["text"])
        func modalities(_ set: Set<String>) -> JSON {
            [
                "text": set.contains("text"),
                "audio": set.contains("audio"),
                "image": set.contains("image"),
                "video": set.contains("video"),
                "pdf": set.contains("pdf"),
            ]
        }
        let variants = (m["variants"] as? [JSON] ?? []).compactMap { $0["id"] as? String }
        let compatibility = m["compatibility"] as? JSON

        // `cost` is a list of tiers; the untiered entry is the base price.
        let costs = m["cost"] as? [JSON] ?? []
        let base = costs.first { $0["tier"] == nil } ?? costs.first
        var cost: JSON = ["input": base?["input"] ?? 0, "output": base?["output"] ?? 0]
        if let cache = base?["cache"] as? JSON {
            cost["cache"] = ["read": cache["read"] ?? 0, "write": cache["write"] ?? 0]
        }

        let limit = m["limit"] as? JSON ?? [:]
        var v1Limit: JSON = ["context": limit["context"] ?? 0, "output": limit["output"] ?? 0]
        if let input = limit["input"] { v1Limit["input"] = input }

        var out: JSON = [
            "id": m["id"] ?? "",
            "providerID": m["providerID"] ?? "",
            "name": m["name"] ?? m["id"] ?? "",
            "api": ["id": m["modelID"] ?? m["id"] ?? "", "npm": m["package"] ?? providerPackage ?? ""],
            "status": m["status"] ?? "active",
            "capabilities": [
                "temperature": true,
                "reasoning": !variants.isEmpty || compatibility?["reasoningField"] != nil,
                "attachment": inputs.contains("image") || inputs.contains("pdf"),
                "toolcall": capabilities["tools"] as? Bool ?? true,
                "interleaved": compatibility?["reasoningField"] != nil,
                "input": modalities(inputs),
                "output": modalities(outputs),
            ],
            "cost": cost,
            "limit": v1Limit,
            "options": JSON(),
            "headers": m["headers"] as? JSON ?? [:],
            "variants": Dictionary(uniqueKeysWithValues: variants.map { ($0, JSON()) }),
        ]
        if let family = m["family"] { out["family"] = family }
        if let released = (m["time"] as? JSON)?["released"] as? Double, released > 0 {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            out["release_date"] = formatter.string(from: Date(timeIntervalSince1970: released / 1000))
        }
        return out
    }

    /// v1 `Provider` built from a 2.x provider (if available) and its enabled models.
    static func provider(id: String, name: String, package: String?, models: [JSON]) -> JSON {
        var modelMap: JSON = [:]
        for model in models {
            guard let modelID = model["id"] as? String else { continue }
            modelMap[modelID] = self.model(model, providerPackage: package)
        }
        return [
            "id": id,
            "name": name,
            "source": "api",
            "env": [String](),
            "options": JSON(),
            "models": modelMap,
        ]
    }

    // MARK: - MCP

    /// `Mcp.Server.status` → v1 `McpStatus`.
    static func mcpStatus(_ status: JSON) -> JSON {
        var out: JSON = ["status": status["status"] ?? "unknown"]
        if let error = status["error"] { out["error"] = error }
        return out
    }

    /// A 2.x MCP server config (`disabled`) → v1 `McpConfig` (`enabled`).
    static func mcpConfig(fromV2 c: JSON) -> JSON? {
        let enabled = !(c["disabled"] as? Bool ?? false)
        switch c["type"] as? String {
        case "local":
            var out: JSON = ["type": "local", "command": c["command"] ?? [String](), "enabled": enabled]
            if let cwd = c["cwd"] { out["cwd"] = cwd }
            if let environment = c["environment"] { out["environment"] = environment }
            return out
        case "remote":
            var out: JSON = ["type": "remote", "url": c["url"] ?? "", "enabled": enabled]
            if let headers = c["headers"] { out["headers"] = headers }
            if let oauth = c["oauth"] as? Bool, oauth == false { out["oauth"] = false }
            return out
        default:
            return nil
        }
    }

    /// A v1 `McpConfig` → the 2.x config shape, or `nil` for an enable-only override.
    static func mcpConfig(fromV1 config: McpConfig) -> JSON? {
        switch config {
        case .local(let c):
            var out: JSON = ["type": "local", "command": c.command, "disabled": !(c.enabled ?? true)]
            if let cwd = c.cwd { out["cwd"] = cwd }
            if let environment = c.environment { out["environment"] = environment }
            return out
        case .remote(let c):
            var out: JSON = ["type": "remote", "url": c.url, "disabled": !(c.enabled ?? true)]
            if let headers = c.headers { out["headers"] = headers }
            if case .disabled = c.oauth { out["oauth"] = false }
            return out
        case .enabledOverride:
            return nil
        }
    }

    // MARK: - Files & projects

    /// `Project` (2.x) → v1 `Project`.
    static func project(_ p: JSON) -> JSON {
        let time = p["time"] as? JSON ?? [:]
        var out: JSON = [
            "id": p["id"] ?? "",
            "worktree": p["canonical"] ?? "",
            "time": ["created": time["created"] ?? 0, "updated": time["updated"] ?? time["created"] ?? 0],
            "sandboxes": p["sandboxes"] ?? [String](),
        ]
        if let vcs = p["vcs"] { out["vcs"] = vcs }
        if let name = p["name"] { out["name"] = name }
        if let icon = p["icon"] { out["icon"] = icon }
        if let commands = p["commands"] { out["commands"] = commands }
        return out
    }

    /// `FileSystem.Entry` → v1 `FileNode`. Entry paths are relative to the location.
    static func fileNode(_ entry: JSON, root: String?) -> JSON {
        let path = entry["path"] as? String ?? ""
        let absolute: String
        if path.hasPrefix("/") {
            absolute = path
        } else if let root, !root.isEmpty {
            absolute = (root as NSString).appendingPathComponent(path)
        } else {
            absolute = path
        }
        return [
            "name": (path as NSString).lastPathComponent,
            "path": path,
            "absolute": absolute,
            "type": entry["type"] ?? "file",
            "ignored": false,
        ]
    }

    /// `Vcs.FileStatus` → v1 `ChangedFile`.
    static func changedFile(_ f: JSON) -> JSON {
        [
            "path": f["file"] ?? "",
            "added": f["additions"] ?? 0,
            "removed": f["deletions"] ?? 0,
            "status": f["status"] ?? "modified",
        ]
    }
}

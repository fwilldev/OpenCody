import Foundation

// MARK: - MessageAPI

/// Typed wrapper for all message-related REST endpoints.
///
/// Endpoints:
/// - `GET    /session/{id}/message`                         → list messages with parts
/// - `GET    /session/{id}/message/{messageID}`              → one message with parts
/// - `DELETE /session/{id}/message/{messageID}`              → delete a message
/// - `POST   /session/{id}/prompt_async`                     → send a prompt, return immediately
/// - `POST   /session/{id}/message`                          → send a prompt, await the reply
/// - `PATCH  /session/{id}/message/{messageID}/part/{partID}` → update a part
/// - `DELETE /session/{id}/message/{messageID}/part/{partID}` → delete a part
struct MessageAPI: Sendable {
    let client: APIClient

    /// Project directory that scopes every request made through this instance.
    ///
    /// These routes are session-scoped, and the server resolves which project
    /// instance answers from the `directory` query parameter. See `SessionAPI` for
    /// the full rationale — omitting it makes a server started outside the project
    /// answer for the wrong one.
    let directory: String?

    init(client: APIClient, directory: String? = nil) {
        self.client = client
        self.directory = directory
    }

    /// Query items for a request, always carrying `directory` when known.
    private func query(_ extra: [URLQueryItem] = []) -> [URLQueryItem]? {
        var items: [URLQueryItem] = []
        if let directory { items.append(URLQueryItem(name: "directory", value: directory)) }
        items.append(contentsOf: extra)
        return items.isEmpty ? nil : items
    }

    // MARK: - Response Types

    /// The API returns `{ info: Message, parts: [Part] }` for message endpoints.
    /// `MessageWithParts` in our models is not `Codable`, so this is the wire type.
    struct MessageWithPartsResponse: Codable, Sendable {
        let info: Message
        let parts: [Part]

        func toModel() -> MessageWithParts {
            MessageWithParts(message: info, parts: parts)
        }
    }

    // MARK: - Request Bodies

    private struct PromptBody: Encodable {
        let parts: [PromptPart]
        let model: ModelSelection?
        let agent: String?
        /// Client-chosen ID for the resulting user message.
        let messageID: String?
        /// Model variant (e.g. a reasoning-effort tier).
        let variant: String?
        /// Extra system prompt appended for this turn only.
        let system: String?
        /// Per-turn tool enable/disable overrides, keyed by tool ID.
        let tools: [String: Bool]?
        /// When `true`, record the message without generating a reply.
        let noReply: Bool?

        private enum CodingKeys: String, CodingKey {
            case parts, model, agent, messageID, variant, system, tools, noReply
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(parts, forKey: .parts)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(agent, forKey: .agent)
            try container.encodeIfPresent(messageID, forKey: .messageID)
            try container.encodeIfPresent(variant, forKey: .variant)
            try container.encodeIfPresent(system, forKey: .system)
            try container.encodeIfPresent(tools, forKey: .tools)
            try container.encodeIfPresent(noReply, forKey: .noReply)
        }

        struct ModelSelection: Encodable {
            let providerID: String
            let modelID: String
        }

        struct PromptPart: Encodable {
            let type: String
            let text: String?
            let mime: String?
            let filename: String?
            let url: String?

            private enum CodingKeys: String, CodingKey {
                case type, text, mime, filename, url
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(type, forKey: .type)
                try container.encodeIfPresent(text, forKey: .text)
                try container.encodeIfPresent(mime, forKey: .mime)
                try container.encodeIfPresent(filename, forKey: .filename)
                try container.encodeIfPresent(url, forKey: .url)
            }
        }
    }

    // MARK: - Reading

    /// List messages with their parts for a session.
    ///
    /// - Parameters:
    ///   - sessionID: The session to read.
    ///   - limit: Maximum number of messages to return, newest-anchored. `nil` returns all.
    ///   - before: Return only messages older than this message ID — used to page backwards.
    func list(
        sessionID: String,
        limit: Int? = nil,
        before: String? = nil
    ) async throws -> [MessageWithPartsResponse] {
        if client.apiVersion == .v2 { return try await v2List(sessionID: sessionID, limit: limit, before: before) }
        var extra: [URLQueryItem] = []
        if let limit { extra.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let before { extra.append(URLQueryItem(name: "before", value: before)) }
        let data = try await client.requestData(
            .get("/session/\(sessionID)/message", queryItems: query(extra))
        )
        do {
            return try JSONDecoder().decode([MessageWithPartsResponse].self, from: data)
        } catch {
            #if DEBUG
            print("[MessageAPI] decode error: \(error)")
            #endif
            throw error
        }
    }

    /// Get a single message with its parts.
    func get(sessionID: String, messageID: String) async throws -> MessageWithPartsResponse {
        if client.apiVersion == .v2 { return try await v2Get(sessionID: sessionID, messageID: messageID) }
        let data = try await client.requestData(.get("/session/\(sessionID)/message/\(messageID)", queryItems: query()))
        return try JSONDecoder().decode(MessageWithPartsResponse.self, from: data)
    }

    // MARK: - Sending

    /// Send a prompt to a session without waiting for the reply.
    ///
    /// Returns as soon as the server has accepted the prompt (`204 No Content`);
    /// the assistant's response streams in over SSE.
    func promptAsync(
        sessionID: String,
        text: String,
        modelID: String? = nil,
        providerID: String? = nil,
        agent: String? = nil,
        variant: String? = nil,
        system: String? = nil,
        tools: [String: Bool]? = nil,
        messageID: String? = nil,
        attachments: [PromptAttachment] = []
    ) async throws {
        if client.apiVersion == .v2 {
            // 2.x has no per-turn system prompt or tool overrides.
            return try await v2PromptAsync(
                sessionID: sessionID, text: text, modelID: modelID, providerID: providerID,
                agent: agent, variant: variant, messageID: messageID, attachments: attachments
            )
        }
        let body = makePromptBody(
            text: text,
            modelID: modelID,
            providerID: providerID,
            agent: agent,
            variant: variant,
            system: system,
            tools: tools,
            messageID: messageID,
            attachments: attachments
        )

        let endpoint = APIEndpoint(
            path: "/session/\(sessionID)/prompt_async",
            method: .POST,
            body: try JSONEncoder().encode(body),
            queryItems: query(),
            timeoutOverride: 300
        )
        try await client.requestVoid(endpoint)
    }

    /// Send a prompt and wait for the completed assistant message.
    ///
    /// Prefer `promptAsync` for interactive use — this blocks for the whole
    /// generation, which can take minutes.
    func prompt(
        sessionID: String,
        text: String,
        modelID: String? = nil,
        providerID: String? = nil,
        agent: String? = nil,
        variant: String? = nil,
        system: String? = nil,
        tools: [String: Bool]? = nil,
        messageID: String? = nil,
        attachments: [PromptAttachment] = []
    ) async throws -> MessageWithPartsResponse {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("Blocking prompts") }
        let body = makePromptBody(
            text: text,
            modelID: modelID,
            providerID: providerID,
            agent: agent,
            variant: variant,
            system: system,
            tools: tools,
            messageID: messageID,
            attachments: attachments
        )

        let endpoint = APIEndpoint(
            path: "/session/\(sessionID)/message",
            method: .POST,
            body: try JSONEncoder().encode(body),
            queryItems: query(),
            timeoutOverride: 900
        )
        let data = try await client.requestData(endpoint)
        return try JSONDecoder().decode(MessageWithPartsResponse.self, from: data)
    }

    // MARK: - Mutating

    /// Permanently delete a message and all of its parts.
    ///
    /// Unlike `SessionAPI.revert`, this does not undo file changes the message caused.
    func delete(sessionID: String, messageID: String) async throws {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("Deleting messages") }
        try await client.requestVoid(
            APIEndpoint(
                path: "/session/\(sessionID)/message/\(messageID)",
                method: .DELETE,
                queryItems: query(),
                contentType: .none
            )
        )
    }

    /// Delete a single part from a message.
    func deletePart(sessionID: String, messageID: String, partID: String) async throws {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("Deleting message parts") }
        try await client.requestVoid(
            APIEndpoint(
                path: "/session/\(sessionID)/message/\(messageID)/part/\(partID)",
                method: .DELETE,
                queryItems: query(),
                contentType: .none
            )
        )
    }

    /// Replace a part with an edited version.
    func updatePart(sessionID: String, messageID: String, part: Part) async throws -> Part {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("Editing message parts") }
        let data = try await client.requestData(
            APIEndpoint(
                path: "/session/\(sessionID)/message/\(messageID)/part/\(part.id)",
                method: .PATCH,
                body: try JSONEncoder().encode(part),
                queryItems: query()
            )
        )
        return try JSONDecoder().decode(Part.self, from: data)
    }

    // MARK: - Private

    /// Build the shared body for `prompt` and `promptAsync`.
    private func makePromptBody(
        text: String,
        modelID: String?,
        providerID: String?,
        agent: String?,
        variant: String?,
        system: String?,
        tools: [String: Bool]?,
        messageID: String?,
        attachments: [PromptAttachment]
    ) -> PromptBody {
        var parts: [PromptBody.PromptPart] = []

        // An empty text part is rejected by the server, so include it only when
        // there is something to send — an attachment-only prompt is valid.
        if !text.isEmpty || attachments.isEmpty {
            parts.append(
                PromptBody.PromptPart(type: "text", text: text, mime: nil, filename: nil, url: nil)
            )
        }

        for attachment in attachments {
            parts.append(
                PromptBody.PromptPart(
                    type: "file",
                    text: nil,
                    mime: attachment.mime,
                    filename: attachment.filename,
                    url: attachment.url
                )
            )
        }

        var modelSelection: PromptBody.ModelSelection? = nil
        if let modelID, let providerID {
            modelSelection = PromptBody.ModelSelection(providerID: providerID, modelID: modelID)
        }

        return PromptBody(
            parts: parts,
            model: modelSelection,
            agent: agent,
            messageID: messageID,
            variant: variant,
            system: system,
            tools: tools,
            noReply: nil
        )
    }
}

// MARK: - PromptAttachment

/// Describes a file attachment for a prompt.
struct PromptAttachment: Sendable {
    let mime: String
    let filename: String
    let url: String
}

import Foundation

// MARK: - MessageAPI

/// Typed wrapper for all message-related REST endpoints.
///
/// Endpoints:
/// - `GET  /session/{id}/message`            → list messages with parts
/// - `GET  /session/{id}/message/{messageID}` → get single message with parts
/// - `POST /session/{id}/message`             → prompt (async, returns 204)
struct MessageAPI: Sendable {
    let client: APIClient

    // MARK: - Response Types

    /// The API returns `{ info: Message, parts: [Part] }` for message endpoints.
    /// `MessageWithParts` in our models is NOT Codable, so we use this dedicated response type.
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

        private enum CodingKeys: String, CodingKey {
            case parts, model, agent
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(parts, forKey: .parts)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(agent, forKey: .agent)
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

    // MARK: - Endpoints

    /// List all messages with their parts for a session.
    func list(sessionID: String) async throws -> [MessageWithPartsResponse] {
        let data = try await client.requestData(.get("/session/\(sessionID)/message"))
        #if DEBUG
        if let raw = String(data: data, encoding: .utf8) {
            let preview = raw.prefix(3000)
        }
        #endif
        do {
            let result = try JSONDecoder().decode([MessageWithPartsResponse].self, from: data)
            #if DEBUG
            for r in result {
                let partTypes = r.parts.map { $0.type }.joined(separator: ", ")
            }
            #endif
            return result
        } catch {
            print("[MessageAPI] decode error: \(error)")
            throw error
        }
    }

    /// Get a single message with its parts.
    func get(sessionID: String, messageID: String) async throws -> MessageWithPartsResponse {
        let data = try await client.requestData(.get("/session/\(sessionID)/message/\(messageID)"))
        return try JSONDecoder().decode(MessageWithPartsResponse.self, from: data)
    }

    /// Send a text prompt to a session. Returns immediately (204 No Content).
    /// The actual response arrives via SSE events.
    func promptAsync(
        sessionID: String,
        text: String,
        modelID: String? = nil,
        providerID: String? = nil,
        agent: String? = nil,
        attachments: [PromptAttachment] = []
    ) async throws {
        var parts: [PromptBody.PromptPart] = [
            PromptBody.PromptPart(type: "text", text: text, mime: nil, filename: nil, url: nil)
        ]

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
        if let mID = modelID, let pID = providerID {
            modelSelection = PromptBody.ModelSelection(providerID: pID, modelID: mID)
        }

        let body = PromptBody(
            parts: parts,
            model: modelSelection,
            agent: agent
        )

        let encodedBody = try JSONEncoder().encode(body)

        #if DEBUG
        if let jsonString = String(data: encodedBody, encoding: .utf8) {
        }
        #endif

        let endpoint = APIEndpoint(
            path: "/session/\(sessionID)/prompt_async",
            method: .POST,
            body: encodedBody,
            timeoutOverride: 300
        )

        do {
            try await client.requestVoid(endpoint)
            #if DEBUG
            #endif
        } catch {
            #if DEBUG
            #endif
            throw error
        }
    }
}

// MARK: - PromptAttachment

/// Describes a file attachment for a prompt.
struct PromptAttachment: Sendable {
    let mime: String
    let filename: String
    let url: String
}

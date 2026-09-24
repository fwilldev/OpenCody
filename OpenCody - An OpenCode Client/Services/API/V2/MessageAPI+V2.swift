import Foundation

// MARK: - MessageAPI (OpenCode 2.x)

extension MessageAPI {
    private typealias JSON = V2Adapter.JSON

    /// The server caps one page at 200 messages.
    private static let pageSize = 200
    /// Upper bound on pages followed, so a misbehaving cursor cannot loop forever.
    private static let maxPages = 50

    /// Fetch the whole 2.x transcript, oldest first.
    private func v2Transcript(sessionID: String) async throws -> [JSON] {
        var all: [JSON] = []
        var seen: Set<String> = []
        var cursor: String?
        for _ in 0..<Self.maxPages {
            var items = [URLQueryItem(name: "limit", value: String(Self.pageSize))]
            if let cursor {
                items.append(URLQueryItem(name: "cursor", value: cursor))
            } else {
                items.append(URLQueryItem(name: "order", value: "asc"))
            }
            let root = try await client.v2JSON(.get("/api/session/\(sessionID)/message", queryItems: items))
            let object = root as? JSON ?? [:]
            // Keep only unseen records: a cursor that points back into already-read
            // pages then ends the walk instead of duplicating the transcript.
            let raw = object["data"] as? [JSON] ?? []
            let page = raw.filter { message in
                guard let id = message["id"] as? String else { return true }
                return seen.insert(id).inserted
            }
            all.append(contentsOf: page)
            // A short page is the last one; `next` is set whenever the page is non-empty.
            guard raw.count >= Self.pageSize, !page.isEmpty,
                  let next = (object["cursor"] as? JSON)?["next"] as? String, !next.isEmpty
            else {
                break
            }
            cursor = next
        }
        return all
    }

    func v2List(sessionID: String, limit: Int?, before: String?) async throws -> [MessageWithPartsResponse] {
        let transcript = try await v2Transcript(sessionID: sessionID)
        var records = V2Adapter.messages(transcript, sessionID: sessionID)
        await attachSessionDiff(to: &records, transcript: transcript, sessionID: sessionID)

        var responses = try V2Adapter.decode([MessageWithPartsResponse].self, from: records)
        if let before, let index = responses.firstIndex(where: { $0.info.id == before }) {
            responses = Array(responses[..<index])
        }
        if let limit, responses.count > limit {
            responses = Array(responses.suffix(limit))
        }
        return responses
    }

    /// Give the transcript the per-file diff v1 exposes on `UserMessage.summary.diffs`.
    ///
    /// 2.x keeps diffs out of the message records; `GET …/diff` computes them for a
    /// range of turns. One call covering every turn is attached to the first user
    /// message: `SessionChangeSet` sums diffs across messages, so session totals and
    /// the session diff view come out right, at the cost of per-turn attribution.
    /// Skipped entirely when no assistant step recorded changed files.
    private func attachSessionDiff(to records: inout [JSON], transcript: [JSON], sessionID: String) async {
        let changed = transcript.contains { message in
            guard (message["type"] as? String) == "assistant" else { return false }
            let files = (message["snapshot"] as? JSON)?["files"] as? [Any] ?? []
            return !files.isEmpty
        }
        let userIDs = transcript.filter { ($0["type"] as? String) == "user" }.compactMap { $0["id"] as? String }
        guard changed, let first = userIDs.first, let last = userIDs.last else { return }

        var items = [URLQueryItem(name: "from", value: first), URLQueryItem(name: "context", value: "3")]
        if last != first { items.append(URLQueryItem(name: "to", value: last)) }
        guard let diffs = try? await client.v2Data(.get("/api/session/\(sessionID)/diff", queryItems: items)),
              let index = records.firstIndex(where: { ($0["info"] as? JSON)?["id"] as? String == first }),
              var info = records[index]["info"] as? JSON
        else { return }
        info["summary"] = ["diffs": diffs]
        records[index]["info"] = info
    }

    func v2Get(sessionID: String, messageID: String) async throws -> MessageWithPartsResponse {
        let data = try await client.v2Data(.get("/api/session/\(sessionID)/message/\(messageID)"))
        guard let message = data as? JSON, let record = V2Adapter.message(message, sessionID: sessionID) else {
            throw OpenCodeError.notFound(message: "Message \(messageID)")
        }
        return try V2Adapter.decode(MessageWithPartsResponse.self, from: record)
    }

    /// Send a prompt. 2.x binds agent and model to the session rather than to each
    /// prompt, so a differing choice is applied as a session switch first.
    func v2PromptAsync(
        sessionID: String,
        text: String,
        modelID: String?,
        providerID: String?,
        agent: String?,
        variant: String?,
        messageID: String?,
        attachments: [PromptAttachment]
    ) async throws {
        try await v2ApplySelection(
            sessionID: sessionID, agent: agent, providerID: providerID, modelID: modelID, variant: variant
        )

        var body: JSON = ["text": text]
        if let messageID { body["id"] = messageID }
        if !attachments.isEmpty {
            body["files"] = attachments.map { ["uri": $0.url, "name": $0.filename] as JSON }
        }
        try await client.requestVoid(
            .v2("/api/session/\(sessionID)/prompt", method: .POST, json: body, timeout: 300)
        )
    }

    private func v2ApplySelection(
        sessionID: String,
        agent: String?,
        providerID: String?,
        modelID: String?,
        variant: String?
    ) async throws {
        guard agent != nil || (providerID != nil && modelID != nil) else { return }
        let current = try await client.v2Data(.get("/api/session/\(sessionID)")) as? JSON ?? [:]

        if let agent, (current["agent"] as? String) != agent {
            try await client.requestVoid(
                .v2("/api/session/\(sessionID)/agent", method: .POST, json: ["agent": agent])
            )
        }
        if let providerID, let modelID {
            let model = current["model"] as? JSON
            let same = (model?["id"] as? String) == modelID
                && (model?["providerID"] as? String) == providerID
                // The server reports an unset variant as "default".
                && ((model?["variant"] as? String) ?? "default") == (variant ?? "default")
            if !same {
                var ref: JSON = ["id": modelID, "providerID": providerID]
                if let variant { ref["variant"] = variant }
                try await client.requestVoid(
                    .v2("/api/session/\(sessionID)/model", method: .POST, json: ["model": ref])
                )
            }
        }
    }
}

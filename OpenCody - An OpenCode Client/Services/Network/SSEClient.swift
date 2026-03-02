import Foundation

// MARK: - SSEClientState

/// Internal state reported by SSEClient to its owner.
enum SSEClientState: Sendable {
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case disconnected
}

// MARK: - SSEClient

/// Low-level SSE stream parser with exponential-backoff reconnection.
///
/// `nonisolated` + all `let` stored properties → `Sendable`.
/// Mutable parsing / reconnection state lives entirely inside `connect()`.
///
/// Usage:
/// ```swift
/// let (stream, continuation) = AsyncStream<SSEEvent>.makeStream()
/// let client = SSEClient(apiClient: api, continuation: continuation, onStateChange: { _ in })
/// Task.detached { await client.connect() }
/// for await event in stream { … }
/// ```
nonisolated final class SSEClient: Sendable {

    // MARK: - Stored Properties (all let → Sendable)

    let apiClient: APIClient
    let continuation: AsyncStream<SSEEvent>.Continuation
    let onStateChange: @Sendable (SSEClientState) -> Void
    let directoryFilter: String?

    // MARK: - Constants

    private static let initialBackoff: TimeInterval = 1.0
    private static let maxBackoff: TimeInterval = 30.0

    // MARK: - Init

    init(
        apiClient: APIClient,
        continuation: AsyncStream<SSEEvent>.Continuation,
        onStateChange: @escaping @Sendable (SSEClientState) -> Void,
        directoryFilter: String? = nil
    ) {
        self.apiClient = apiClient
        self.continuation = continuation
        self.onStateChange = onStateChange
        self.directoryFilter = directoryFilter
    }

    // MARK: - Connect

    /// Runs the SSE read loop until the owning `Task` is cancelled.
    ///
    /// On stream failure the method waits with exponential backoff
    /// (1 s → 2 s → 4 s → 8 s → 16 s → 30 s max) then reconnects.
    /// Backoff resets to 1 s after a successful connection.
    /// `Last-Event-ID` is tracked locally and sent as a query parameter on reconnect.
    func connect() async {
        var currentBackoff: TimeInterval = Self.initialBackoff
        var lastEventID: String?
        var reconnectAttempt = 0

        defer { continuation.finish() }

        while !Task.isCancelled {
            do {
                // Build endpoint — include lastEventId on reconnects
                let endpoint = await makeEndpoint(lastEventID: lastEventID)

                onStateChange(reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt))

                let (bytes, _) = try await apiClient.streamBytes(endpoint)

                // Connection succeeded — reset backoff
                currentBackoff = Self.initialBackoff
                reconnectAttempt = 0
                onStateChange(.connected)

                // Parse SSE wire format
                try await parseStream(bytes: bytes, lastEventID: &lastEventID)

                // Stream ended normally (server closed) — reconnect
            } catch {
                if Task.isCancelled { break }
            }

            // Reconnect with backoff
            reconnectAttempt += 1
            onStateChange(.reconnecting(attempt: reconnectAttempt))

            do {
                try await Task.sleep(for: .seconds(currentBackoff))
            } catch {
                // Task cancelled during sleep
                break
            }

            currentBackoff = min(currentBackoff * 2, Self.maxBackoff)
        }

        onStateChange(.disconnected)
    }

    // MARK: - SSE Wire-Format Parser

    /// Reads lines from the byte stream and dispatches parsed SSE events.
    ///
    /// SSE wire format:
    /// ```
    /// event: <name>\n
    /// data: <payload line 1>\n
    /// data: <payload line 2>\n
    /// id: <event-id>\n
    /// \n                        ← blank line = dispatch
    /// ```
    private func parseStream(
        bytes: URLSession.AsyncBytes,
        lastEventID: inout String?
    ) async throws {
        var eventName = ""
        var dataLines: [String] = []
        var eventID: String?

        for try await line in bytes.lines {
            if Task.isCancelled { break }

            if line.isEmpty {
                // Blank line → dispatch accumulated event
                guard !dataLines.isEmpty else { continue }

                let data = dataLines.joined(separator: "\n")
                let normalized = normalizeEvent(eventName: eventName, data: data)
                let name = normalized.name

                if let id = eventID {
                    lastEventID = id
                }

                do {
                    let event = try await MainActor.run {
                        try SSEEvent.parse(eventName: name, data: normalized.data)
                    }
                    continuation.yield(event)
                } catch {
                    // Parsing failed — skip this event
                }

                // Reset accumulators
                eventName = ""
                dataLines = []
                eventID = nil

            } else if line.hasPrefix("event:") {
                eventName = stripFieldPrefix(line, prefixLength: 6)

            } else if line.hasPrefix("data:") {
                dataLines.append(stripFieldPrefix(line, prefixLength: 5))

            } else if line.hasPrefix("id:") {
                let value = stripFieldPrefix(line, prefixLength: 3)
                // SSE spec: id field must not contain NULL
                if !value.contains("\0") {
                    eventID = value
                }

            } else if line.hasPrefix("retry:") {
                // Retry directive — ignored (we use our own backoff strategy)

            } else if line.hasPrefix(":") {
                // Comment line — ignored
            }
        }
    }

    // MARK: - Helpers

    /// Builds the SSE endpoint, optionally appending `lastEventId` as a query parameter.
    private func makeEndpoint(lastEventID: String?) async -> APIEndpoint {
        await MainActor.run {
            var queryItems: [URLQueryItem]?
            if let directoryFilter, !directoryFilter.isEmpty {
                queryItems = [URLQueryItem(name: "directory", value: directoryFilter)]
            }
            if let lastEventID, !lastEventID.isEmpty {
                var items = queryItems ?? []
                items.append(URLQueryItem(name: "lastEventId", value: lastEventID))
                queryItems = items
            }
            let path = directoryFilter == nil || directoryFilter?.isEmpty == true ? "/global/event" : "/event"
            return APIEndpoint(
                path: path,
                method: .GET,
                queryItems: queryItems,
                contentType: .none
            )
        }
    }

    /// Strips the field prefix (e.g. `"event:"`) and optional leading space.
    ///
    /// Per SSE spec: "If the field value does not start with a U+0020 SPACE character,
    /// the field value is the value. Otherwise, remove the first SPACE."
    private func stripFieldPrefix(_ line: String, prefixLength: Int) -> String {
        let startIndex = line.index(line.startIndex, offsetBy: prefixLength)
        let remainder = line[startIndex...]
        if remainder.hasPrefix(" ") {
            return String(remainder.dropFirst())
        }
        return String(remainder)
    }

    /// Normalize SSE events that omit `event:` name and wrap payloads in GlobalEvent.
    /// When `event:` is missing, the server emits default "message" events.
    /// We extract the real event name from the JSON payload's `type` field.
    private func normalizeEvent(eventName: String, data: String) -> (name: String, data: String) {
        guard let jsonData = data.data(using: .utf8) else {
            return (eventName.isEmpty ? "message" : eventName, data)
        }

        if let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            if let payload = object["payload"] as? [String: Any],
               let type = payload["type"] as? String,
               let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let payloadString = String(data: payloadData, encoding: .utf8) {
                return (type, payloadString)
            }

            if let type = object["type"] as? String, (eventName.isEmpty || eventName == "message") {
                return (type, data)
            }
        }

        return (eventName.isEmpty ? "message" : eventName, data)
    }
}

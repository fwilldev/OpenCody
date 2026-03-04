import Foundation
import LDSwiftEventSource

// MARK: - SSEClientState

/// Internal state reported by SSEClient to its owner.
enum SSEClientState: Sendable {
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case disconnected
}

// MARK: - SSEClient

/// Low-level SSE client backed by LDSwiftEventSource.
///
/// Handles SSE connection, parsing, and reconnection via `LDSwiftEventSource.EventSource`.
/// Bridges the EventHandler callbacks to MainActor-safe closures.
///
/// Usage:
/// ```swift
/// let client = SSEClient(
///     baseURL: apiClient.baseURL,
///     authHeader: "Bearer token",
///     directoryFilter: "/some/dir",
///     onEvent: { event in … },
///     onStateChange: { state in … }
/// )
/// client.start()
/// // later:
/// client.stop()
/// ```
final class SSEClient {

    // MARK: - Stored Properties

    let baseURL: String
    let authHeader: String?
    let directoryFilter: String?
    let onEvent: @MainActor (SSEEvent) -> Void
    let onStateChange: @MainActor (SSEClientState) -> Void

    private var eventSource: EventSource?

    // MARK: - Init

    init(
        baseURL: String,
        authHeader: String?,
        directoryFilter: String?,
        onEvent: @escaping @MainActor (SSEEvent) -> Void,
        onStateChange: @escaping @MainActor (SSEClientState) -> Void
    ) {
        self.baseURL = baseURL
        self.authHeader = authHeader
        self.directoryFilter = directoryFilter
        self.onEvent = onEvent
        self.onStateChange = onStateChange
    }

    // MARK: - Start / Stop

    func start() {
        // Use /global/event — the server sends ALL events; we filter client-side by directory.
        // Note: /global/event does NOT accept a `directory` query parameter (only /event does).
        let urlString = baseURL + "/global/event"

        guard let url = URL(string: urlString) else { return }

        // Capture callbacks and state for use in the nonisolated handler
        let onEvent = self.onEvent
        let onStateChange = self.onStateChange
        let normalizeEventFn = self.normalizeEvent(eventName:data:)
        let shouldHandleEventFn = self.shouldHandleEvent(data:)

        // Thread-safe counter for reconnect attempts (called from LDSwiftEventSource's internal DispatchQueue)
        let reconnectCounter = Counter()

        let handler = Handler(
            onOpenedCallback: {
                Task { @MainActor in
                    onStateChange(.connected)
                }
            },
            onClosedCallback: {
                Task { @MainActor in
                    onStateChange(.disconnected)
                }
            },
            onMessageCallback: { eventType, messageEvent in
                let data = messageEvent.data

                guard shouldHandleEventFn(data) else { return }

                let normalized = normalizeEventFn(eventType, data)

                guard let event = try? SSEEvent.parse(eventName: normalized.name, data: normalized.data) else {
                    return
                }

                Task { @MainActor in
                    onEvent(event)
                }
            },
            onCommentCallback: { _ in },
            onErrorCallback: { error in
                reconnectCounter.increment()
                let attempt = reconnectCounter.value
                Task { @MainActor in
                    onStateChange(.reconnecting(attempt: attempt))
                }
            }
        )

        var config = EventSource.Config(handler: handler, url: url)
        if let authHeader {
            config.headers["Authorization"] = authHeader
        }
        config.reconnectTime = 1.0
        config.maxReconnectTime = 30.0
        config.connectionErrorHandler = { error in
            if let responseError = error as? UnsuccessfulResponseError {
                let code = responseError.responseCode
                if code == 401 || code == 403 {
                    return .shutdown
                }
            }
            return .proceed
        }

        let source = EventSource(config: config)
        eventSource = source

        Task { @MainActor in
            onStateChange(.connecting)
        }

        source.start()
    }

    func stop() {
        eventSource?.stop()
        eventSource = nil
    }

    // MARK: - Event Helpers

    /// Extracts the event type name and normalizes the data so `SSEEvent.parse` can decode it.
    ///
    /// Handles two server formats:
    /// - **Direct Event** (`/event`): `{"type":"…","properties":{…}}`
    /// - **GlobalEvent** (`/global/event`): `{"directory":"…","payload":{"type":"…","properties":{…}}}`
    ///
    /// In both cases, returns the event type string and a JSON string that
    /// `EventPayload<T>` can decode (i.e. contains a top-level `properties` key).
    private func normalizeEvent(eventName: String, data: String) -> (name: String, data: String) {
        guard let jsonData = data.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return (eventName.isEmpty ? "message" : eventName, data)
        }

        // Case 1: GlobalEvent wrapper — { directory, payload: { type, properties } }
        if let payload = object["payload"] as? [String: Any],
           let type = payload["type"] as? String {
            if let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let payloadString = String(data: payloadData, encoding: .utf8) {
                return (type, payloadString)
            }
        }

        // Case 2: Direct Event format — { type, properties }
        if let type = object["type"] as? String {
            return (type, data)
        }

        return (eventName.isEmpty ? "message" : eventName, data)
    }

    /// Client-side directory filter for `/global/event`.
    /// Events that don't match the configured directory are dropped.
    /// When no filter is set, all events pass through.
    ///
    /// Uses prefix matching: the event's directory is the opencode project root
    /// and the filter is the session directory which may be a subdirectory (or vice versa).
    private func shouldHandleEvent(data: String) -> Bool {
        guard let directoryFilter, !directoryFilter.isEmpty else { return true }
        guard let jsonData = data.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return true
        }
        guard let directory = object["directory"] as? String else { return true }
        return directoryFilter.hasPrefix(directory) || directory.hasPrefix(directoryFilter)
    }
}

// MARK: - Handler

/// Private EventHandler implementation that bridges LDSwiftEventSource callbacks.
private final class Handler: EventHandler, @unchecked Sendable {

    let onOpenedCallback: @Sendable () -> Void
    let onClosedCallback: @Sendable () -> Void
    let onMessageCallback: @Sendable (String, MessageEvent) -> Void
    let onCommentCallback: @Sendable (String) -> Void
    let onErrorCallback: @Sendable (Error) -> Void

    init(
        onOpenedCallback: @escaping @Sendable () -> Void,
        onClosedCallback: @escaping @Sendable () -> Void,
        onMessageCallback: @escaping @Sendable (String, MessageEvent) -> Void,
        onCommentCallback: @escaping @Sendable (String) -> Void,
        onErrorCallback: @escaping @Sendable (Error) -> Void
    ) {
        self.onOpenedCallback = onOpenedCallback
        self.onClosedCallback = onClosedCallback
        self.onMessageCallback = onMessageCallback
        self.onCommentCallback = onCommentCallback
        self.onErrorCallback = onErrorCallback
    }

    nonisolated func onOpened() {
        onOpenedCallback()
    }

    nonisolated func onClosed() {
        onClosedCallback()
    }

    nonisolated func onMessage(eventType: String, messageEvent: MessageEvent) {
        onMessageCallback(eventType, messageEvent)
    }

    nonisolated func onComment(comment: String) {
        onCommentCallback(comment)
    }

    nonisolated func onError(error: Error) {
        onErrorCallback(error)
    }
}

// MARK: - Counter

/// Thread-safe integer counter for reconnect attempt tracking.
private final class Counter: @unchecked Sendable {
    private var _value = 0
    private let lock = NSLock()

    var value: Int { lock.withLock { _value } }

    func increment() { lock.withLock { _value += 1 } }
}

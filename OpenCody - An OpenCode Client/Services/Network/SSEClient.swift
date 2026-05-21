import Foundation
import LDSwiftEventSource

// MARK: - SSEClientState

/// Internal state reported by SSEClient to its owner.
enum SSEClientState: Sendable {
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case disconnected
    case offline
}

// MARK: - SSEClient

/// Low-level SSE client backed by LDSwiftEventSource.
///
/// Handles SSE connection, parsing, and reconnection via `LDSwiftEventSource.EventSource`.
/// Bridges the EventHandler callbacks to MainActor-safe closures.
///
/// Features:
/// - **Serial event ordering**: Events are delivered through an `AsyncStream` to
///   guarantee strict ordering on MainActor, even under high throughput.
/// - **Heartbeat timeout**: If no event (including server comments) arrives within
///   `heartbeatTimeout` seconds, the client automatically reconnects to detect
///   silently-dropped TCP connections.
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
    let maxReconnectAttempts: Int

    /// Duration in seconds before a silent connection is considered dead.
    /// Matches the reference implementation's `HEARTBEAT_TIMEOUT_MS = 15_000`.
    let heartbeatTimeout: TimeInterval

    private var eventSource: EventSource?

    /// Serial event stream — events from LDSwiftEventSource's DispatchQueue are
    /// funnelled through this stream so that MainActor receives them in strict order.
    private var eventContinuation: AsyncStream<SSEEvent>.Continuation?
    private var eventConsumerTask: Task<Void, Never>?

    /// Heartbeat watchdog task — cancels & reconnects when no activity is detected.
    private var heartbeatTask: Task<Void, Never>?

    /// Thread-safe timestamp of the last received message or comment from the server.
    private let lastActivityAt = AtomicDate()

    // MARK: - Init

    init(
        baseURL: String,
        authHeader: String?,
        directoryFilter: String?,
        maxReconnectAttempts: Int = 5,
        heartbeatTimeout: TimeInterval = 15.0,
        onEvent: @escaping @MainActor (SSEEvent) -> Void,
        onStateChange: @escaping @MainActor (SSEClientState) -> Void
    ) {
        self.baseURL = baseURL
        self.authHeader = authHeader
        self.directoryFilter = directoryFilter
        self.maxReconnectAttempts = maxReconnectAttempts
        self.heartbeatTimeout = heartbeatTimeout
        self.onEvent = onEvent
        self.onStateChange = onStateChange
    }

    // MARK: - Start / Stop

    func start() {
        // Use /global/event — the server sends ALL events; we filter client-side by directory.
        // Note: /global/event does NOT accept a `directory` query parameter (only /event does).
        let urlString = baseURL + "/global/event"

        guard let url = URL(string: urlString) else { return }

        // --- Serial event stream ---
        // All parsed SSEEvents are yielded into this stream from LDSwiftEventSource's
        // internal DispatchQueue. A single consumer Task drains the stream on MainActor,
        // guaranteeing strict ordering.
        let (stream, continuation) = AsyncStream<SSEEvent>.makeStream()
        self.eventContinuation = continuation
        let onEvent = self.onEvent
        self.eventConsumerTask = Task { @MainActor in
            for await event in stream {
                onEvent(event)
            }
        }

        // Capture callbacks and state for use in the nonisolated handler
        let onStateChange = self.onStateChange
        let normalizeEventFn = self.normalizeEvent(eventName:data:)
        let shouldHandleEventFn = self.shouldHandleEvent(data:)
        let maxAttempts = self.maxReconnectAttempts
        let activityTracker = self.lastActivityAt

        // Thread-safe counter for reconnect attempts (called from LDSwiftEventSource's internal DispatchQueue)
        let reconnectCounter = Counter()

        let handler = Handler(
            onOpenedCallback: {
                reconnectCounter.reset()
                activityTracker.touch()
                Task { @MainActor in
                    onStateChange(.connected)
                }
            },
            onClosedCallback: {
                Task { @MainActor in
                    if reconnectCounter.hasReached(maxAttempts) {
                        onStateChange(.offline)
                    } else {
                        onStateChange(.disconnected)
                    }
                }
            },
            onMessageCallback: { eventType, messageEvent in
                activityTracker.touch()
                let data = messageEvent.data

                guard shouldHandleEventFn(data) else { return }

                let normalized = normalizeEventFn(eventType, data)

                let event: SSEEvent
                do {
                    event = try SSEEvent.parse(eventName: normalized.name, data: normalized.data)
                } catch {
                    print("[SSEClient] Failed to parse event '\(normalized.name)': \(error)")
                    return
                }

                // Yield into the serial stream instead of spawning a Task per event.
                continuation.yield(event)
            },
            onCommentCallback: { _ in
                // Server heartbeat comments (e.g., `: keepalive`) count as activity.
                activityTracker.touch()
            },
            onErrorCallback: { error in
                reconnectCounter.increment()
                let attempt = reconnectCounter.value
                Task { @MainActor in
                    if attempt >= maxAttempts {
                        onStateChange(.offline)
                    } else {
                        onStateChange(.reconnecting(attempt: attempt))
                    }
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
            if reconnectCounter.hasReached(maxAttempts) {
                return .shutdown
            }
            return .proceed
        }

        let source = EventSource(config: config)
        eventSource = source

        Task { @MainActor in
            onStateChange(.connecting)
        }

        source.start()

        // --- Heartbeat watchdog ---
        startHeartbeatWatchdog()
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        eventContinuation?.finish()
        eventContinuation = nil
        eventSource?.stop()
        eventSource = nil
    }

    /// Returns `true` if the connection has received activity recently.
    /// Used by ConnectionManager for foreground-reconnection checks.
    var isConnectionStale: Bool {
        guard let last = lastActivityAt.value else { return true }
        return Date().timeIntervalSince(last) > heartbeatTimeout
    }

    /// Force a reconnection cycle. Stops the current EventSource and restarts.
    /// Called by the heartbeat watchdog and by ConnectionManager on app-foreground.
    func reconnect() {
        guard eventSource != nil else { return }
        #if DEBUG
        print("[SSEClient] Reconnecting (heartbeat/foreground)")
        #endif
        // Stop & restart the underlying EventSource.
        // LDSwiftEventSource handles creating a new TCP connection.
        eventSource?.stop()
        eventSource?.start()
        lastActivityAt.touch()
    }

    // MARK: - Heartbeat Watchdog

    /// Periodically checks `lastActivityAt` and forces a reconnect if the connection
    /// has been silent for longer than `heartbeatTimeout`.
    private func startHeartbeatWatchdog() {
        heartbeatTask?.cancel()
        let timeout = heartbeatTimeout
        let activityTracker = lastActivityAt
        heartbeatTask = Task { [weak self] in
            // Check every half the timeout interval for responsiveness.
            let checkInterval = max(timeout / 2, 3.0)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(checkInterval))
                guard !Task.isCancelled else { break }
                guard let last = activityTracker.value else { continue }
                if Date().timeIntervalSince(last) > timeout {
                    #if DEBUG
                    print("[SSEClient] Heartbeat timeout — forcing reconnect")
                    #endif
                    await MainActor.run { [weak self] in
                        self?.reconnect()
                    }
                }
            }
        }
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

    func reset() { lock.withLock { _value = 0 } }

    func hasReached(_ limit: Int) -> Bool { lock.withLock { _value >= limit } }
}

// MARK: - AtomicDate

/// Thread-safe mutable `Date?` for tracking the last SSE activity timestamp.
/// Accessed from LDSwiftEventSource's internal DispatchQueue (writes) and
/// MainActor (reads for heartbeat check).
private final class AtomicDate: @unchecked Sendable {
    private var _date: Date?
    private let lock = NSLock()

    var value: Date? { lock.withLock { _date } }

    func touch() { lock.withLock { _date = Date() } }
}

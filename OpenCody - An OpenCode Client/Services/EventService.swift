import Foundation

// MARK: - ConnectionState

/// Represents the current state of the SSE event stream connection.
enum ConnectionState: Sendable, Equatable {
    case idle
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case disconnected(error: String?)

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.reconnecting(let a), .reconnecting(let b)):
            return a == b
        case (.disconnected(let a), .disconnected(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - EventService

/// Manages the SSE event stream connection to the OpenCode server.
///
/// Owns one `SSEClient`, publishes `connectionState`, and dispatches
/// parsed events to a registered callback.
///
/// Runs on `MainActor` (project default) — safe for SwiftUI observation.
@Observable
final class EventService {

    // MARK: - Published State

    /// Current connection state, observable by SwiftUI views.
    private(set) var connectionState: ConnectionState = .idle

    // MARK: - Event Dispatch

    /// Callback invoked on MainActor for each parsed SSE event.
    /// Set by the owning ConnectionManager to route events.
    @ObservationIgnored
    var onEvent: (@MainActor @Sendable (SSEEvent) -> Void)?

    // MARK: - Private State

    /// Task that runs the SSE connection + event consumption loop.
    private var connectionTask: Task<Void, Never>?

    /// Detached task running the nonisolated SSEClient.
    private var sseTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Start listening for SSE events from the server.
    ///
    /// Creates an `SSEClient`, opens the stream, and begins dispatching
    /// events through `onEvent`. Call `stopListening()` to tear down.
    ///
    /// - Parameter apiClient: The authenticated API client to use for the connection.
    func startListening(apiClient: APIClient, directoryFilter: String? = nil) {
        stopListening()
        connectionState = .connecting

        let (stream, continuation) = AsyncStream<SSEEvent>.makeStream()

        let client = SSEClient(
            apiClient: apiClient,
            continuation: continuation,
            onStateChange: { @Sendable [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleSSEStateChange(state)
                }
            },
            directoryFilter: directoryFilter
        )

        // Run SSEClient.connect() off-MainActor in a detached task
        sseTask = Task.detached {
            await client.connect()
        }

        // Consume events on MainActor
        connectionTask = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { break }
                self.onEvent?(event)
            }

            // Stream ended
            guard let self, !Task.isCancelled else { return }
            if case .connected = self.connectionState {
                self.connectionState = .disconnected(error: nil)
            }
        }
    }

    /// Stop listening and tear down all tasks.
    func stopListening() {
        sseTask?.cancel()
        connectionTask?.cancel()
        sseTask = nil
        connectionTask = nil

        if connectionState != .idle {
            connectionState = .idle
        }
    }

    // MARK: - Private

    /// Maps `SSEClientState` to our published `ConnectionState`.
    private func handleSSEStateChange(_ state: SSEClientState) {
        switch state {
        case .connecting:
            connectionState = .connecting
        case .connected:
            connectionState = .connected
        case .reconnecting(let attempt):
            connectionState = .reconnecting(attempt: attempt)
        case .disconnected:
            connectionState = .disconnected(error: nil)
        }
    }
}

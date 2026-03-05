import Foundation

// MARK: - ConnectionState

/// Represents the current state of the SSE event stream connection.
enum ConnectionState: Sendable, Equatable {
    case idle
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case disconnected(error: String?)
    case offline

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.connecting, .connecting),
             (.connected, .connected),
             (.offline, .offline):
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

// MARK: - ConnectionState → ConnectionStatus

extension ConnectionState {
    /// Maps connection state to the UI-facing `ConnectionStatus` for badges and indicators.
    var displayStatus: ConnectionStatus {
        switch self {
        case .connected: return .active
        case .connecting, .reconnecting: return .connecting
        case .disconnected(let error): return error != nil ? .error : .idle
        case .idle: return .idle
        case .offline: return .offline
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
    var connectionState: ConnectionState = .idle

    // MARK: - Event Dispatch

    /// Callback invoked on MainActor for each parsed SSE event.
    /// Set by the owning ConnectionManager to route events.
    @ObservationIgnored
    var onEvent: (@MainActor @Sendable (SSEEvent) -> Void)?

    // MARK: - Private State

    /// The active SSE client.
    private var sseClient: SSEClient?

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

        let client = SSEClient(
            baseURL: apiClient.baseURL,
            authHeader: apiClient.authorizationHeader,
            directoryFilter: directoryFilter,
            onEvent: { @MainActor [weak self] event in
                self?.onEvent?(event)
            },
            onStateChange: { @MainActor [weak self] state in
                self?.handleSSEStateChange(state)
            }
        )

        sseClient = client
        client.start()
    }

    /// Stop listening and tear down the SSE client.
    func stopListening() {
        sseClient?.stop()
        sseClient = nil

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
        case .offline:
            connectionState = .offline
        }
    }
}

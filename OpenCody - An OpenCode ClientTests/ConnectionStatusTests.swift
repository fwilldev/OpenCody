import Observation
import XCTest
@testable import OpenCody___An_OpenCode_Client

/// The server status the UI shows (`ConnectionManager.connectionState(for:)`) has to follow the
/// real connection, for views that only observe it and never poll.
///
/// The live tests are skipped unless `OPENCODY_V2_URL` (and `OPENCODY_V2_PASSWORD`) point at a
/// running OpenCode 2.x server; pass them with the `TEST_RUNNER_` prefix.
@MainActor
final class ConnectionStatusTests: XCTestCase {

    private func server(url: String, password: String = "") -> ServerConnection {
        let parts = URLComponents(string: url)
        let server = ServerConnection(
            name: "Status Test", hostname: parts?.host ?? "", port: parts?.port,
            useHTTPS: parts?.scheme == "https", username: "opencode", apiVersion: .v2
        )
        try? KeychainService.save(password: password, for: server.keychainIdentifier)
        addTeardownBlock { try? KeychainService.delete(for: server.keychainIdentifier) }
        return server
    }

    private func liveServer() throws -> ServerConnection {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["OPENCODY_V2_URL"], !url.isEmpty else { throw XCTSkip("OPENCODY_V2_URL not set") }
        return server(url: url, password: env["OPENCODY_V2_PASSWORD"] ?? "")
    }

    /// Waits for `state(for:)` to reach `expected` the way a view does: re-reading only when
    /// observation reports a change.
    private func waitForObservedState(
        _ expected: ConnectionState, of manager: ConnectionManager, server id: UUID, timeout: TimeInterval
    ) async -> ConnectionState {
        let deadline = Date().addingTimeInterval(timeout)
        var state = ConnectionState.idle
        while Date() < deadline {
            let changed = AsyncStream<Void> { continuation in
                state = withObservationTracking {
                    manager.connectionState(for: id)
                } onChange: {
                    continuation.yield()
                    continuation.finish()
                }
                if state == expected { continuation.finish() }
            }
            if state == expected { return state }
            let remaining = deadline.timeIntervalSinceNow
            let timedOut = await withTaskGroup(of: Bool.self) { group in
                group.addTask { for await _ in changed { return false }; return false }
                group.addTask {
                    try? await Task.sleep(for: .seconds(max(remaining, 0)))
                    return true
                }
                let first = await group.next() ?? true
                group.cancelAll()
                return first
            }
            if timedOut { break }
        }
        return state
    }

    func testStoringAConnectionNotifiesStatusObservers() async {
        let manager = ConnectionManager()
        // Nothing listens on port 1, so this stores an offline connection.
        let unreachable = server(url: "http://127.0.0.1:1")
        manager.connectAndActivate(server: unreachable)

        let state = await waitForObservedState(.offline, of: manager, server: unreachable.id, timeout: 10)
        XCTAssertEqual(state, .offline)
    }

    /// Launch and "Save Server" can both activate the same server before either connected.
    func testActivatingTwiceStillReportsConnected() async throws {
        let live = try liveServer()
        let manager = ConnectionManager()
        manager.connectAndActivate(server: live)
        manager.connectAndActivate(server: live)

        let state = await waitForObservedState(.connected, of: manager, server: live.id, timeout: 15)
        XCTAssertEqual(state, .connected)
        manager.disconnect(serverID: live.id)
    }

    /// The foreground and heartbeat checks reconnect a stream; that has to open it again,
    /// also when it hadn't opened yet (scene activation right after launch).
    func testReconnectOpensTheStreamAgain() async throws {
        let live = try liveServer()
        let client = APIClient(
            baseURL: live.baseURL, username: "opencode",
            password: ProcessInfo.processInfo.environment["OPENCODY_V2_PASSWORD"] ?? "", apiVersion: .v2
        )
        var opened = 0
        let sse = SSEClient(
            baseURL: client.baseURL, authHeader: client.authorizationHeader, directoryFilter: nil,
            heartbeatTimeout: 40, v2Translator: V2EventTranslator(client: client),
            onEvent: { _ in },
            onStateChange: { if case .connected = $0 { opened += 1 } }
        )
        defer { sse.stop() }

        sse.start()
        sse.reconnect()
        try await waitUntil(timeout: 10) { opened == 1 }
        XCTAssertEqual(opened, 1, "opens after a reconnect before the first open")

        sse.reconnect()
        try await waitUntil(timeout: 10) { opened == 2 }
        XCTAssertEqual(opened, 2, "opens again after reconnecting an open stream")
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}

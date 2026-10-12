import XCTest
@testable import OpenCody___An_OpenCode_Client

/// 1.8 features against live 1.x and 2.x servers: version detection, session rename,
/// paging and search, fork, project names, pairing. No model is called.
///
/// Each server is optional (pass with the `TEST_RUNNER_` prefix):
/// - `OPENCODY_V1_URL`, `OPENCODY_V1_PASSWORD` (optional), `OPENCODY_V1_DIR`
/// - `OPENCODY_V2_URL`, `OPENCODY_V2_PASSWORD`, `OPENCODY_V2_DIR`
@MainActor
final class ServerRenameIntegrationTests: XCTestCase {

    private struct Target {
        let version: ServerAPIVersion
        let url: String
        let username: String
        let password: String
        let directory: String
        var client: APIClient { APIClient(baseURL: url, username: username, password: password, apiVersion: version) }
    }

    private func targets() throws -> [Target] {
        let env = ProcessInfo.processInfo.environment
        var result: [Target] = []
        for (version, prefix, user) in [(ServerAPIVersion.v1, "OPENCODY_V1", ""), (.v2, "OPENCODY_V2", "opencode")] {
            guard let url = env["\(prefix)_URL"], let dir = env["\(prefix)_DIR"] else { continue }
            result.append(Target(version: version, url: url, username: user, password: env["\(prefix)_PASSWORD"] ?? "", directory: dir))
        }
        if result.isEmpty { throw XCTSkip("No OPENCODY_V1_* / OPENCODY_V2_* server configured") }
        return result
    }

    func testDetectsTheAPIVersion() async throws {
        for target in try targets() {
            let detected = try await APIClient.detectAPIVersion(baseURL: target.url, username: "", password: target.password)
            XCTAssertEqual(detected.apiVersion, target.version, target.url)
            XCTAssertFalse(detected.serverVersion.isEmpty)
        }
    }

    func testWrongVersionFailsTheHealthCheck() async throws {
        for target in try targets() {
            let other: ServerAPIVersion = target.version == .v1 ? .v2 : .v1
            let client = APIClient(baseURL: target.url, username: target.username, password: target.password, apiVersion: other)
            let healthy = (try? await client.healthCheck()) ?? false
            XCTAssertFalse(healthy, "\(target.url) must not pass as \(other)")
        }
    }

    func testRenamePageSearchAndForkSessions() async throws {
        for target in try targets() {
            let api = SessionAPI(client: target.client, directory: target.directory)
            let marker = "OpenCody-\(UUID().uuidString.prefix(8))"
            var created: [Session] = []
            defer { for session in created { Task { try? await api.delete(id: session.id) } } }

            for index in 0..<3 {
                created.append(try await api.create(title: "\(marker) \(index)"))
                try await Task.sleep(for: .milliseconds(20))
            }

            // Rename.
            let renamed = try await api.update(id: created[0].id, title: "\(marker) renamed")
            XCTAssertEqual(renamed.title, "\(marker) renamed", "\(target.version)")
            let reloaded = try await api.get(id: created[0].id)
            XCTAssertEqual(reloaded.title, "\(marker) renamed")

            // Search + paging: two pages of two, newest first, no duplicates.
            let first = try await api.page(limit: 2, search: marker)
            XCTAssertEqual(first.sessions.count, 2, "\(target.version)")
            let cursor = try XCTUnwrap(first.next, "\(target.version) has a second page")
            let second = try await api.page(limit: 2, cursor: cursor, search: marker)
            let ids = (first.sessions + second.sessions).map(\.id)
            XCTAssertEqual(Set(ids), Set(created.map(\.id)), "\(target.version)")
            XCTAssertEqual(ids.count, 3)
            XCTAssertNil(second.next)

            // Fork the whole history. 2.x refuses to fork a session without messages.
            do {
                let fork = try await api.fork(id: created[1].id)
                created.append(fork)
                XCTAssertNotEqual(fork.id, created[1].id)
            } catch OpenCodeError.validation(400, let message) where target.version == .v2 {
                XCTAssertTrue(message.contains("empty_session"), message)
            }
        }
    }

    func testProjectNameRoundTrip() async throws {
        for target in try targets() {
            let files = FileAPI(client: target.client)
            guard let project = try await files.listProjects().first(where: { $0.worktree == target.directory }) else {
                XCTFail("\(target.version): no project for \(target.directory)")
                continue
            }
            let original = project.name ?? ""
            let named = try await files.updateProject(projectID: project.id, name: "OpenCody Test")
            XCTAssertEqual(named.name, "OpenCody Test", "\(target.version)")
            let reset = try await files.updateProject(projectID: project.id, name: original)
            XCTAssertEqual(reset.name ?? "", original)
        }
    }

    func testPairingLinkRedeemsToAWorkingPassword() async throws {
        guard let target = try targets().first(where: { $0.version == .v2 }) else { throw XCTSkip("No 2.x server") }
        let link = try await PairingAPI.createLink(client: target.client)
        let parsed = try XCTUnwrap(PairingAPI.parse(link.url.absoluteString))
        let token = try await PairingAPI.redeem(parsed)
        let paired = APIClient(baseURL: target.url, username: PairingAPI.username, password: token, apiVersion: .v2)
        let healthy = try await paired.healthCheck()
        XCTAssertTrue(healthy)

        do {
            _ = try await PairingAPI.redeem(parsed)
            XCTFail("A pairing code works only once")
        } catch OpenCodeError.auth {}
    }
}

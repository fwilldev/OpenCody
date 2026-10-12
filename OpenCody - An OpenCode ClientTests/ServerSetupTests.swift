import XCTest
@testable import OpenCody___An_OpenCode_Client

/// Server setup: version detection and address parsing.
@MainActor
final class ServerSetupTests: XCTestCase {

    func testVersionIsJudgedFromTheBodyNotTheStatus() {
        let v2Info = Data(#"{"version":"2.0.27","pid":1,"urls":[],"paths":{"tmp":"/t"},"capabilities":{}}"#.utf8)
        let v1Health = Data(#"{"healthy":true,"version":"1.19.0"}"#.utf8)
        // Both generations answer unknown routes with their web app.
        let html = Data("<!doctype html><html></html>".utf8)

        XCTAssertEqual(APIClient.serverVersion(from: v2Info, apiVersion: .v2), "2.0.27")
        XCTAssertEqual(APIClient.serverVersion(from: v1Health, apiVersion: .v1), "1.19.0")
        XCTAssertNil(APIClient.serverVersion(from: html, apiVersion: .v2))
        XCTAssertNil(APIClient.serverVersion(from: html, apiVersion: .v1))
        XCTAssertNil(APIClient.serverVersion(from: v1Health, apiVersion: .v2))
        XCTAssertNil(APIClient.serverVersion(from: v2Info, apiVersion: .v1))
    }

    func testNewServersDefaultToV2() {
        XCTAssertEqual(ServerDraft().apiVersion, .v2)
        XCTAssertEqual(ServerAPIVersion.allCases.first, .v2)
    }

    func testPastedURLIsSplitIntoAddressFields() {
        var draft = ServerDraft()
        XCTAssertTrue(draft.applyURL(" https://box.local:4096/ "))
        XCTAssertEqual(draft.hostname, "box.local")
        XCTAssertEqual(draft.port, "4096")
        XCTAssertTrue(draft.useHTTPS)
        XCTAssertEqual(draft.baseURL, "https://box.local:4096")

        var plain = ServerDraft()
        plain.hostname = "192.168.1.5"
        XCTAssertFalse(plain.applyURL(plain.hostname))
        XCTAssertEqual(plain.hostname, "192.168.1.5")
    }

    func testDraftRoundTripsAnExistingServer() {
        let server = ServerConnection(name: "Box", hostname: "h", port: 4096, useHTTPS: true, username: "u", apiVersion: .v1)
        var draft = ServerDraft(server: server, password: "pw")
        XCTAssertEqual(draft.apiVersion, .v1)
        draft.port = ""
        draft.apply(to: server)
        XCTAssertNil(server.port)
        XCTAssertEqual(server.apiVersion, .v1)
        XCTAssertTrue(draft.canSave)
        draft.port = "abc"
        XCTAssertFalse(draft.canSave)
    }

    func testPairingLinkParsing() throws {
        let link = try XCTUnwrap(PairingAPI.parse(" https://box.local:4296/auth/connect/Ue6KIQ3z8y-bw7yJxfsgQQ "))
        XCTAssertEqual(link.code, "Ue6KIQ3z8y-bw7yJxfsgQQ")
        XCTAssertEqual(link.server.absoluteString, "https://box.local:4296")

        XCTAssertNil(PairingAPI.parse("https://box.local:4296/"))
        XCTAssertNil(PairingAPI.parse("ftp://box/auth/connect/abc"))
        XCTAssertNil(PairingAPI.parse("not a link"))

        var draft = ServerDraft()
        draft.apiVersion = .v1
        draft.apply(pairing: link, token: "tok")
        XCTAssertEqual(draft.hostname, "box.local")
        XCTAssertEqual(draft.port, "4296")
        XCTAssertTrue(draft.useHTTPS)
        XCTAssertEqual(draft.username, "opencode")
        XCTAssertEqual(draft.password, "tok")
        XCTAssertEqual(draft.apiVersion, .v2)
        XCTAssertEqual(draft.name, "box.local")
    }

    func testV2UsernameDefaultsToOpencode() {
        var draft = ServerDraft()
        XCTAssertEqual(draft.effectiveUsername, "opencode")
        draft.apiVersion = .v1
        XCTAssertEqual(draft.effectiveUsername, "")
    }
}

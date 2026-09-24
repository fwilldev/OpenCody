import XCTest
@testable import OpenCody___An_OpenCode_Client

/// Tests for the MCP model layer and the command tokenizer.
///
/// The JSON here is captured verbatim from a live opencode server (v1.16.2) — the
/// `GET /global/config` and `GET /mcp` responses after configuring servers through
/// `PATCH /global/config`.
final class MCPTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - McpConfig

    /// The regression that mattered most: an `mcp` entry with no `type`.
    ///
    /// The config schema allows `{ "enabled": Bool }` as a way to toggle a server
    /// declared elsewhere in the config chain. Requiring `type` made the whole
    /// `GET /config` response undecodable, not just that one entry.
    func testEnabledOverrideEntryDecodes() throws {
        let json = """
        {"$schema":"https://opencode.ai/config.json",
         "mcp":{"claudetest":{"type":"local","command":["echo","hello"],
                              "environment":{"FOO":"bar"},"enabled":true},
                "defined elsewhere":{"enabled":false}}}
        """
        let config = try decode(ServerConfig.self, json)
        let mcp = try XCTUnwrap(config.mcp)
        XCTAssertEqual(mcp.count, 2)

        guard case .enabledOverride(let enabled) = try XCTUnwrap(mcp["defined elsewhere"]) else {
            return XCTFail("Expected an enabled-override entry")
        }
        XCTAssertFalse(enabled)

        guard case .local(let local) = try XCTUnwrap(mcp["claudetest"]) else {
            return XCTFail("Expected a local entry")
        }
        XCTAssertEqual(local.command, ["echo", "hello"])
        XCTAssertEqual(local.environment?["FOO"], "bar")
        XCTAssertEqual(local.enabled, true)
    }

    func testLocalConfigRoundTripsCwdAndTimeout() throws {
        let original = McpLocalConfig(
            command: ["npx", "-y", "server"],
            cwd: "/srv/app",
            environment: ["TOKEN": "abc"],
            enabled: true,
            timeout: 15000
        )
        let data = try JSONEncoder().encode(McpConfig.local(original))
        guard case .local(let decoded) = try JSONDecoder().decode(McpConfig.self, from: data) else {
            return XCTFail("Expected a local entry")
        }
        XCTAssertEqual(decoded.type, "local")
        XCTAssertEqual(decoded.cwd, "/srv/app")
        XCTAssertEqual(decoded.timeout, 15000)
        XCTAssertEqual(decoded.command, ["npx", "-y", "server"])
    }

    /// `oauth: false` is a valid value and means "do not auto-detect OAuth".
    func testRemoteConfigDecodesOAuthFalse() throws {
        let json = """
        {"type":"remote","url":"https://mcp.example.com/mcp","oauth":false,
         "headers":{"Authorization":"Bearer x"}}
        """
        guard case .remote(let remote) = try decode(McpConfig.self, json) else {
            return XCTFail("Expected a remote entry")
        }
        XCTAssertEqual(remote.url, "https://mcp.example.com/mcp")
        XCTAssertEqual(remote.headers?["Authorization"], "Bearer x")
        guard case .disabled = try XCTUnwrap(remote.oauth) else {
            return XCTFail("Expected oauth to be disabled")
        }
    }

    func testRemoteConfigDecodesOAuthSettings() throws {
        let json = """
        {"type":"remote","url":"https://mcp.example.com/mcp",
         "oauth":{"clientId":"abc","scope":"read write"}}
        """
        guard case .remote(let remote) = try decode(McpConfig.self, json),
              case .settings(let oauth) = try XCTUnwrap(remote.oauth) else {
            return XCTFail("Expected oauth settings")
        }
        XCTAssertEqual(oauth.clientId, "abc")
        XCTAssertEqual(oauth.scope, "read write")
    }

    /// Encoding must omit unset optionals — the write is a deep merge server-side, so
    /// an explicit null or empty value would be merged in as real content.
    func testEncodingOmitsUnsetFields() throws {
        let data = try JSONEncoder().encode(McpConfig.local(McpLocalConfig(command: ["x"])))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("cwd"))
        XCTAssertFalse(json.contains("environment"))
        XCTAssertFalse(json.contains("timeout"))
        XCTAssertFalse(json.contains("null"))
    }

    func testSettingEnabledPreservesDefinition() throws {
        let config = McpConfig.remote(McpRemoteConfig(url: "https://x/mcp", headers: ["A": "b"]))
        guard case .remote(let updated) = config.settingEnabled(false) else {
            return XCTFail("Expected a remote entry")
        }
        XCTAssertEqual(updated.enabled, false)
        XCTAssertEqual(updated.url, "https://x/mcp")
        XCTAssertEqual(updated.headers?["A"], "b")
    }

    // MARK: - McpStatus

    func testStatusMapDecodes() throws {
        // Captured from GET /mcp.
        let json = """
        {"claudetest":{"status":"failed","error":"MCP error -32000: Connection closed"},
         "linear":{"status":"needs_auth"},
         "fs":{"status":"connected"},
         "off":{"status":"disabled"}}
        """
        let map = try decode(MCPAPI.McpStatusMap.self, json)
        XCTAssertEqual(map["fs"], .connected)
        XCTAssertEqual(map["off"], .disabled)
        XCTAssertEqual(map["linear"], .needsAuth)
        XCTAssertEqual(map["claudetest"]?.errorDetail, "MCP error -32000: Connection closed")
    }

    /// An unknown status must not take the whole map down with it.
    func testUnknownStatusDegradesGracefully() throws {
        let json = """
        {"fs":{"status":"connected"},"weird":{"status":"reticulating_splines"}}
        """
        let map = try decode(MCPAPI.McpStatusMap.self, json)
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map["fs"], .connected)
        XCTAssertEqual(map["weird"], .unknown(status: "reticulating_splines"))
    }

    /// Reconnecting cannot clear these states, so the UI must not offer a retry.
    func testAuthStatesAreNotConnectActionable() {
        XCTAssertFalse(McpStatus.needsAuth.isConnectActionable)
        XCTAssertFalse(McpStatus.needsClientRegistration(error: "no dcr").isConnectActionable)
        XCTAssertFalse(McpStatus.connected.isConnectActionable)
        XCTAssertTrue(McpStatus.disabled.isConnectActionable)
        XCTAssertTrue(McpStatus.failed(error: "boom").isConnectActionable)
    }

    // MARK: - Path Encoding

    /// Interpolating a raw name into a path silently truncates the request at the
    /// first `#` or `?`: `URLComponents` reads the remainder as a fragment or query,
    /// so `/mcp/a#b/connect` is sent as `/mcp/a` — a different route, and in the `?`
    /// case the `directory` query is destroyed too. Encoding the segment fixes it.
    func testRawNameTruncatesPathAtDelimiters() throws {
        let broken = try XCTUnwrap(URLComponents(string: "http://h/mcp/a#b/connect"))
        XCTAssertEqual(broken.path, "/mcp/a")

        let fixed = try XCTUnwrap(URLComponents(string: "http://h/mcp/\(APIEndpoint.segment("a#b"))/connect"))
        XCTAssertEqual(fixed.path, "/mcp/a#b/connect")
    }

    /// A raw `/` in a name adds a path segment instead of naming the server.
    func testRawNameWithSlashAddsPathSegment() throws {
        let broken = try XCTUnwrap(URLComponents(string: "http://h/mcp/a/b/connect"))
        XCTAssertEqual(broken.path, "/mcp/a/b/connect")

        let fixed = try XCTUnwrap(URLComponents(string: "http://h/mcp/\(APIEndpoint.segment("a/b"))/connect"))
        XCTAssertEqual(fixed.path, "/mcp/a/b/connect")
        // The difference that matters: the encoded form survives to the wire.
        XCTAssertEqual(fixed.url?.absoluteString, "http://h/mcp/a%2Fb/connect")
    }

    func testSegmentEncodesDelimitersAndLeavesPlainNamesAlone() {
        XCTAssertEqual(APIEndpoint.segment("a/b"), "a%2Fb")
        XCTAssertEqual(APIEndpoint.segment("a#b"), "a%23b")
        XCTAssertEqual(APIEndpoint.segment("a?b"), "a%3Fb")
        XCTAssertEqual(APIEndpoint.segment("a%b"), "a%25b")
        XCTAssertEqual(APIEndpoint.segment("defined elsewhere"), "defined%20elsewhere")
        XCTAssertEqual(APIEndpoint.segment("plain-name_1"), "plain-name_1")
    }

    // MARK: - Command Tokenizer

    func testTokenizerSplitsOnWhitespace() {
        XCTAssertEqual(
            CommandTokenizer.tokenize("npx -y @modelcontextprotocol/server-filesystem /srv"),
            ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/srv"]
        )
    }

    /// The case that made naive splitting wrong: a path containing a space.
    func testTokenizerHonoursQuotes() {
        XCTAssertEqual(
            CommandTokenizer.tokenize(#"uv --directory "/Users/me/My Projects/mcp" run server"#),
            ["uv", "--directory", "/Users/me/My Projects/mcp", "run", "server"]
        )
        XCTAssertEqual(CommandTokenizer.tokenize("echo 'a b'"), ["echo", "a b"])
    }

    func testTokenizerHonoursBackslashEscapes() {
        XCTAssertEqual(
            CommandTokenizer.tokenize(#"cmd /Users/me/My\ Folder/x"#),
            ["cmd", "/Users/me/My Folder/x"]
        )
        // Inside single quotes a backslash is literal, as in POSIX shells.
        XCTAssertEqual(CommandTokenizer.tokenize(#"cmd 'a\b'"#), ["cmd", #"a\b"#])
    }

    func testTokenizerCollapsesRepeatedWhitespace() {
        XCTAssertEqual(CommandTokenizer.tokenize("  a   b\t c  "), ["a", "b", "c"])
        XCTAssertEqual(CommandTokenizer.tokenize("   "), [])
        XCTAssertEqual(CommandTokenizer.tokenize(""), [])
    }

    /// An explicitly empty argument is a real argument and must survive.
    func testTokenizerKeepsExplicitEmptyArgument() {
        XCTAssertEqual(CommandTokenizer.tokenize(#"cmd "" x"#), ["cmd", "", "x"])
    }

    func testTokenizerRoundTripsThroughRender() {
        let argv = ["uv", "--directory", "/Users/me/My Projects/x", "run", "a\"b"]
        XCTAssertEqual(CommandTokenizer.tokenize(CommandTokenizer.render(argv)), argv)
    }

    // MARK: - Merge Limits

    /// The server merges config writes and cannot delete keys, so a removed
    /// environment variable survives. Detecting it is what lets the UI say so.
    func testStrandedKeysDetectsRemovedEnvironmentVariables() {
        let before = McpConfig.local(McpLocalConfig(command: ["x"], environment: ["A": "1", "B": "2"]))
        let after = McpConfig.local(McpLocalConfig(command: ["x"], environment: ["A": "1"]))
        XCTAssertEqual(MCPConfigWriter.strandedKeys(from: before, to: after), ["B"])
    }

    func testStrandedKeysEmptyWhenNothingRemoved() {
        let before = McpConfig.local(McpLocalConfig(command: ["x"], environment: ["A": "1"]))
        let after = McpConfig.local(McpLocalConfig(command: ["x"], environment: ["A": "1", "B": "2"]))
        XCTAssertTrue(MCPConfigWriter.strandedKeys(from: before, to: after).isEmpty)
        XCTAssertTrue(MCPConfigWriter.strandedKeys(from: nil, to: after).isEmpty)
    }

    /// `command` is an array, which the merge replaces wholesale — it never strands.
    func testStrandedKeysIgnoresCommandChanges() {
        let before = McpConfig.local(McpLocalConfig(command: ["a", "b", "c"]))
        let after = McpConfig.local(McpLocalConfig(command: ["a"]))
        XCTAssertTrue(MCPConfigWriter.strandedKeys(from: before, to: after).isEmpty)
    }

    func testStrandedKeysDetectsRemovedHeaders() {
        let before = McpConfig.remote(McpRemoteConfig(url: "https://x", headers: ["Authorization": "a", "X": "b"]))
        let after = McpConfig.remote(McpRemoteConfig(url: "https://x", headers: [:]))
        XCTAssertEqual(MCPConfigWriter.strandedKeys(from: before, to: after), ["Authorization", "X"])
    }
}

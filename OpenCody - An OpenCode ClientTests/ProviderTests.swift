import XCTest
@testable import OpenCody___An_OpenCode_Client

/// Tests for the provider model layer.
///
/// JSON captured verbatim from a live opencode server (v1.16.2) — `GET /provider`
/// and `GET /provider/auth`.
final class ProviderTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Cost Units

    /// The server reports cost in **USD per million tokens**, not per token.
    ///
    /// Claude Sonnet comes back as `"input": 3` meaning $3/Mtok. Scaling that by a
    /// million produced "$3000000 in" on screen.
    func testCostIsAlreadyPerMillionTokens() throws {
        let json = """
        {"input":3,"output":15,"cache":{"read":0.3,"write":3.75}}
        """
        let cost = try decode(ModelCost.self, json)
        XCTAssertEqual(cost.input, 3, accuracy: 0.0001)
        XCTAssertEqual(cost.output, 15, accuracy: 0.0001)
        XCTAssertEqual(cost.cache?.read ?? 0, 0.3, accuracy: 0.0001)
    }

    // MARK: - Auth Methods

    /// Captured from `GET /provider/auth`. Covers the shapes that matter: several
    /// methods per provider, both types, and prompts with options.
    func testAuthMethodsDecode() throws {
        let json = """
        {"openai":[{"type":"oauth","label":"ChatGPT Pro/Plus (browser)"},
                   {"type":"api","label":"Manually enter API Key"}],
         "cloudflare-ai-gateway":[{"type":"api","label":"Gateway API token",
            "prompts":[{"type":"text","key":"accountId","message":"Account ID"},
                       {"type":"select","key":"region","message":"Region",
                        "options":[{"label":"EU","value":"eu"},{"label":"US","value":"us","hint":"default"}]}]}]}
        """
        let methods = try decode([String: [ProviderAuthMethod]].self, json)
        XCTAssertEqual(methods["openai"]?.count, 2)
        XCTAssertEqual(methods["openai"]?.first?.type, .oauth)
        XCTAssertEqual(methods["openai"]?.last?.type, .api)

        let gateway = try XCTUnwrap(methods["cloudflare-ai-gateway"]?.first)
        XCTAssertEqual(gateway.prompts?.count, 2)
        XCTAssertEqual(gateway.prompts?.last?.options?.last?.hint, "default")
    }

    /// A prompt's `when` rule decides whether it is shown at all.
    func testPromptVisibilityHonoursWhenRule() throws {
        let json = """
        {"type":"oauth","label":"Login",
         "prompts":[{"type":"select","key":"mode","message":"Mode",
                     "options":[{"label":"Cloud","value":"cloud"},{"label":"Self hosted","value":"self"}]},
                    {"type":"text","key":"host","message":"Host",
                     "when":{"key":"mode","op":"eq","value":"self"}}]}
        """
        let method = try decode(ProviderAuthMethod.self, json)
        XCTAssertEqual(method.visiblePrompts(given: [:]).map(\.key), ["mode"])
        XCTAssertEqual(method.visiblePrompts(given: ["mode": "cloud"]).map(\.key), ["mode"])
        XCTAssertEqual(method.visiblePrompts(given: ["mode": "self"]).map(\.key), ["mode", "host"])
    }

    func testPromptVisibilityHonoursNegatedRule() throws {
        let json = """
        {"type":"oauth","label":"Login",
         "prompts":[{"type":"text","key":"token","message":"Token",
                     "when":{"key":"mode","op":"neq","value":"cloud"}}]}
        """
        let method = try decode(ProviderAuthMethod.self, json)
        XCTAssertTrue(method.visiblePrompts(given: ["mode": "cloud"]).isEmpty)
        XCTAssertEqual(method.visiblePrompts(given: ["mode": "self"]).map(\.key), ["token"])
    }

    // MARK: - Authorization Result

    /// `POST /provider/{id}/oauth/authorize` answers literal `null` when the chosen
    /// method does not start a flow, so the result has to decode as optional.
    func testAuthorizationDecodesNull() throws {
        XCTAssertNil(try decode(ProviderAuthAuthorization?.self, "null"))

        let json = """
        {"url":"https://provider/auth?x=1","method":"code","instructions":"Paste the code"}
        """
        let authorization = try XCTUnwrap(try decode(ProviderAuthAuthorization?.self, json))
        XCTAssertEqual(authorization.method, .code)
        XCTAssertEqual(authorization.url, "https://provider/auth?x=1")
    }

    // MARK: - Credential Encoding

    /// Must match the server's `Auth` union exactly — it is a discriminated union and
    /// a wrong field name is a 400 with no useful detail.
    func testApiCredentialEncoding() throws {
        let data = try JSONEncoder().encode(ProviderCredential.api(key: "sk-test", metadata: nil))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "api")
        XCTAssertEqual(object["key"] as? String, "sk-test")
        XCTAssertNil(object["metadata"])
    }

    func testOAuthCredentialEncoding() throws {
        let data = try JSONEncoder().encode(
            ProviderCredential.oauth(access: "a", refresh: "r", expires: 42)
        )
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "oauth")
        XCTAssertEqual(object["access"] as? String, "a")
        XCTAssertEqual(object["refresh"] as? String, "r")
        XCTAssertEqual(object["expires"] as? Int, 42)
    }

    // MARK: - API Key Support

    /// Only a handful of providers have an auth plugin. The rest are connected by
    /// storing an API key under their ID — verified against a live server, where
    /// `PUT /auth/anthropic` made `anthropic` report as connected despite it having
    /// no entry in `/provider/auth` at all.
    func testProviderWithoutPluginAcceptsApiKey() throws {
        let entry = try entry(id: "anthropic", methods: [])
        XCTAssertTrue(entry.supportsApiKey)
    }

    /// A provider offering both OAuth and a key method still takes a key.
    func testProviderWithApiMethodAcceptsApiKey() throws {
        let entry = try entry(id: "openai", methods: [
            #"{"type":"oauth","label":"ChatGPT Pro/Plus (browser)"}"#,
            #"{"type":"api","label":"Manually enter API Key"}"#,
        ])
        XCTAssertTrue(entry.supportsApiKey)
    }

    /// The one case where a key must not be offered: the server's `connected` list only
    /// checks that an auth entry exists, so writing a key for an OAuth-only provider
    /// would show it as connected while every request failed.
    func testOAuthOnlyProviderRejectsApiKey() throws {
        let entry = try entry(id: "github-copilot", methods: [
            #"{"type":"oauth","label":"Login with GitHub Copilot"}"#,
        ])
        XCTAssertFalse(entry.supportsApiKey)
    }

    func testEnvVarHintListsEveryVariable() throws {
        let entry = ProviderEntry(
            provider: try sampleProvider(id: "anthropic", env: ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]),
            isConnected: false,
            defaultModelID: nil,
            authMethods: []
        )
        XCTAssertEqual(entry.envVarHint, "ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN")
    }

    // MARK: - Helpers

    private func entry(id: String, methods: [String]) throws -> ProviderEntry {
        ProviderEntry(
            provider: try sampleProvider(id: id),
            isConnected: false,
            defaultModelID: nil,
            authMethods: try methods.map { try decode(ProviderAuthMethod.self, $0) }
        )
    }

    private func sampleProvider(id: String, env: [String] = []) throws -> Provider {
        let envJSON = env.map { "\"\($0)\"" }.joined(separator: ",")
        return try decode(Provider.self, """
        {"id":"\(id)","name":"\(id)","source":"custom","env":[\(envJSON)],
         "options":{},"models":{}}
        """)
    }
}

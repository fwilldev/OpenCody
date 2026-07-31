import XCTest
@testable import OpenCody___An_OpenCode_Client

/// Decoding tests pinned to payloads captured verbatim from a live opencode
/// server (v1.18.9). They guard the model layer against the schema drift that
/// silently broke session diffs, permission prompts, and slash commands before.
final class APIDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Session

    func testSessionDecodesNewFields() throws {
        // Captured from POST /session.
        let json = """
        {"id":"ses_04cd9e194ffeoDki2OPyujgmUT","slug":"crisp-mountain",
         "projectID":"012780c4098d08caa4ea8c479ed0a4690489f38d",
         "directory":"/srv/opencode-demo/opencode","path":"","cost":0,
         "tokens":{"input":0,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},
         "title":"smoke","version":"1.18.9",
         "time":{"created":1785417047659,"updated":1785417047659}}
        """
        let session = try decode(Session.self, json)
        XCTAssertEqual(session.id, "ses_04cd9e194ffeoDki2OPyujgmUT")
        XCTAssertEqual(session.slug, "crisp-mountain")
        XCTAssertEqual(session.cost, 0)
        XCTAssertNotNil(session.tokens)
        XCTAssertFalse(session.isArchived)
        XCTAssertFalse(session.isCompacting)
    }

    // MARK: - FileDiff / UnifiedDiff

    func testFileDiffDecodesPatchAndParsesHunks() throws {
        // Captured from GET /vcs/diff?mode=git — the server sends a unified patch,
        // never the before/after full contents an earlier client version expected.
        let json = """
        [{"file":"AGENTS.md","patch":"diff --git a/AGENTS.md b/AGENTS.md\\nindex cd2327e..0ff2f3b 100644\\n--- a/AGENTS.md\\n+++ b/AGENTS.md\\n@@ -1,4 +1,5 @@\\n context line\\n+added line\\n-removed line\\n more context\\n","additions":1,"deletions":1,"status":"modified"}]
        """
        let diffs = try decode([FileDiff].self, json)
        XCTAssertEqual(diffs.count, 1)

        let diff = diffs[0]
        XCTAssertEqual(diff.file, "AGENTS.md")
        XCTAssertEqual(diff.fileName, "AGENTS.md")
        XCTAssertEqual(diff.additions, 1)
        XCTAssertEqual(diff.deletions, 1)
        XCTAssertNotNil(diff.patch)

        let parsed = diff.parsedDiff
        XCTAssertFalse(parsed.isEmpty, "patch must parse into hunks")
        XCTAssertEqual(parsed.additions, 1)
        XCTAssertEqual(parsed.deletions, 1)

        let added = parsed.lines.filter { $0.kind == .added }
        XCTAssertEqual(added.map(\.text), ["added line"])
        let removed = parsed.lines.filter { $0.kind == .removed }
        XCTAssertEqual(removed.map(\.text), ["removed line"])
        // `diff --git`/`index`/`---`/`+++` must not be mistaken for content.
        XCTAssertFalse(parsed.lines.contains { $0.text.hasPrefix("diff --git") })
        XCTAssertTrue(parsed.lines.contains { $0.kind == .header })
    }

    func testFileDiffToleratesMissingFileAndPatch() throws {
        // SnapshotFileDiff marks only additions/deletions as required.
        let diffs = try decode([FileDiff].self, #"[{"additions":3,"deletions":0}]"#)
        XCTAssertEqual(diffs[0].file, "")
        XCTAssertNil(diffs[0].patch)
        XCTAssertTrue(diffs[0].parsedDiff.isEmpty)
    }

    func testUnifiedDiffTracksLineNumbers() {
        let parsed = UnifiedDiff(patch: "@@ -10,3 +20,4 @@\n ctx\n+new\n-old\n")
        let added = parsed.lines.first { $0.kind == .added }
        let removed = parsed.lines.first { $0.kind == .removed }
        // Context line consumes 10/20, so the next added line is new-file line 21.
        XCTAssertEqual(added?.newLineNumber, 21)
        XCTAssertEqual(removed?.oldLineNumber, 11)
    }

    // MARK: - Permission

    func testPermissionDecodesV1Shape() throws {
        let json = """
        {"id":"per_abc","sessionID":"ses_abc","permission":"bash",
         "patterns":["rm -rf /tmp/x"],"metadata":{"title":"rm -rf /tmp/x"},
         "always":["rm *"],"tool":{"messageID":"msg_1","callID":"call_1"}}
        """
        let permission = try decode(Permission.self, json)
        XCTAssertEqual(permission.variant, .v1)
        XCTAssertEqual(permission.permission, "bash")
        XCTAssertEqual(permission.patterns, ["rm -rf /tmp/x"])
        XCTAssertEqual(permission.displayTitle, "rm -rf /tmp/x")
        XCTAssertTrue(permission.supportsAlways)
        XCTAssertEqual(permission.tool?.callID, "call_1")
    }

    func testPermissionDecodesV2Shape() throws {
        // permission.v2.asked renames the fields; the reply route differs too, so
        // the variant must be detected rather than assumed.
        let json = """
        {"id":"per_xyz","sessionID":"ses_xyz","action":"edit",
         "resources":["src/main.swift"],"save":["src/*"]}
        """
        let permission = try decode(Permission.self, json)
        XCTAssertEqual(permission.variant, .v2)
        XCTAssertEqual(permission.permission, "edit")
        XCTAssertEqual(permission.patterns, ["src/main.swift"])
        XCTAssertEqual(permission.primaryPattern, "src/main.swift")
        XCTAssertTrue(permission.supportsAlways)
        // No metadata.title — falls back to the action name.
        XCTAssertEqual(permission.displayTitle, "edit")
    }

    // MARK: - Agent

    func testAgentDecodesPermissionRuleset() throws {
        // Captured from GET /agent.
        let json = """
        [{"name":"build","description":"The default agent.","mode":"primary","native":true,
          "permission":[{"permission":"*","pattern":"*","action":"allow"},
                        {"permission":"doom_loop","pattern":"*","action":"ask"}],
          "options":{}}]
        """
        let agents = try decode([Agent].self, json)
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].mode, .primary)
        XCTAssertEqual(agents[0].permission.count, 2)
        XCTAssertEqual(agents[0].permission[1].action, "ask")
    }

    // MARK: - VCS

    func testVcsInfoDecodesDefaultBranch() throws {
        let info = try decode(VcsInfo.self, #"{"branch":"dev","default_branch":"dev"}"#)
        XCTAssertEqual(info.branch, "dev")
        XCTAssertEqual(info.defaultBranch, "dev")
        XCTAssertTrue(info.isRepository)
    }

    func testVcsInfoToleratesNonRepository() throws {
        // A directory outside version control returns an empty object.
        let info = try decode(VcsInfo.self, "{}")
        XCTAssertNil(info.branch)
        XCTAssertFalse(info.isRepository)
    }

    // MARK: - Project

    func testProjectDecodesSandboxesAndDisplayName() throws {
        let json = """
        {"id":"0127","worktree":"/srv/opencode-demo/opencode","vcs":"git",
         "time":{"created":1785417607959,"updated":1785417607959},"sandboxes":[]}
        """
        let project = try decode(Project.self, json)
        XCTAssertTrue(project.isGitRepository)
        XCTAssertEqual(project.sandboxes, [])
        // No explicit name — fall back to the worktree's last path component.
        XCTAssertEqual(project.displayName, "opencode")
    }

    // MARK: - Provider auth

    func testProviderAuthMethodsDecodePromptsAndConditions() throws {
        // Captured from GET /provider/auth.
        let json = """
        {"github-copilot":[{"type":"oauth","label":"Login with GitHub Copilot","prompts":[
           {"type":"select","key":"deploymentType","message":"Select GitHub deployment type",
            "options":[{"label":"GitHub.com","value":"github.com","hint":"Public"},
                       {"label":"GitHub Enterprise","value":"enterprise","hint":"Self-hosted"}]},
           {"type":"text","key":"enterpriseUrl","message":"Enter your GitHub Enterprise URL",
            "placeholder":"company.ghe.com",
            "when":{"key":"deploymentType","op":"eq","value":"enterprise"}}]}],
         "openai":[{"type":"api","label":"Manually enter API Key"}]}
        """
        let methods = try decode([String: [ProviderAuthMethod]].self, json)
        let copilot = try XCTUnwrap(methods["github-copilot"]?.first)
        XCTAssertEqual(copilot.type, .oauth)
        XCTAssertEqual(copilot.prompts?.count, 2)
        XCTAssertEqual(copilot.prompts?[0].options?.count, 2)

        // The enterprise URL prompt is gated on the preceding select.
        XCTAssertEqual(copilot.visiblePrompts(given: [:]).map(\.key), ["deploymentType"])
        XCTAssertEqual(
            copilot.visiblePrompts(given: ["deploymentType": "enterprise"]).map(\.key),
            ["deploymentType", "enterpriseUrl"]
        )
        XCTAssertEqual(methods["openai"]?.first?.type, .api)
    }

    // MARK: - Skill

    func testSkillDecodes() throws {
        let json = #"[{"name":"customize-opencode","description":"Use ONLY when...","location":"/x/skill.md","content":"body"}]"#
        let skills = try decode([Skill].self, json)
        XCTAssertEqual(skills[0].id, "customize-opencode")
        XCTAssertEqual(skills[0].location, "/x/skill.md")
    }

    // MARK: - Events

    func testPermissionAskedEventParsesBothGenerations() throws {
        let v1 = try SSEEvent.parse(
            eventName: "permission.asked",
            data: #"{"type":"permission.asked","properties":{"id":"per_1","sessionID":"ses_1","permission":"bash","patterns":["ls"],"metadata":{},"always":[]}}"#
        )
        guard case .permissionUpdated(let p1) = v1 else {
            return XCTFail("expected permissionUpdated, got \(v1)")
        }
        XCTAssertEqual(p1.variant, .v1)

        let v2 = try SSEEvent.parse(
            eventName: "permission.v2.asked",
            data: #"{"type":"permission.v2.asked","properties":{"id":"per_2","sessionID":"ses_2","action":"edit","resources":["a.txt"]}}"#
        )
        guard case .permissionUpdated(let p2) = v2 else {
            return XCTFail("expected permissionUpdated, got \(v2)")
        }
        XCTAssertEqual(p2.variant, .v2)
    }

    func testPermissionRepliedAcceptsOldAndNewKeys() throws {
        let modern = try SSEEvent.parse(
            eventName: "permission.replied",
            data: #"{"type":"permission.replied","properties":{"sessionID":"ses_1","requestID":"per_1","reply":"once"}}"#
        )
        guard case .permissionReplied(let a) = modern else {
            return XCTFail("expected permissionReplied")
        }
        XCTAssertEqual(a.requestID, "per_1")
        XCTAssertEqual(a.reply, "once")

        let legacy = try SSEEvent.parse(
            eventName: "permission.replied",
            data: #"{"type":"permission.replied","properties":{"sessionID":"ses_1","permissionID":"per_9","response":"reject"}}"#
        )
        guard case .permissionReplied(let b) = legacy else {
            return XCTFail("expected permissionReplied")
        }
        XCTAssertEqual(b.requestID, "per_9")
        XCTAssertEqual(b.reply, "reject")
    }

    func testHeartbeatAndSyncEventsAreClassified() throws {
        // Observed live: both arrive on /global/event and must not be treated as
        // unknown — heartbeats keep the watchdog alive, sync events are duplicates.
        let beat = try SSEEvent.parse(
            eventName: "server.heartbeat",
            data: #"{"id":"evt_1","type":"server.heartbeat","properties":{}}"#
        )
        guard case .serverHeartbeat = beat else { return XCTFail("expected serverHeartbeat") }

        let sync = try SSEEvent.parse(
            eventName: "sync",
            data: #"{"type":"sync","syncEvent":{"type":"session.created.1","seq":0}}"#
        )
        guard case .syncEnvelope = sync else { return XCTFail("expected syncEnvelope") }
    }

    func testSessionNextStreamEventsCollapseToOneCase() throws {
        let event = try SSEEvent.parse(
            eventName: "session.next.text.delta",
            data: #"{"type":"session.next.text.delta","properties":{"timestamp":1,"sessionID":"ses_1","assistantMessageID":"msg_1","textID":"t","delta":"Hello"}}"#
        )
        guard case .sessionStreamEvent(let payload) = event else {
            return XCTFail("expected sessionStreamEvent, got \(event)")
        }
        XCTAssertEqual(payload.stage, "text.delta")
        XCTAssertEqual(payload.sessionID, "ses_1")
        XCTAssertEqual(payload.delta, "Hello")
        XCTAssertTrue(payload.isTextDelta)
    }

    func testUnknownEventStillParses() throws {
        let event = try SSEEvent.parse(eventName: "totally.new.event", data: #"{"type":"totally.new.event"}"#)
        guard case .unknown(let name, _) = event else { return XCTFail("expected unknown") }
        XCTAssertEqual(name, "totally.new.event")
    }

    // MARK: - SessionChangeSet

    /// Builds a user message carrying the per-turn diffs the server stores.
    ///
    /// Decoded from JSON rather than constructed, so the fixture exercises the same
    /// path as a real `GET /session/{id}/message` response.
    private func userMessage(id: String, diffsJSON: String) throws -> MessageWithParts {
        let json = """
        {"info":{"id":"\(id)","sessionID":"ses_1","role":"user",
          "time":{"created":0},"summary":{"diffs":\(diffsJSON)}},
         "parts":[]}
        """
        return try decode(MessageAPI.MessageWithPartsResponse.self, json).toModel()
    }

    /// One entry of a user message's `summary.diffs`.
    private func diffJSON(
        file: String,
        patch: String? = nil,
        additions: Int,
        deletions: Int,
        status: String
    ) -> String {
        let patchField = patch.map { ",\"patch\":\(jsonString($0))" } ?? ""
        return """
        {"file":"\(file)","additions":\(additions),"deletions":\(deletions),"status":"\(status)"\(patchField)}
        """
    }

    private func jsonString(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    func testChangeSetAggregatesUserTurnDiffs() throws {
        // Mirrors the live server: real diffs live on user messages, per turn.
        let messages = [
            try userMessage(id: "msg_1", diffsJSON: """
            [\(diffJSON(file: "README.md", patch: "@@ -1,1 +1,1 @@\n-a\n+b\n", additions: 1, deletions: 1, status: "modified"))]
            """),
            try userMessage(id: "msg_2", diffsJSON: "[]"),
            try userMessage(id: "msg_3", diffsJSON: """
            [\(diffJSON(file: "README.md", patch: "@@ -5,1 +5,1 @@\n-c\n+d\n", additions: 1, deletions: 1, status: "modified")),
             \(diffJSON(file: "NEW.md", patch: "@@ -0,0 +1,1 @@\n+hello\n", additions: 1, deletions: 0, status: "added"))]
            """),
        ]

        let changeSet = SessionChangeSet(messages: messages)

        // One entry per file, in first-touched order.
        XCTAssertEqual(changeSet.files.map(\.file), ["README.md", "NEW.md"])
        XCTAssertEqual(changeSet.fileCount, 2)
        // Per-turn diffs are incremental, so counts sum across turns.
        XCTAssertEqual(changeSet.additions, 3)
        XCTAssertEqual(changeSet.deletions, 2)

        let readme = try XCTUnwrap(changeSet.files.first)
        XCTAssertEqual(readme.additions, 2)
        XCTAssertEqual(readme.deletions, 2)
        // Both turns' patches are retained and parse into two hunks.
        XCTAssertEqual(readme.parsedDiff.hunks.count, 2)
        XCTAssertEqual(readme.parsedDiff.additions, 2)
    }

    func testChangeSetIsEmptyWhenNoTurnChangedFiles() throws {
        let changeSet = SessionChangeSet(messages: [try userMessage(id: "msg_1", diffsJSON: "[]")])
        XCTAssertTrue(changeSet.isEmpty)
        XCTAssertEqual(changeSet.additions, 0)
    }

    func testChangeSetKeepsAddedStatusAcrossLaterEdits() throws {
        let messages = [
            try userMessage(id: "msg_1", diffsJSON: """
            [\(diffJSON(file: "NEW.md", additions: 5, deletions: 0, status: "added"))]
            """),
            try userMessage(id: "msg_2", diffsJSON: """
            [\(diffJSON(file: "NEW.md", additions: 1, deletions: 1, status: "modified"))]
            """),
        ]
        let file = try XCTUnwrap(SessionChangeSet(messages: messages).files.first)
        // A file created then edited within the session is still an addition overall.
        XCTAssertEqual(file.status, .added)
        XCTAssertEqual(file.additions, 6)
    }

    func testAllZeroSessionSummaryIsTreatedAsUncomputed() throws {
        // The server writes {0,0,0} and never updates it, so this must not be
        // rendered as a factual "0 files · +0 -0".
        let placeholder = try decode(
            SessionSummary.self,
            #"{"additions":0,"deletions":0,"files":0}"#
        )
        XCTAssertFalse(placeholder.hasMeaningfulTotals)

        let real = try decode(SessionSummary.self, #"{"additions":2,"deletions":5,"files":1}"#)
        XCTAssertTrue(real.hasMeaningfulTotals)
    }

    // MARK: - IDGenerator

    func testGeneratedIDsArePrefixedAndSortable() {
        let a = IDGenerator.message()
        let b = IDGenerator.message()
        XCTAssertTrue(a.hasPrefix("msg_"), "server validates the ^msg prefix")
        XCTAssertTrue(IDGenerator.part().hasPrefix("prt_"))
        XCTAssertNotEqual(a, b)
        // Zero-padded base-36 timestamps keep lexical order equal to time order.
        XCTAssertEqual(a.count, b.count)
    }
}

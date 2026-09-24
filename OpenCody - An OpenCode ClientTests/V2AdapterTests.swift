import XCTest
@testable import OpenCody___An_OpenCode_Client

/// Tests for the OpenCode 2.x translation layer.
///
/// Fixtures follow the 2.x OpenAPI schema (`packages/protocol/openapi.json`, v2.0.15)
/// and the event definitions in `packages/schema/src/session-event.ts`.
final class V2AdapterTests: XCTestCase {

    private func json(_ string: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any])
    }

    // MARK: - Sessions

    func testSessionDirectoryIsItsLocation() throws {
        let raw = try json("""
        {"id":"ses_1","projectID":"prj_1","cost":0.5,
         "tokens":{"input":10,"output":20,"reasoning":0,"cache":{"read":1,"write":2}},
         "time":{"created":1000,"updated":2000},
         "title":"Fix login","subpath":"packages/app",
         "model":{"id":"claude","providerID":"anthropic"},
         "location":{"directory":"/srv/repo/packages/app"}}
        """)
        let session = try V2Adapter.decode(Session.self, from: V2Adapter.session(raw))
        XCTAssertEqual(session.id, "ses_1")
        XCTAssertEqual(session.directory, "/srv/repo/packages/app")
        XCTAssertEqual(session.path, "packages/app")
        XCTAssertEqual(session.title, "Fix login")
        XCTAssertEqual(session.model?.id, "claude")
        XCTAssertEqual(session.time.updated, 2000)
        XCTAssertFalse(session.isArchived)
    }

    func testUntitledSessionGetsPlaceholderTitle() throws {
        let raw = try json("""
        {"id":"ses_2","projectID":"prj_1","cost":0,
         "tokens":{"input":0,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},
         "time":{"created":1,"updated":1},"location":{"directory":"/srv/repo"}}
        """)
        let session = try V2Adapter.decode(Session.self, from: V2Adapter.session(raw))
        XCTAssertEqual(session.title, "New session")
        XCTAssertEqual(session.directory, "/srv/repo")
    }

    // MARK: - Messages

    private let transcript = """
    [
      {"id":"msg_a","type":"model-switched","time":{"created":1},"model":{"id":"gpt","providerID":"openai"}},
      {"id":"msg_u1","type":"user","time":{"created":2},"text":"Hello",
       "files":[{"data":"aGk=","mime":"text/plain","source":{"type":"inline"},"name":"hi.txt"}]},
      {"id":"msg_x1","type":"assistant","time":{"created":3,"completed":9},"agent":"build",
       "model":{"id":"claude","providerID":"anthropic"},
       "content":[
         {"type":"reasoning","text":"thinking","time":{"created":3,"completed":4}},
         {"type":"text","text":"Sure."},
         {"type":"tool","id":"call_1","name":"shell","time":{"created":5,"ran":6,"completed":7},
          "state":{"status":"completed","input":{"command":"ls"},
                   "content":[{"type":"text","text":"a.txt"}],"metadata":{"title":"List files"}}},
         {"type":"text","text":"Done."}
       ],
       "finish":"stop","cost":0.01,
       "tokens":{"input":5,"output":6,"reasoning":0,"cache":{"read":0,"write":0}}},
      {"id":"msg_i","type":"idle","time":{"created":10},"outcome":"succeeded"}
    ]
    """

    func testTranscriptBecomesUserAndAssistantRecords() throws {
        let list = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(transcript.utf8)) as? [[String: Any]])
        let records = V2Adapter.messages(list, sessionID: "ses_1")
        let responses = try V2Adapter.decode([MessageAPI.MessageWithPartsResponse].self, from: records)
        XCTAssertEqual(responses.map(\.info.id), ["msg_u1", "msg_x1"], "bookkeeping records are dropped")

        // User message: stamped with the agent/model of the turn it started.
        guard case .user(let user) = responses[0].info else { return XCTFail("Expected user message") }
        XCTAssertEqual(user.agent, "build")
        XCTAssertEqual(user.model?.modelID, "claude")
        XCTAssertEqual(responses[0].parts.count, 2)
        guard case .file(let file) = responses[0].parts[1] else { return XCTFail("Expected file part") }
        XCTAssertEqual(file.url, "data:text/plain;base64,aGk=")
        XCTAssertEqual(file.filename, "hi.txt")

        // Assistant message: inline content becomes parts with derived IDs.
        guard case .assistant(let assistant) = responses[1].info else { return XCTFail("Expected assistant") }
        XCTAssertEqual(assistant.parentID, "msg_u1")
        XCTAssertEqual(assistant.mode, "build")
        XCTAssertEqual(assistant.providerID, "anthropic")
        XCTAssertEqual(assistant.time.completed, 9)
        XCTAssertEqual(responses[1].parts.map(\.id), [
            "msg_x1-reasoning-0", "msg_x1-text-0", "msg_x1-tool-call_1", "msg_x1-text-1",
        ])
        guard case .tool(let tool) = responses[1].parts[2], case .completed(let state) = tool.state else {
            return XCTFail("Expected completed tool part")
        }
        XCTAssertEqual(tool.tool, "shell")
        XCTAssertEqual(tool.callID, "call_1")
        XCTAssertEqual(state.output, "a.txt")
        XCTAssertEqual(state.title, "List files")
    }

    func testToolErrorState() throws {
        let tool = try json("""
        {"type":"tool","id":"c","name":"edit","time":{"created":1},
         "state":{"status":"error","input":{"path":"x"},"error":{"type":"Tool","message":"no such file"}}}
        """)
        let part = try V2Adapter.decode(Part.self, from: V2Adapter.toolPart(tool, messageID: "m", sessionID: "s"))
        guard case .tool(let toolPart) = part, case .error(let state) = toolPart.state else {
            return XCTFail("Expected tool error")
        }
        XCTAssertEqual(state.error, "no such file")
    }

    // MARK: - Questions

    private let questionForm = """
    {"id":"frm_1","sessionID":"ses_1","title":"Questions",
     "metadata":{"kind":"question","tool":{"messageID":"msg_x1","id":"call_q"}},
     "fields":[
       {"key":"q0","title":"Color","description":"Pick a color","type":"string","custom":true,
        "options":[{"value":"Red","label":"Red","description":"warm"},{"value":"Blue","label":"Blue"}]},
       {"key":"q1","title":"Sizes","description":"Pick sizes","type":"multiselect",
        "options":[{"value":"S","label":"S"},{"value":"M","label":"M"}]}
     ]}
    """

    func testQuestionFormBecomesQuestionRequest() throws {
        let form = try json(questionForm)
        let request = try V2Adapter.decode(QuestionRequest.self, from: try XCTUnwrap(V2Adapter.question(fromForm: form)))
        XCTAssertEqual(request.id, "frm_1")
        XCTAssertEqual(request.questions.count, 2)
        XCTAssertEqual(request.questions[0].question, "Pick a color")
        XCTAssertEqual(request.questions[0].header, "Color")
        XCTAssertFalse(request.questions[0].allowsMultiple)
        XCTAssertTrue(request.questions[1].allowsMultiple)
        XCTAssertEqual(request.tool?.callID, "call_q")
    }

    func testAnswersAreTypedPerField() throws {
        let fields = try XCTUnwrap(try json(questionForm)["fields"] as? [[String: Any]])
        let answer = V2Adapter.formAnswer([["Blue"], ["S", "M"]], fields: fields)
        XCTAssertEqual(answer["q0"] as? String, "Blue")
        XCTAssertEqual(answer["q1"] as? [String], ["S", "M"])
    }

    func testNonQuestionFormsAreIgnored() throws {
        let form = try json("""
        {"id":"frm_2","sessionID":"s","title":"Login","fields":[{"key":"k","type":"external","url":"https://x"}]}
        """)
        XCTAssertNil(V2Adapter.question(fromForm: form))
    }

    // MARK: - Catalog

    func testModelDecodesAsV1Model() throws {
        let raw = try json("""
        {"id":"claude","modelID":"claude-5","providerID":"anthropic","name":"Claude",
         "capabilities":{"tools":true,"input":["text","image"],"output":["text"]},
         "variants":[{"id":"high"}],"time":{"released":1760000000000},
         "cost":[{"input":3,"output":15,"cache":{"read":0.3,"write":3.75}}],
         "status":"active","enabled":true,"limit":{"context":200000,"output":64000}}
        """)
        let model = try V2Adapter.decode(Model.self, from: V2Adapter.model(raw, providerPackage: "@ai-sdk/anthropic"))
        XCTAssertEqual(model.id, "claude")
        XCTAssertEqual(model.api.id, "claude-5")
        XCTAssertTrue(model.capabilities.attachment)
        XCTAssertEqual(model.variantIDs, ["high"])
        XCTAssertEqual(model.cost.input, 3)
        XCTAssertEqual(model.limit.context, 200000)
    }

    func testAgentUsesIDAsName() throws {
        let raw = try json("""
        {"id":"build","name":"Build","mode":"primary","hidden":false,
         "request":{"settings":{},"headers":{},"body":{}},"permissions":[]}
        """)
        let agent = try V2Adapter.decode(Agent.self, from: V2Adapter.agent(raw))
        XCTAssertEqual(agent.name, "build")
        XCTAssertEqual(agent.mode, .primary)
    }

    func testPermissionKeepsV2VariantAndCallID() throws {
        let raw = try json("""
        {"id":"per_1","sessionID":"ses_1","action":"shell","resources":["rm -rf x"],"save":["rm *"],
         "source":{"type":"tool","messageID":"msg_1","id":"call_9"}}
        """)
        let permission = try V2Adapter.decode(Permission.self, from: V2Adapter.permission(raw))
        XCTAssertEqual(permission.variant, .v2)
        XCTAssertEqual(permission.permission, "shell")
        XCTAssertEqual(permission.tool?.callID, "call_9")
    }

    func testMcpConfigRoundTrip() throws {
        let v2 = try json(#"{"type":"local","command":["npx","srv"],"disabled":true}"#)
        let v1 = try V2Adapter.decode(McpConfig.self, from: try XCTUnwrap(V2Adapter.mcpConfig(fromV2: v2)))
        XCTAssertFalse(v1.isEnabled)
        let back = try XCTUnwrap(V2Adapter.mcpConfig(fromV1: v1))
        XCTAssertEqual(back["disabled"] as? Bool, true)
        XCTAssertEqual(back["command"] as? [String], ["npx", "srv"])
    }

    // MARK: - Events

    /// Feed raw 2.x events through the translator and parse what comes out.
    private func translate(_ events: [String]) async throws -> [SSEEvent] {
        let client = APIClient(baseURL: "http://127.0.0.1:9", username: "", password: "", apiVersion: .v2)
        let translator = V2EventTranslator(client: client)
        var output: [SSEEvent] = []
        for raw in events {
            for wrapped in await translator.translate(raw) {
                let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(wrapped.utf8)) as? [String: Any])
                let payload = try XCTUnwrap(object["payload"] as? [String: Any])
                let name = try XCTUnwrap(payload["type"] as? String)
                let data = try JSONSerialization.data(withJSONObject: payload)
                output.append(try SSEEvent.parse(eventName: name, data: String(decoding: data, as: UTF8.self)))
            }
        }
        return output
    }

    func testStreamFoldsIntoMessageAndPartEvents() async throws {
        let s = #""sessionID":"ses_1","assistantMessageID":"msg_x""#
        let events = try await translate([
            #"{"id":"evt_0","type":"session.inbox.enqueued","created":1,"data":{"sessionID":"ses_1","inboxID":"msg_u","item":{"type":"user","delivery":"steer","payload":{"text":"hi"}}}}"#,
            #"{"id":"evt_1","type":"session.inbox.delivered","created":2,"data":{"sessionID":"ses_1","inboxID":"msg_u"}}"#,
            #"{"id":"evt_2","type":"session.step.started","created":3,"data":{\#(s),"agent":"build","model":{"id":"claude","providerID":"anthropic"},"started":3}}"#,
            #"{"id":"evt_3","type":"session.text.started","created":4,"data":{\#(s),"ordinal":0}}"#,
            #"{"id":"evt_4","type":"session.text.delta","created":5,"data":{\#(s),"ordinal":0,"delta":"Hel"}}"#,
            #"{"id":"evt_5","type":"session.text.ended","created":6,"data":{\#(s),"ordinal":0,"text":"Hello"}}"#,
            #"{"id":"evt_6","type":"session.tool.input.started","created":7,"data":{\#(s),"id":"call_1","name":"read"}}"#,
            #"{"id":"evt_7","type":"session.tool.called","created":8,"data":{\#(s),"id":"call_1","input":{"path":"a"},"executed":true}}"#,
            #"{"id":"evt_8","type":"session.tool.success","created":9,"data":{\#(s),"id":"call_1","content":[{"type":"text","text":"file body"}],"executed":true}}"#,
            #"{"id":"evt_9","type":"session.step.ended","created":10,"data":{\#(s),"finish":"stop","cost":0.2,"tokens":{"input":1,"output":2,"reasoning":0,"cache":{"read":0,"write":0}}}}"#,
            #"{"id":"evt_a","type":"session.status","created":11,"data":{"sessionID":"ses_1","status":{"type":"idle"}}}"#,
        ])

        // User message and its text part.
        guard case .messageUpdated(.user(let user)) = events[0] else { return XCTFail("Expected user message") }
        XCTAssertEqual(user.id, "msg_u")
        guard case .messagePartUpdated(let userPart) = events[1], case .text(let userText) = userPart.part else {
            return XCTFail("Expected user text part")
        }
        XCTAssertEqual(userText.text, "hi")

        // Assistant message opened by the step.
        guard case .messageUpdated(.assistant(let started)) = events[2] else { return XCTFail("Expected assistant") }
        XCTAssertEqual(started.parentID, "msg_u")
        XCTAssertNil(started.time.completed)

        // Text streams as start → delta → final value, on the REST-derived part ID.
        guard case .messagePartDelta(let delta) = events[4] else { return XCTFail("Expected delta") }
        XCTAssertEqual(delta.partID, "msg_x-text-0")
        XCTAssertEqual(delta.delta, "Hel")
        guard case .messagePartUpdated(let ended) = events[5], case .text(let text) = ended.part else {
            return XCTFail("Expected final text")
        }
        XCTAssertEqual(text.text, "Hello")

        // Tool progresses pending → running → completed.
        guard case .messagePartUpdated(let done) = events[8], case .tool(let tool) = done.part,
              case .completed(let state) = tool.state else { return XCTFail("Expected completed tool") }
        XCTAssertEqual(tool.id, "msg_x-tool-call_1")
        XCTAssertEqual(state.output, "file body")
        XCTAssertEqual(state.input?["path"]?.asString, "a")

        // Step end completes the message; status passes through.
        guard case .messageUpdated(.assistant(let finished)) = events[9] else { return XCTFail("Expected assistant") }
        XCTAssertEqual(finished.time.completed, 10)
        XCTAssertEqual(finished.finish, "stop")
        XCTAssertEqual(finished.cost, 0.2)
        guard case .sessionStatus(let status) = events[10], case .idle = status.status else {
            return XCTFail("Expected idle status")
        }
    }

    func testFormAndPermissionEvents() async throws {
        let form = questionForm.replacingOccurrences(of: "\n", with: "")
        let events = try await translate([
            #"{"id":"evt_1","type":"form.created","created":1,"data":{"form":\#(form)}}"#,
            #"{"id":"evt_2","type":"form.replied","created":2,"data":{"id":"frm_1","sessionID":"ses_1","answer":{"q1":["S"],"q0":"Red"}}}"#,
            #"{"id":"evt_3","type":"permission.asked","created":3,"data":{"id":"per_1","sessionID":"ses_1","action":"edit","resources":["a.txt"]}}"#,
            #"{"id":"evt_4","type":"permission.replied","created":4,"data":{"sessionID":"ses_1","requestID":"per_1","reply":"once"}}"#,
        ])
        guard case .questionAsked(let asked) = events[0] else { return XCTFail("Expected question") }
        XCTAssertEqual(asked.questions.count, 2)
        guard case .questionReplied(let replied) = events[1] else { return XCTFail("Expected reply") }
        XCTAssertEqual(replied.answers, [["Red"], ["S"]], "answers follow question order")
        guard case .permissionUpdated(let permission) = events[2] else { return XCTFail("Expected permission") }
        XCTAssertEqual(permission.variant, .v2)
        guard case .permissionReplied(let reply) = events[3] else { return XCTFail("Expected permission reply") }
        XCTAssertEqual(reply.requestID, "per_1")
    }

    // MARK: - Server configuration

    func testStoredServersWithoutVersionDefaultToV1() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Old","hostname":"h","useHTTPS":false,"username":"",
         "keychainIdentifier":"k","createdAt":0,"isDefault":false}
        """
        let server = try JSONDecoder().decode(ServerConnection.self, from: Data(json.utf8))
        XCTAssertEqual(server.apiVersion, .v1)
    }
}

import XCTest
@testable import OpenCody___An_OpenCode_Client

/// End-to-end tests of the 2.x support against a live OpenCode 2.x server.
///
/// Skipped unless the server is configured through the environment (pass them to
/// `xcodebuild test` with the `TEST_RUNNER_` prefix):
/// - `OPENCODY_V2_URL`       e.g. `http://127.0.0.1:4196`
/// - `OPENCODY_V2_PASSWORD`  the server's `OPENCODE_PASSWORD`
/// - `OPENCODY_V2_DIR`       a git project directory the server can open
/// - `OPENCODY_V2_MODEL`     optional `provider/model`, default `opencode/mimo-v2.6-flash-free`
///
/// The chat tests talk to a real model, so they are slow and depend on it following
/// simple instructions.
@MainActor
final class V2ServerIntegrationTests: XCTestCase {
    private var client: APIClient!
    private var directory: String!
    private var providerID = "opencode"
    private var modelID = "mimo-v2.6-flash-free"

    override func setUp() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["OPENCODY_V2_URL"], let dir = env["OPENCODY_V2_DIR"] else {
            throw XCTSkip("OPENCODY_V2_URL / OPENCODY_V2_DIR not set")
        }
        client = APIClient(
            baseURL: url,
            username: "opencode",
            password: env["OPENCODY_V2_PASSWORD"] ?? "",
            apiVersion: .v2
        )
        directory = dir
        if let model = env["OPENCODY_V2_MODEL"], let slash = model.firstIndex(of: "/") {
            providerID = String(model[..<slash])
            modelID = String(model[model.index(after: slash)...])
        }
    }

    // MARK: - Helpers

    /// Collects translated events from a real `SSEClient` in 2.x mode.
    private final class EventRecorder {
        var events: [SSEEvent] = []
        var sse: SSEClient?
    }

    private func startRecording() async throws -> EventRecorder {
        let recorder = EventRecorder()
        let sse = SSEClient(
            baseURL: client.baseURL,
            authHeader: client.authorizationHeader,
            directoryFilter: directory,
            heartbeatTimeout: 40,
            v2Translator: V2EventTranslator(client: client),
            onEvent: { event in recorder.events.append(event) },
            onStateChange: { _ in }
        )
        recorder.sse = sse
        sse.start()
        try await waitFor("server.connected", recorder, timeout: 10) {
            if case .serverConnected = $0 { return true }
            return false
        }
        return recorder
    }

    @discardableResult
    private func waitFor(
        _ what: String,
        _ recorder: EventRecorder,
        timeout: TimeInterval = 120,
        _ match: (SSEEvent) -> Bool
    ) async throws -> SSEEvent {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let event = recorder.events.first(where: match) { return event }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTFail("Timed out waiting for \(what)")
        throw CancellationError()
    }

    /// `Part.sessionID` is private to the app target; read it from the encoded part.
    private func sessionID(of part: Part) -> String? {
        guard let data = try? JSONEncoder().encode(part),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["sessionID"] as? String
    }

    private func isIdle(_ sessionID: String) -> (SSEEvent) -> Bool {
        { event in
            if case .sessionIdle(let id) = event { return id == sessionID }
            return false
        }
    }

    private func newSession(title: String) async throws -> Session {
        try await SessionAPI(client: client, directory: directory).create(
            title: title,
            model: SessionAPI.ModelRef(providerID: providerID, id: modelID)
        )
    }

    // MARK: - Catalog, files, VCS

    func testCatalogAndFiles() async throws {
        let healthy = try await client.healthCheck()
        XCTAssertTrue(healthy)
        let health = try await GlobalAPI(client: client).health()
        XCTAssertTrue(health.version.hasPrefix("2."))

        let providers = try await ProviderAPI(client: client).list(directory: directory)
        let provider = try XCTUnwrap(providers.all.first { $0.id == providerID }, "configured provider listed")
        XCTAssertNotNil(provider.models[modelID], "configured model listed")
        XCTAssertTrue(providers.connected.contains(providerID))
        _ = try await ProviderAPI(client: client).allAuthMethods(directory: directory)

        let agents = try await AgentAPI(client: client).list()
        XCTAssertTrue(agents.contains { $0.name == "build" }, "agents: \(agents.map(\.name))")
        _ = try await CommandAPI(client: client).list(directory: directory)
        _ = try await CommandAPI(client: client).listSkills(directory: directory)

        let config = try await ConfigAPI(client: client).get()
        XCTAssertNotNil(config.model)
        _ = try await GlobalAPI(client: client).config()
        _ = try await MCPAPI(client: client).list(directory: directory)

        let files = FileAPI(client: client)
        let root = try await files.list(path: ".", directory: directory)
        XCTAssertTrue(root.contains { $0.name == "README.md" && $0.type == .file }, "root: \(root.map(\.path))")
        let readme = try await files.content(path: "README.md", directory: directory)
        XCTAssertEqual(readme.type, .text)
        XCTAssertFalse(readme.content.isEmpty)
        let found = try await files.findFiles(query: "READ", directory: directory)
        XCTAssertTrue(found.contains { $0.hasSuffix("README.md") }, "found: \(found)")
        let projects = try await files.listProjects()
        XCTAssertFalse(projects.isEmpty)
        let current = try await files.currentProject(directory: directory)
        XCTAssertTrue(projects.contains { $0.id == current.id })
        _ = try await files.status(directory: directory)

        let vcs = VcsAPI(client: client)
        let info = try await vcs.info(directory: directory)
        XCTAssertTrue(info.isRepository)
        _ = try await vcs.status(directory: directory)
        _ = try await vcs.diff(mode: .git, directory: directory)
        _ = try await vcs.diff(mode: .branch, directory: directory)

        _ = try await PermissionAPI(client: client).listAll(directory: directory)
        _ = try await QuestionAPI(client: client).list(directory: directory)
    }

    // MARK: - Session lifecycle

    func testSessionLifecycle() async throws {
        let api = SessionAPI(client: client, directory: directory)
        let created = try await newSession(title: "Lifecycle")
        XCTAssertEqual(created.title, "Lifecycle")
        XCTAssertTrue(created.directory.hasPrefix(directory) || directory.hasPrefix(created.directory))

        let renamed = try await api.update(id: created.id, title: "Renamed")
        XCTAssertEqual(renamed.title, "Renamed")
        let fetched = try await api.get(id: created.id)
        XCTAssertEqual(fetched.title, "Renamed")

        let listed = try await api.list()
        XCTAssertTrue(listed.contains { $0.id == created.id }, "list: \(listed.map(\.id))")
        let global = try await api.listGlobal()
        XCTAssertTrue(global.contains { $0.id == created.id })
        _ = try await api.status()
        _ = try await api.children(id: created.id)
        let todos = try await api.todos(id: created.id)
        XCTAssertTrue(todos.isEmpty)

        do {
            _ = try await api.update(id: created.id, setArchived: true)
            XCTFail("Archiving should be reported as unsupported")
        } catch OpenCodeError.unsupported {}

        try await api.delete(id: created.id)
        let after = try await api.list()
        XCTAssertFalse(after.contains { $0.id == created.id })
    }

    // MARK: - Chat

    /// A full turn: live events are translated into the v1 stream, and a REST reload
    /// afterwards yields the same message and part IDs.
    func testChatTurnStreamsAndReloadsConsistently() async throws {
        let recorder = try await startRecording()
        defer { recorder.sse?.stop() }
        let session = try await newSession(title: "Chat")
        let messageID = IDGenerator.message()

        try await MessageAPI(client: client, directory: directory).promptAsync(
            sessionID: session.id,
            text: "Run the shell command `ls` with your shell tool, then answer with one short sentence.",
            modelID: modelID,
            providerID: providerID,
            agent: "build",
            messageID: messageID
        )

        try await waitFor("busy", recorder) {
            if case .sessionStatus(let payload) = $0, payload.sessionID == session.id, case .busy = payload.status {
                return true
            }
            return false
        }
        try await waitFor("idle", recorder, timeout: 180, isIdle(session.id))

        // Live view, folded exactly as ChatViewModel does: last update per ID wins.
        var liveMessages: [String: Message] = [:]
        var liveParts: [String: Part] = [:]
        var deltas = 0
        for event in recorder.events {
            switch event {
            case .messageUpdated(let message) where message.sessionID == session.id:
                liveMessages[message.id] = message
            case .messagePartUpdated(let payload) where sessionID(of: payload.part) == session.id:
                liveParts[payload.part.id] = payload.part
            case .messagePartDelta(let delta) where delta.sessionID == session.id:
                deltas += 1
            default:
                break
            }
        }

        let userMessage = try XCTUnwrap(liveMessages[messageID], "user message echoed with the client-chosen ID")
        XCTAssertEqual(userMessage.role, .user)
        XCTAssertTrue(liveMessages.values.contains { $0.role == .assistant })
        let liveTools = liveParts.values.compactMap { part -> ToolPart? in
            if case .tool(let tool) = part { return tool }
            return nil
        }
        XCTAssertTrue(liveTools.contains { $0.tool == "shell" && $0.state.status == .completed }, "tools: \(liveTools)")
        XCTAssertTrue(liveParts.values.contains { if case .text = $0 { return true } else { return false } })
        XCTAssertGreaterThan(deltas, 0, "text streamed as deltas")

        // Every live assistant message has completed.
        for case .assistant(let assistant) in liveMessages.values {
            XCTAssertNotNil(assistant.time.completed, "assistant \(assistant.id) completed")
        }

        // REST reload lands on the same IDs.
        let reloaded = try await MessageAPI(client: client, directory: directory).list(sessionID: session.id)
        let restMessageIDs = Set(reloaded.map(\.info.id))
        XCTAssertEqual(restMessageIDs, Set(liveMessages.keys), "messages: REST vs live")
        let restPartIDs = Set(reloaded.flatMap(\.parts).map(\.id))
        XCTAssertEqual(restPartIDs, Set(liveParts.keys), "parts: REST vs live")

        // Final text matches between the stream and REST.
        for response in reloaded {
            for case .text(let restText) in response.parts {
                guard case .text(let liveText)? = liveParts[restText.id] else { continue }
                XCTAssertEqual(liveText.text, restText.text)
            }
        }

        // The user message carries the turn's agent/model for the pickers.
        guard case .user(let restUser)? = reloaded.first(where: { $0.info.id == messageID })?.info else {
            return XCTFail("user message in REST")
        }
        XCTAssertEqual(restUser.agent, "build")
        XCTAssertEqual(restUser.model?.modelID, modelID)

        let updated = try await SessionAPI(client: client, directory: directory).get(id: session.id)
        XCTAssertNotEqual(updated.title, "", "title present")

        // History operations on a real transcript.
        let sessionAPI = SessionAPI(client: client, directory: directory)
        let forked = try await sessionAPI.fork(id: session.id)
        XCTAssertNotEqual(forked.id, session.id)
        let reverted = try await sessionAPI.revert(id: session.id, messageID: messageID)
        XCTAssertEqual(reverted.revert?.messageID, messageID)
        let restored = try await sessionAPI.unrevert(id: session.id)
        XCTAssertNil(restored.revert)
        _ = try await sessionAPI.diff(id: session.id, messageID: messageID)

        try await sessionAPI.delete(id: forked.id)
        try await sessionAPI.delete(id: session.id)
    }

    /// A shell tool that needs approval, answered through `PermissionAPI`.
    func testPermissionRoundTrip() async throws {
        let recorder = try await startRecording()
        defer { recorder.sse?.stop() }

        // The app has no UI for session rules; set one directly to force an approval.
        let data = try await client.v2Data(.v2("/api/session", method: .POST, json: [
            "location": ["directory": directory!],
            "model": ["id": modelID, "providerID": providerID],
            "permissions": [["action": "shell", "resource": "*", "effect": "ask"]],
        ] as [String: Any]))
        let sessionID = try XCTUnwrap((data as? [String: Any])?["id"] as? String)

        try await MessageAPI(client: client, directory: directory).promptAsync(
            sessionID: sessionID, text: "Run the shell command `ls` using your shell tool."
        )

        let asked = try await waitFor("permission", recorder) {
            if case .permissionUpdated(let permission) = $0 { return permission.sessionID == sessionID }
            return false
        }
        guard case .permissionUpdated(let permission) = asked else { return }
        XCTAssertEqual(permission.variant, .v2)
        XCTAssertEqual(permission.permission, "shell")
        XCTAssertFalse(permission.tool?.callID.isEmpty ?? true)

        let pending = try await PermissionAPI(client: client).listAll(directory: directory)
        XCTAssertTrue(pending.contains { $0.id == permission.id })

        try await PermissionAPI(client: client).reply(to: permission, decision: .once)
        try await waitFor("permission replied", recorder) {
            if case .permissionReplied(let payload) = $0 { return payload.requestID == permission.id }
            return false
        }
        try await waitFor("idle", recorder, timeout: 180, isIdle(sessionID))
        try await SessionAPI(client: client).delete(id: sessionID)
    }

    /// The `question` tool, surfaced as a v1 question and answered through `QuestionAPI`.
    func testQuestionRoundTrip() async throws {
        let recorder = try await startRecording()
        defer { recorder.sse?.stop() }
        let session = try await newSession(title: "Question")

        try await MessageAPI(client: client, directory: directory).promptAsync(
            sessionID: session.id,
            text: "Use the question tool to ask me whether I prefer red or blue. Do nothing else."
        )

        let asked = try await waitFor("question", recorder) {
            if case .questionAsked(let request) = $0 { return request.sessionID == session.id }
            return false
        }
        guard case .questionAsked(let request) = asked else { return }
        let question = try XCTUnwrap(request.questions.first)
        XCTAssertFalse(question.options.isEmpty)
        XCTAssertNotNil(request.tool)

        let pending = try await QuestionAPI(client: client).list(directory: directory)
        XCTAssertTrue(pending.contains { $0.id == request.id })

        let choice = question.options[0].label
        try await QuestionAPI(client: client).reply(
            requestID: request.id,
            answers: request.questions.map { _ in [choice] },
            directory: directory,
            sessionID: request.sessionID
        )
        let replied = try await waitFor("question replied", recorder) {
            if case .questionReplied(let payload) = $0 { return payload.requestID == request.id }
            return false
        }
        if case .questionReplied(let payload) = replied {
            XCTAssertEqual(payload.answers.first, [choice])
        }
        try await waitFor("idle", recorder, timeout: 180, isIdle(session.id))
        try await SessionAPI(client: client).delete(id: session.id)
    }

    // MARK: - Changes, shell, commands

    /// A turn that writes a file: the transcript exposes the change the way v1 did,
    /// and the working-tree views see it too.
    func testEditTurnProducesDiffs() async throws {
        let recorder = try await startRecording()
        defer { recorder.sse?.stop() }
        let session = try await newSession(title: "Edit")
        let name = "note-\(UUID().uuidString.prefix(6)).txt"

        try await MessageAPI(client: client, directory: directory).promptAsync(
            sessionID: session.id,
            text: "Create a file named \(name) containing exactly the text: hello. Use your write tool. Do nothing else."
        )
        try await waitFor("idle", recorder, timeout: 180, isIdle(session.id))

        let messages = try await MessageAPI(client: client, directory: directory).list(sessionID: session.id)
        let changes = SessionChangeSet(messages: messages.map { $0.toModel() })
        XCTAssertTrue(changes.files.contains { $0.file.hasSuffix(name) }, "changes: \(changes.files.map(\.file))")
        XCTAssertGreaterThan(changes.additions, 0)

        let status = try await FileAPI(client: client).status(directory: directory)
        XCTAssertTrue(status.contains { $0.path.hasSuffix(name) }, "status: \(status.map(\.path))")
        let working = try await VcsAPI(client: client).diff(mode: .git, directory: directory)
        XCTAssertTrue(working.contains { $0.file.hasSuffix(name) })

        try await SessionAPI(client: client).delete(id: session.id)
        try? FileManager.default.removeItem(atPath: (directory as NSString).appendingPathComponent(name))
    }

    /// `!command` in the app — a session shell run shows up as a completed `shell` tool.
    func testSessionShellRun() async throws {
        let recorder = try await startRecording()
        defer { recorder.sse?.stop() }
        let session = try await newSession(title: "Shell")

        try await SessionAPI(client: client, directory: directory).shell(
            id: session.id, command: "echo opencody", agent: "build"
        )

        let done = try await waitFor("shell tool", recorder, timeout: 60) {
            guard case .messagePartUpdated(let payload) = $0, case .tool(let tool) = payload.part else { return false }
            return tool.tool == "shell" && tool.state.status == .completed
        }
        guard case .messagePartUpdated(let payload) = done, case .tool(let liveTool) = payload.part,
              case .completed(let liveState) = liveTool.state else { return }
        XCTAssertTrue(liveState.output?.contains("opencody") ?? false, "output: \(liveState.output ?? "")")

        let messages = try await MessageAPI(client: client, directory: directory).list(sessionID: session.id)
        let restParts = messages.flatMap(\.parts)
        XCTAssertTrue(restParts.contains { $0.id == liveTool.id }, "live shell part matches REST: \(restParts.map(\.id))")
        try await SessionAPI(client: client).delete(id: session.id)
    }

    /// A slash command runs a turn like a prompt does.
    func testSlashCommand() async throws {
        let recorder = try await startRecording()
        defer { recorder.sse?.stop() }
        let session = try await newSession(title: "Command")
        let commands = try await CommandAPI(client: client).list(directory: directory)
        let review = try XCTUnwrap(commands.first { $0.name == "review" }, "commands: \(commands.map(\.name))")

        try await CommandAPI(client: client).execute(sessionID: session.id, command: review.name, arguments: "README.md")
        try await waitFor("busy", recorder) {
            if case .sessionStatus(let p) = $0, p.sessionID == session.id, case .busy = p.status { return true }
            return false
        }
        try await SessionAPI(client: client, directory: directory).abort(id: session.id)
        try await waitFor("idle after abort", recorder, timeout: 60, isIdle(session.id))
        try await SessionAPI(client: client).delete(id: session.id)
    }
}

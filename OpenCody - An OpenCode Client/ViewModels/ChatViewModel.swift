//
//  ChatViewModel.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import Foundation

// MARK: - Part Helpers

/// Extends `Part` with computed properties for session/message scoping.
/// Each `Part` variant wraps a struct conforming to `PartFields` which has `sessionID` and `messageID`.
private extension Part {
    var sessionID: String {
        switch self {
        case .text(let p): return p.sessionID
        case .subtask(let p): return p.sessionID
        case .reasoning(let p): return p.sessionID
        case .file(let p): return p.sessionID
        case .tool(let p): return p.sessionID
        case .stepStart(let p): return p.sessionID
        case .stepFinish(let p): return p.sessionID
        case .snapshot(let p): return p.sessionID
        case .patch(let p): return p.sessionID
        case .agent(let p): return p.sessionID
        case .retry(let p): return p.sessionID
        case .compaction(let p): return p.sessionID
        case .unknown(let p): return p.sessionID
        }
    }

    var messageID: String {
        switch self {
        case .text(let p): return p.messageID
        case .subtask(let p): return p.messageID
        case .reasoning(let p): return p.messageID
        case .file(let p): return p.messageID
        case .tool(let p): return p.messageID
        case .stepStart(let p): return p.messageID
        case .stepFinish(let p): return p.messageID
        case .snapshot(let p): return p.messageID
        case .patch(let p): return p.messageID
        case .agent(let p): return p.messageID
        case .retry(let p): return p.messageID
        case .compaction(let p): return p.messageID
        case .unknown(let p): return p.messageID
        }
    }
}

// MARK: - ChatViewModel

/// Manages message list state, SSE event observation, prompt sending, and permission handling for a single session.
@Observable
final class ChatViewModel {

    // MARK: - Observable State

    var session: Session
    var messages: [MessageWithParts] = []
    var pendingPermission: Permission? = nil
    var pendingQuestionRequestIDs: Set<String> = []
    var error: String? = nil

    /// Server-reported session status. Updated from SSE events and REST polling.
    /// Drives `isGenerating` reactively instead of manual toggling.
    private(set) var sessionStatus: SessionStatus = .idle

    /// Optimistic local flag: set `true` when the user sends a prompt,
    /// cleared when the first server-side status event arrives.
    /// Bridges the gap between "user pressed send" and "server confirmed busy".
    private var isLocallyGenerating: Bool = false

    /// Whether the session is actively generating a response.
    ///
    /// Derived from:
    /// 1. Server-reported `sessionStatus` (`.busy` or `.retry`)
    /// 2. Optimistic local state (after sending a prompt, before server confirms)
    ///
    /// This can never get "stuck" because server status always resolves to idle,
    /// and the fallback polling ensures we see it.
    var isGenerating: Bool {
        switch sessionStatus {
        case .busy, .retry:
            return true
        case .idle:
            return isLocallyGenerating
        }
    }

    /// The first pending question request for the session, if any.
    /// Drives the `SessionQuestionDock` overlay.
    var activeQuestionRequest: QuestionRequest? {
        // Prefer the most recent visible tool-bound pending question to avoid
        // arbitrary Set iteration when multiple questions are pending.
        for message in messages.reversed() {
            for part in message.parts.reversed() {
                guard case .tool(let toolPart) = part else { continue }
                if let request = questionRequest(for: toolPart),
                   pendingQuestionRequestIDs.contains(request.id) {
                    return request
                }
            }
        }

        // Deterministic fallback by request ID.
        for id in pendingQuestionRequestIDs.sorted() {
            if let request = questionRequestsByID[id], pendingQuestionRequestIDs.contains(request.id) {
                return request
            }
        }
        return nil
    }

    /// Whether the session is blocked waiting for question input.
    var isBlockedByQuestion: Bool {
        !pendingQuestionRequestIDs.isEmpty
    }
    var isLoadingMore: Bool = false
    var hasMoreMessages: Bool = true
    var visibleMessageCount: Int = 0
    var selectedAgentID: String? = nil
    var selectedModelID: String? = nil
    var selectedProviderID: String? = nil

    /// Monotonically increasing counter bumped on every content mutation
    /// (streaming deltas, new parts, message upserts).  The ChatView
    /// observes this to auto-scroll during streaming.
    var scrollTrigger: UInt64 = 0

    /// Messages filtered for display: removes "step-only" messages (those containing
    /// exclusively step-start / step-finish parts with no real content).
    var displayMessages: [MessageWithParts] {
        let filtered = filteredMessagesCache
        guard visibleMessageCount > 0 else { return filtered }
        let count = min(filtered.count, visibleMessageCount)
        return Array(filtered.suffix(count))
    }

    /// Count of messages hidden by displayMessages filter (step-only messages).
    var hiddenStepMessageCount: Int {
        messages.count - filteredMessagesCache.count
    }

    // MARK: - Private

    @ObservationIgnored private let connectionManager: ConnectionManager
    @ObservationIgnored private var loadedMessageIDs: Set<String> = []
    @ObservationIgnored private var filteredMessagesCache: [MessageWithParts] = []
    /// Buffer for parts that arrived before their message via SSE.
    @ObservationIgnored private var pendingParts: [String: [Part]] = [:]
    /// Buffer for deltas that arrived before their part via SSE.
    @ObservationIgnored private var pendingDeltas: [String: [PartDeltaPayload]] = [:]
    /// Map tool call (messageID + callID) to question request.
    @ObservationIgnored private var questionRequestsByToolCall: [ToolCallKey: QuestionRequest] = [:]
    /// Map requestID to question request.
    @ObservationIgnored private var questionRequestsByID: [String: QuestionRequest] = [:]
    /// Local optimistic user messages pending server acknowledgement.
    @ObservationIgnored private var pendingLocalUserMessageIDs: Set<String> = []
    /// Last time an SSE event was received (used for fallback polling).
    @ObservationIgnored private var lastSSEEventAt: Date?
    /// Fallback polling task when SSE isn't delivering events.
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Monotonic generation to avoid stale poll-task teardown races.
    @ObservationIgnored private var pollTaskGeneration: UInt64 = 0
    /// Questions received via SSE before their tool/message becomes visible.
    @ObservationIgnored private var deferredQuestionRequestsByID: [String: QuestionRequest] = [:]
    /// Question IDs that have been confirmed as pending (via SSE event OR REST discovery).
    /// Once a question enters this set it is **sticky** — only an explicit reply/reject
    /// event (or session reset) can remove it.  This prevents transient REST empty
    /// responses from wiping known questions.
    @ObservationIgnored private var confirmedQuestionIDs: Set<String> = []
    /// Recently dismissed question IDs (answered/rejected locally). Maps ID → dismissal
    /// timestamp. REST polls ignore these IDs for a short cooldown to prevent the server's
    /// eventual-consistency lag from re-confirming a question the user already handled.
    @ObservationIgnored private var dismissedQuestionCooldowns: [String: Date] = [:]
    @ObservationIgnored private let dismissCooldownSeconds: TimeInterval = 10
    /// Throttle global (/question without directory) fallback scans.
    @ObservationIgnored private var lastGlobalQuestionScanAt: Date?
    @ObservationIgnored private let globalQuestionScanInterval: TimeInterval = 10
    @ObservationIgnored private let initialMessageBatch = 60
    @ObservationIgnored private let loadMoreBatch = 40

    // MARK: - Init

    init(session: Session, connectionManager: ConnectionManager) {
        self.session = session
        self.connectionManager = connectionManager
    }

    // MARK: - Public API

    /// Fetch all messages (with parts) for this session from the server.
    /// Also syncs `isGenerating` with the server's current session status.
    func loadMessages() async {
        guard let client = connectionManager.activeAPIClient else {
            error = "No active server connection"
            return
        }

        error = nil
        let wasFullyLoaded = !hasMoreMessages && visibleMessageCount > 0

        do {
            let api = MessageAPI(client: client, directory: session.directory)
            let responses = try await api.list(sessionID: session.id)
            messages = responses.map { $0.toModel() }
            loadedMessageIDs = Set(messages.map(\.id))
            refreshFilteredMessages()
            updatePaginationState(wasFullyLoaded: wasFullyLoaded)
            await refreshPendingQuestions(client: client)
            await refreshPendingPermission(client: client)
            restoreAgentModelFromMessages()
            // Load server-side defaults (agent + model) when none were set from message history.
            // This ensures new/empty sessions reflect the server's configured defaults.
            if selectedModelID == nil || selectedAgentID == nil {
                await loadDefaultsFromServer(client: client)
            }
            // Sync isGenerating with actual server status so we never get stuck.
            await syncGeneratingStatus(client: client)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Queries the server for the current session status and updates `sessionStatus`.
    /// Called after loading messages to ensure the UI reflects the true server state.
    private func syncGeneratingStatus(client: APIClient) async {
        let sessionAPI = SessionAPI(client: client, directory: session.directory)
        if let statusMap = try? await sessionAPI.status() {
            let status = statusMap[session.id] ?? .idle
            sessionStatus = status
            isLocallyGenerating = false  // Server is authoritative.
            switch status {
            case .idle:
                if !isBlockedByQuestion {
                    pollTask?.cancel()
                    pollTask = nil
                }
            case .busy, .retry:
                startFallbackPollingIfNeeded()
            }
        }
    }

    /// Load older messages. Currently a no-op since the API returns all messages at once.
    /// Kept for future pagination support.
    func loadMore() async {
        guard hasMoreMessages, !isLoadingMore else { return }
        isLoadingMore = true
        let total = filteredMessagesCache.count
        let target = min(total, visibleMessageCount + loadMoreBatch)
        visibleMessageCount = target
        hasMoreMessages = total > visibleMessageCount
        isLoadingMore = false
    }

    /// Send a text prompt to the session. The actual response arrives via SSE events.
    func sendPrompt(
        _ text: String,
        attachments: [PromptAttachment] = [],
        modelID: String? = nil,
        providerID: String? = nil,
        agent: String? = nil
    ) async {
        guard let client = connectionManager.activeAPIClient else {
            error = "No active server connection"
            return
        }

        appendLocalUserMessage(text: text, attachments: attachments)
        isLocallyGenerating = true
        error = nil

        do {
            let api = MessageAPI(client: client, directory: session.directory)
            try await api.promptAsync(
                sessionID: session.id,
                text: text,
                modelID: modelID ?? selectedModelID,
                providerID: providerID ?? selectedProviderID,
                agent: agent ?? selectedAgentID,
                attachments: attachments
            )
            startFallbackPollingIfNeeded()
        } catch {
            // Reset isLocallyGenerating if the send call itself failed.
            isLocallyGenerating = false
            self.error = error.localizedDescription
        }
    }

    /// Execute a slash command in the session.
    /// The command name should NOT include the leading "/".
    func executeCommand(name: String, arguments: String? = nil) async {
        guard let client = connectionManager.activeAPIClient else {
            error = "No active server connection"
            return
        }

        // Show the command as a local user message for immediate feedback
        let displayText = "/" + name + (arguments.map { " " + $0 } ?? "")
        appendLocalUserMessage(text: displayText, attachments: [])
        isLocallyGenerating = true
        error = nil

        do {
            let api = CommandAPI(client: client)
            try await api.execute(
                sessionID: session.id,
                command: name,
                arguments: arguments ?? ""
            )
            startFallbackPollingIfNeeded()
        } catch {
            isLocallyGenerating = false
            self.error = error.localizedDescription
        }
    }

    /// Execute a shell command in the session.
    /// The response arrives via SSE events, similar to prompts and commands.
    func executeShellCommand(command: String) async {
        guard let client = connectionManager.activeAPIClient else {
            error = "No active server connection"
            return
        }

        appendLocalUserMessage(text: "$ " + command, attachments: [])
        isLocallyGenerating = true
        error = nil

        do {
            let api = SessionAPI(client: client, directory: session.directory)
            try await api.shell(id: session.id, command: command, agent: selectedAgentID ?? "coder", providerID: selectedProviderID, modelID: selectedModelID)
            startFallbackPollingIfNeeded()
        } catch {
            isLocallyGenerating = false
            self.error = error.localizedDescription
        }
    }

    /// Abort the currently running generation for this session.
    func abort() async throws {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }

        let api = SessionAPI(client: client, directory: session.directory)
        try await api.abort(id: session.id)
        // Reset immediately as a fallback.
        // Normally the server sends a session.idle SSE event, but if SSE
        // is lagging or the event is missed the UI would stay stuck.
        sessionStatus = .idle
        isLocallyGenerating = false
        pendingPermission = nil
        pendingQuestionRequestIDs.removeAll()
        questionRequestsByToolCall.removeAll()
        questionRequestsByID.removeAll()
        deferredQuestionRequestsByID.removeAll()
        confirmedQuestionIDs.removeAll()
        dismissedQuestionCooldowns.removeAll()
        pollTask?.cancel()
        pollTask = nil
    }

    /// Reply to a pending permission request.
    ///
    /// Routes through `PermissionAPI`, which picks the v1/v2 endpoint from the
    /// request's `variant` and falls back to the deprecated per-session route on
    /// servers that predate the dedicated permission endpoints.
    func replyToPermission(_ permission: Permission, decision: PermissionReplyDecision) async throws {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }

        // Clear optimistically so the sheet dismisses even if the reply is slow.
        if pendingPermission?.id == permission.id {
            pendingPermission = nil
        }

        let api = PermissionAPI(client: client)
        do {
            try await api.reply(to: permission, decision: decision)
        } catch {
            // Restore the prompt so the user can retry.
            pendingPermission = permission
            throw error
        }
    }

    /// Reply to a pending question request.
    func replyToQuestion(_ request: QuestionRequest, answers: [QuestionAnswer]) async throws {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }

        #if DEBUG
        print("[ChatViewModel] replyToQuestion requestID=\(request.id) session=\(request.sessionID) answers=\(answers)")
        #endif
        let api = QuestionAPI(client: client)
        do {
            try await api.reply(requestID: request.id, answers: answers)
            #if DEBUG
            print("[ChatViewModel] replyToQuestion SUCCESS requestID=\(request.id)")
            #endif
        } catch {
            #if DEBUG
            print("[ChatViewModel] replyToQuestion FAILED requestID=\(request.id) error=\(error)")
            #endif
            throw error
        }
        removeQuestionRequest(request)
        isLocallyGenerating = true
        startFallbackPollingIfNeeded()
    }

    /// Reject a pending question request.
    func rejectQuestion(_ request: QuestionRequest) async throws {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }

        #if DEBUG
        print("[ChatViewModel] rejectQuestion requestID=\(request.id) session=\(request.sessionID)")
        #endif
        let api = QuestionAPI(client: client)
        do {
            try await api.reject(requestID: request.id)
            #if DEBUG
            print("[ChatViewModel] rejectQuestion SUCCESS requestID=\(request.id)")
            #endif
        } catch {
            #if DEBUG
            print("[ChatViewModel] rejectQuestion FAILED requestID=\(request.id) error=\(error)")
            #endif
            throw error
        }
        removeQuestionRequest(request)
        isLocallyGenerating = true
        startFallbackPollingIfNeeded()
    }

    // MARK: - SSE Event Observation

    @ObservationIgnored private var eventToken: UUID?
    @ObservationIgnored private var refreshToken: UUID?

    /// Subscribe to SSE events for live message/part/permission updates.
    func startObservingEvents() {
        // Do not scope SSE stream by directory here.
        // Directory-prefix filtering can drop valid session events (status/question)
        // when path normalization differs between server/client. We route by session
        // inside handleEvent/isEventForSession and keep REST as fallback.
        connectionManager.setActiveEventDirectory(nil)
        eventToken = connectionManager.subscribeToEvents { [weak self] event in
            self?.handleEvent(event)
        }
        refreshToken = connectionManager.subscribeToRefresh { [weak self] in
            guard let self else { return }
            Task {
                await self.loadMessages()
            }
        }

    }

    /// Unsubscribe from SSE events.
    func stopObservingEvents() {
        if let t = eventToken { connectionManager.unsubscribeFromEvents(token: t) }
        if let t = refreshToken { connectionManager.unsubscribeFromRefresh(token: t) }
        eventToken = nil
        refreshToken = nil

        // Keep global stream mode.
        connectionManager.setActiveEventDirectory(nil)
        pollTask?.cancel()
        pollTask = nil
    }


    /// Restore agent/model/provider selection from the last user message in this session.
    /// Called after loading messages so the picker reflects what was actually used.
    private func restoreAgentModelFromMessages() {
        // Find the last user message that has agent or model info
        let lastUserMessage = messages.reversed().compactMap { mwp -> UserMessage? in
            if case .user(let um) = mwp.message { return um }
            return nil
        }.first

        if let um = lastUserMessage {
            if let agent = um.agent {
                selectedAgentID = agent
            }
            if let model = um.model {
                selectedProviderID = model.providerID
                selectedModelID = model.modelID
            }
        }
    }

    /// Fetch server config and provider defaults, then populate selectedAgentID / selectedModelID
    /// / selectedProviderID if they are still unset (i.e. no prior messages carried those values).
    /// This ensures the picker always reflects the server-side defaults for a new session.
    private func loadDefaultsFromServer(client: APIClient) async {
        async let configFetch = ConfigAPI(client: client).get()
        async let providerFetch = ProviderAPI(client: client).list()

        let config = try? await configFetch
        let providerResponse = try? await providerFetch

        // --- Default Model ---
        // ServerConfig.model is formatted as "providerID/modelID"
        if selectedModelID == nil, let modelString = config?.model, !modelString.isEmpty {
            let parts = modelString.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                selectedProviderID = parts[0]
                selectedModelID = parts[1]
            }
        }

        // Fallback: use the provider-level default if config.model had no value
        if selectedModelID == nil, let defaults = providerResponse?.default {
            // defaults is [providerID: modelID], pick the first connected provider that has a default
            let connected = providerResponse?.connected ?? []
            for providerID in connected {
                if let modelID = defaults[providerID], !modelID.isEmpty {
                    selectedProviderID = providerID
                    selectedModelID = modelID
                    break
                }
            }
        }

        // --- Default Agent ---
        // The server has a primary agent (usually "coder"). Reflect it in the picker
        // only if no agent was already set from message history.
        // We leave selectedAgentID = nil when we can't determine a meaningful default,
        // because nil = "Default Agent" (server picks) which is always correct.
        if selectedAgentID == nil, let agents = try? await AgentAPI(client: client).list() {
            // Prefer the agent configured as 'primary' mode; fall back to "coder".
            let primary = agents.first { $0.mode == AgentMode.primary }
            let coder = agents.first { $0.name == "coder" }
            if let defaultAgent = primary ?? coder {
                selectedAgentID = defaultAgent.name
            }
        }
    }

    // MARK: - Private

    private func handleEvent(_ event: SSEEvent) {
        if isEventForSession(event) {
            lastSSEEventAt = Date()
        }

        switch event {
        case .messageUpdated(let message):
            guard message.sessionID == session.id else { return }
            if case .user = message, !pendingLocalUserMessageIDs.isEmpty {
                messages.removeAll { pendingLocalUserMessageIDs.contains($0.id) }
                pendingLocalUserMessageIDs.removeAll()
            }
            upsertMessage(message)

        case .messageRemoved(let payload):
            guard payload.sessionID == session.id else { return }
            messages.removeAll { $0.id == payload.messageID }
            loadedMessageIDs.remove(payload.messageID)
            refreshFilteredMessages()

        case .messagePartUpdated(let payload):
            let part = payload.part
            guard part.sessionID == session.id else { return }
            upsertPart(part)
            if let delta = payload.delta, !delta.isEmpty {
                let deltaPayload = PartDeltaPayload(
                    sessionID: part.sessionID,
                    messageID: part.messageID,
                    partID: part.id,
                    field: "text",
                    delta: delta
                )
                applyDelta(deltaPayload)
            }

        case .messagePartRemoved(let payload):
            guard payload.sessionID == session.id else { return }
            if let msgIdx = messages.firstIndex(where: { $0.id == payload.messageID }) {
                messages[msgIdx].parts.removeAll { $0.id == payload.partID }
                refreshFilteredMessages()
            }

        case .permissionUpdated(let permission):
            guard permission.sessionID == session.id else { return }
            pendingPermission = permission

        case .permissionReplied(let payload):
            guard payload.sessionID == session.id else { return }
            pendingPermission = nil

        case .questionAsked(let request):
            // Simplified question handling: show immediately if for this session.
            // The reference implementation proves that session-scoped question
            // display (without tool-part matching) works reliably.
            guard request.sessionID == session.id else { return }
            storeQuestionRequest(request)
#if DEBUG
            print("[ChatViewModel] question.asked accepted id=\(request.id) session=\(request.sessionID)")
#endif
            // Ensure watchdog is active even if session status switched to idle
            // while waiting for the question reply.
            if pollTask == nil {
                startFallbackPollingIfNeeded()
            }

        case .questionReplied(let payload):
            guard payload.sessionID == session.id || pendingQuestionRequestIDs.contains(payload.requestID) else { return }
            removeQuestionRequest(withID: payload.requestID)
            deferredQuestionRequestsByID.removeValue(forKey: payload.requestID)

        case .questionRejected(let payload):
            guard payload.sessionID == session.id || pendingQuestionRequestIDs.contains(payload.requestID) else { return }
            removeQuestionRequest(withID: payload.requestID)
            deferredQuestionRequestsByID.removeValue(forKey: payload.requestID)

        case .sessionStatus(let payload):
            guard payload.sessionID == session.id else { return }
            sessionStatus = payload.status
            isLocallyGenerating = false  // Server status is authoritative; clear optimistic flag.
            switch payload.status {
            case .idle:
                // When session goes idle due to a question, don't kill the poll task.
                // The poll loop checks isBlockedByQuestion to stay alive.
                if !isBlockedByQuestion {
                    pollTask?.cancel()
                    pollTask = nil
                }
                // Safety net: trigger a one-shot question poll in case the SSE
                // question.asked event was missed during a reconnection gap.
                Task { [weak self] in
                    await self?.pollPendingQuestions()
                    // If we just discovered a question and had no poll task, start one
                    if let self, self.isBlockedByQuestion, self.pollTask == nil {
                        self.startFallbackPollingIfNeeded()
                    }
                }
            case .busy, .retry:
                if pollTask == nil {
                    startFallbackPollingIfNeeded()
                }
            }

        case .sessionIdle(let sessionID):
            guard sessionID == session.id else { return }
            sessionStatus = .idle
            isLocallyGenerating = false
            if !isBlockedByQuestion {
                pollTask?.cancel()
                pollTask = nil
            }
            // Safety net: poll for questions that might have been missed via SSE
            Task { [weak self] in
                await self?.pollPendingQuestions()
                if let self, self.isBlockedByQuestion, self.pollTask == nil {
                    self.startFallbackPollingIfNeeded()
                }
            }


        case .messagePartDelta(let payload):
            guard payload.sessionID == session.id else { return }
            applyDelta(payload)
        case .sessionUpdated(let updatedSession):
            guard updatedSession.id == session.id else { return }
            session = updatedSession

        case .sessionDiff(let payload):
            guard payload.sessionID == session.id else { return }
            // Only re-fetch when the event actually carries diff data.
            //
            // The server publishes `session.diff` with a hardcoded empty array and
            // resets `Session.summary` to {0, 0, 0} at the same time, so an
            // unconditional re-fetch here fired on every event and could never
            // recover a summary. Real per-turn diffs come from the message list —
            // see `SessionChangeSet`.
            guard !payload.diff.isEmpty else { return }
            Task { [weak self] in
                guard let self, let client = self.connectionManager.activeAPIClient else { return }
                if let updated = try? await SessionAPI(client: client, directory: self.session.directory)
                    .get(id: payload.sessionID) {
                    self.session = updated
                }
            }

        default:
#if DEBUG
            if case .unknown(let eventName, _) = event {
                print("[ChatViewModel] unknown SSE event: \(eventName)")
            }
#endif
            break
        }
    }

    private func isEventForSession(_ event: SSEEvent) -> Bool {
        switch event {
        case .messageUpdated(let message):
            return message.sessionID == session.id
        case .messageRemoved(let payload):
            return payload.sessionID == session.id
        case .messagePartUpdated(let payload):
            return payload.part.sessionID == session.id
        case .messagePartRemoved(let payload):
            return payload.sessionID == session.id
        case .messagePartDelta(let payload):
            return payload.sessionID == session.id
        case .permissionUpdated(let permission):
            return permission.sessionID == session.id
        case .permissionReplied(let payload):
            return payload.sessionID == session.id
        case .questionAsked(let request):
            return request.sessionID == session.id
        case .questionReplied(let payload):
            return payload.sessionID == session.id
        case .questionRejected(let payload):
            return payload.sessionID == session.id
        case .sessionStatus(let payload):
            return payload.sessionID == session.id
        case .sessionIdle(let sessionID):
            return sessionID == session.id
        case .sessionUpdated(let updatedSession):
            return updatedSession.id == session.id
        case .sessionDiff(let payload):
            return payload.sessionID == session.id
        default:
            return false
        }
    }

    /// Start a periodic watchdog that ensures `isGenerating` is eventually reset.
    ///
    /// Even when SSE events are flowing, the watchdog periodically polls the server
    /// for session status. This guards against silently dropped `session.idle` events
    /// that would otherwise leave `isGenerating` stuck at `true` forever.
    ///
    /// The loop stays alive while `isGenerating` OR `isBlockedByQuestion` — when the
    /// server is waiting for a question answer it reports `idle`, but we must keep
    /// polling so the question dock appears and the loop resumes after the user answers.
    private func startFallbackPollingIfNeeded() {
        pollTask?.cancel()
        pollTaskGeneration &+= 1
        let generation = pollTaskGeneration
        pollTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.pollTaskGeneration == generation {
                    self.pollTask = nil
                }
            }
            // Poll immediately at least once. If the server transitions to idle quickly
            // because it's waiting on a question, a delayed first poll can miss the
            // pending question and terminate too early.
            while !Task.isCancelled {
                // Poll questions FIRST — must discover pending questions before
                // pollSessionStatus() sets isGenerating=false, which would exit
                // the loop if no question was found yet.
                await self.pollPendingQuestions()
                await self.pollSessionStatus()

                let shouldContinue = self.isGenerating || self.isBlockedByQuestion
                if !shouldContinue || Task.isCancelled {
                    // Grace window for eventual consistency: when session flips to idle,
                    // the pending question may appear via REST moments later.
                    var recovered = false
                    for _ in 0..<3 where !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        await self.pollPendingQuestions()
                        if self.isBlockedByQuestion {
                            recovered = true
                            break
                        }
                    }
                    if !recovered || Task.isCancelled {
                        break
                    }
                }

                // If SSE is silent, also poll for messages (full sync).
                let sseRecent = self.lastSSEEventAt.map { Date().timeIntervalSince($0) < 5 } ?? false
                if !sseRecent && self.isGenerating {
                    await self.pollForCompletion()
                }

                try? await Task.sleep(for: .seconds(1))
            }

        }
    }

    /// Quick check of session status via REST. Updates `sessionStatus` if idle.
    ///
    /// Does NOT cancel the poll task — the loop condition (`isGenerating || isBlockedByQuestion`)
    /// handles termination. This prevents killing the poll while a question is pending.
    private func pollSessionStatus() async {
        guard let client = connectionManager.activeAPIClient else { return }
        let sessionAPI = SessionAPI(client: client, directory: session.directory)
        if let statusMap = try? await sessionAPI.status() {
            let status = statusMap[session.id] ?? .idle
#if DEBUG
            let inMap = statusMap[session.id] != nil
            print("[ChatViewModel] pollSessionStatus session=\(session.id) status=\(status) inMap=\(inMap) generating=\(isGenerating) blocked=\(isBlockedByQuestion)")
#endif
            sessionStatus = status
            isLocallyGenerating = false  // Server is authoritative.
            // Don't cancel pollTask here — the loop condition handles termination.
            // If isBlockedByQuestion is true, we need the loop to stay alive.
        }
    }

    /// Poll for pending questions via REST. Ensures question dock appears even if SSE event was missed.
    private func pollPendingQuestions() async {
        guard let client = connectionManager.activeAPIClient else { return }
        await refreshPendingQuestions(client: client)
    }

    /// Poll the message list until a new assistant message appears or generation ends.
    private func pollForCompletion() async {
        guard let client = connectionManager.activeAPIClient else { return }
        let api = MessageAPI(client: client, directory: session.directory)
        let sessionAPI = SessionAPI(client: client, directory: session.directory)
        let questionAPI = QuestionAPI(client: client)

        var attempts = 0
        while isGenerating && attempts < 60 {
            if let last = lastSSEEventAt, Date().timeIntervalSince(last) < 2 {
                attempts += 1
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            do {
                let responses = try await api.list(sessionID: session.id)
                let updated = responses.map { $0.toModel() }
                if shouldReplaceMessages(with: updated) {
                    messages = updated
                    loadedMessageIDs = Set(updated.map(\.id))
                    pendingLocalUserMessageIDs.removeAll()
                    refreshFilteredMessages()
                    updatePaginationState(wasFullyLoaded: false)
                }

                await refreshPendingQuestions(api: questionAPI)

                if let statusMap = try? await sessionAPI.status() {
                    let status = statusMap[session.id] ?? .idle
                    if case .idle = status {
                        sessionStatus = .idle
                        isLocallyGenerating = false
                        if !isBlockedByQuestion {
                            pollTask?.cancel()
                            pollTask = nil
                        }
                        return
                    }
                }
            } catch {
                // Ignore transient errors; try again
            }

            attempts += 1
            try? await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: - Question Requests

    struct ToolCallKey: Hashable, Sendable {
        let messageID: String
        let callID: String
    }

    func questionRequest(for tool: ToolPart) -> QuestionRequest? {
        let key = ToolCallKey(messageID: tool.messageID, callID: tool.callID)
        if let mapped = questionRequestsByToolCall[key] {
            return mapped
        }

        // Fallback for payloads with missing/legacy fields:
        // match pending requests by strict message+call where both call IDs are present.
        for request in questionRequestsByID.values {
            guard pendingQuestionRequestIDs.contains(request.id) else { continue }
            guard let ref = request.tool else { continue }
            guard ref.messageID == tool.messageID else { continue }
            guard !ref.callID.isEmpty, !tool.callID.isEmpty else { continue }
            if ref.callID == tool.callID {
                return request
            }
        }

        // Last-resort fallback when call IDs are missing/mismatched in payloads:
        // match by message ID when there is a single unambiguous candidate.
        let looseCandidates = questionRequestsByID.values.filter { request in
            guard pendingQuestionRequestIDs.contains(request.id) else { return false }
            guard let ref = request.tool else { return false }
            guard ref.messageID == tool.messageID else { return false }
            guard tool.tool == "question" else { return false }
            if !ref.callID.isEmpty, !tool.callID.isEmpty {
                return ref.callID == tool.callID
            }
            return true
        }
        if looseCandidates.count == 1 {
            return looseCandidates[0]
        }
        return nil
    }

    private func storeQuestionRequest(_ request: QuestionRequest) {
        questionRequestsByID[request.id] = request
        pendingQuestionRequestIDs.remove(request.id)
        pendingQuestionRequestIDs.insert(request.id)
        deferredQuestionRequestsByID.removeValue(forKey: request.id)
        confirmedQuestionIDs.insert(request.id)
        if let tool = request.tool {
            if !tool.callID.isEmpty {
                let key = ToolCallKey(messageID: tool.messageID, callID: tool.callID)
                questionRequestsByToolCall[key] = request
            }
        }
#if DEBUG
        if let tool = request.tool {
            print("[ChatViewModel] Stored question request id=\(request.id) session=\(request.sessionID) tool=(msg=\(tool.messageID), call=\(tool.callID))")
        } else {
            print("[ChatViewModel] Stored question request id=\(request.id) session=\(request.sessionID) (no tool ref)")
        }
#endif
    }

    private func removeQuestionRequest(_ request: QuestionRequest) {
        removeQuestionRequest(withID: request.id)
    }

    private func removeQuestionRequest(withID requestID: String) {
        pendingQuestionRequestIDs.remove(requestID)
        confirmedQuestionIDs.remove(requestID)
        dismissedQuestionCooldowns[requestID] = Date()
        deferredQuestionRequestsByID.removeValue(forKey: requestID)
        if let existing = questionRequestsByID.removeValue(forKey: requestID),
           let tool = existing.tool {
            let key = ToolCallKey(messageID: tool.messageID, callID: tool.callID)
            questionRequestsByToolCall.removeValue(forKey: key)
        }
    }

    private func refreshPendingQuestions(client: APIClient) async {
        let api = QuestionAPI(client: client)
        await refreshPendingQuestions(api: api)
    }

    /// Recover a permission request that was asked while the app was not listening.
    ///
    /// `permission.asked` arrives over SSE, so a request raised while the app was
    /// backgrounded (or before the stream connected) would otherwise never be
    /// shown and the session would appear silently stuck. Re-reading the pending
    /// list on load closes that gap.
    private func refreshPendingPermission(client: APIClient) async {
        // Don't clobber a request the user is already looking at.
        guard pendingPermission == nil else { return }

        let api = PermissionAPI(client: client)
        guard let pending = try? await api.listAll(directory: session.directory) else { return }
        pendingPermission = pending.first { $0.sessionID == session.id }
    }

    /// Refresh pending questions from REST, merging with confirmed state.
    ///
    /// REST results are **additive**: newly discovered questions are added and
    /// marked as confirmed.  Confirmed questions (whether discovered via SSE or
    /// a previous REST poll) can NEVER be removed by a subsequent empty REST
    /// response.  Only explicit `question.replied` / `question.rejected` events
    /// (handled elsewhere) clear confirmed questions.
    private func refreshPendingQuestions(api: QuestionAPI) async {
        do {
            var all = try await api.list(directory: session.directory)
            // Fallback: some server setups/path normalizations can return empty when
            // filtering by directory. Retry global list occasionally while generating
            // or when already blocked by a question.
            if all.isEmpty {
                let now = Date()
                let shouldScanGlobal: Bool = {
                    guard let last = lastGlobalQuestionScanAt else { return true }
                    return now.timeIntervalSince(last) >= globalQuestionScanInterval
                }()
                if shouldScanGlobal {
                    lastGlobalQuestionScanAt = now
                    if let global = try? await api.list(directory: nil), !global.isEmpty {
                        all = global
#if DEBUG
                        print("[ChatViewModel] refreshPendingQuestions used global fallback count=\(global.count)")
#endif
                    }
                }
            }
            // Filter to this session only.
            let pending = all.filter { $0.sessionID == session.id }
            var byID = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0) })

            // Expire old cooldowns and skip recently-dismissed questions so that
            // REST eventual-consistency lag doesn't resurrect answered questions.
            let now = Date()
            dismissedQuestionCooldowns = dismissedQuestionCooldowns.filter { _, dismissedAt in
                now.timeIntervalSince(dismissedAt) < dismissCooldownSeconds
            }
            for cooldownID in dismissedQuestionCooldowns.keys {
                byID.removeValue(forKey: cooldownID)
            }

            // Mark every REST-discovered question as confirmed so future empty
            // REST responses can't wipe it.
            for id in byID.keys {
                confirmedQuestionIDs.insert(id)
            }

            // Preserve confirmed questions that REST didn't return this time.
            // These are sticky — only reply/reject events can remove them.
            for requestID in confirmedQuestionIDs {
                guard byID[requestID] == nil else { continue }
                guard let local = questionRequestsByID[requestID] else { continue }
                byID[requestID] = local
            }

#if DEBUG
            print("[ChatViewModel] refreshPendingQuestions rest=\(pending.count) confirmed=\(confirmedQuestionIDs.count) final=\(byID.count)")
#endif
            questionRequestsByID = byID
            pendingQuestionRequestIDs = Set(byID.keys)
            questionRequestsByToolCall = byID.values.reduce(into: [:]) { result, request in
                if let tool = request.tool, !tool.callID.isEmpty {
                    let key = ToolCallKey(messageID: tool.messageID, callID: tool.callID)
                    result[key] = request
                }
            }
        } catch {
            // Ignore transient errors; questions will refresh later
        }
    }

    private func shouldReplaceMessages(with updated: [MessageWithParts]) -> Bool {
        messageSignature(for: messages) != messageSignature(for: updated)
    }

    private func messageSignature(for items: [MessageWithParts]) -> String {
        items.map { item in
            let partSignature = item.parts.map { part in
                switch part {
                case .text(let p):
                    return "text:\(p.id):\(p.text.count)"
                case .reasoning(let p):
                    return "reasoning:\(p.id):\(p.text.count)"
                case .file(let p):
                    return "file:\(p.id):\(p.filename ?? ""): \(p.url ?? "")"
                case .tool(let p):
                    return "tool:\(p.id):\(p.state.status.rawValue)"
                case .stepStart(let p):
                    return "stepStart:\(p.id):\(p.snapshot ?? "")"
                case .stepFinish(let p):
                    return "stepFinish:\(p.id):\(p.reason)"
                case .snapshot(let p):
                    return "snapshot:\(p.id):\(p.snapshot.count)"
                case .patch(let p):
                    return "patch:\(p.id):\(p.hash ?? "")"
                case .agent(let p):
                    return "agent:\(p.id):\(p.name)"
                case .retry(let p):
                    return "retry:\(p.id):\(p.attempt)"
                case .compaction(let p):
                    return "compaction:\(p.id):\(p.auto)"
                case .subtask(let p):
                    return "subtask:\(p.id):\(p.prompt ?? "")"
                case .unknown(let p):
                    return "unknown:\(p.id):\(p.type)"
                }
            }.joined(separator: ",")
            return "\(item.id):\(partSignature)"
        }.joined(separator: "|")
    }

    /// Upsert a message into the messages array. Updates existing or appends new.
    private func upsertMessage(_ message: Message) {
        let wasFullyLoaded = !hasMoreMessages && visibleMessageCount > 0
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = MessageWithParts(message: message, parts: messages[idx].parts)
        } else {
            // Flush any parts that arrived before this message
            let buffered = pendingParts.removeValue(forKey: message.id) ?? []
            messages.append(MessageWithParts(message: message, parts: buffered))
            for part in buffered {
                drainPendingDeltas(forPartID: part.id)
            }
            loadedMessageIDs.insert(message.id)
        }
        refreshFilteredMessages()
        updatePaginationState(wasFullyLoaded: wasFullyLoaded)
        scrollTrigger &+= 1
    }

    /// Add a local optimistic user message so the chat feels instant.
    private func appendLocalUserMessage(text: String, attachments: [PromptAttachment]) {
        let wasFullyLoaded = !hasMoreMessages && visibleMessageCount > 0
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText: String
        if trimmed.isEmpty, !attachments.isEmpty {
            let count = attachments.count
            displayText = count == 1 ? "Sent 1 attachment" : "Sent \(count) attachments"
        } else {
            displayText = trimmed
        }

        guard !displayText.isEmpty else { return }

        let now = Date().timeIntervalSince1970
        let tempMessageID = "local-user-\(UUID().uuidString)"
        let tempPartID = "local-part-\(UUID().uuidString)"

        let model: MessageModel?
        if let providerID = selectedProviderID, let modelID = selectedModelID {
            model = MessageModel(providerID: providerID, modelID: modelID)
        } else {
            model = nil
        }

        let userMessage = UserMessage(
            id: tempMessageID,
            sessionID: session.id,
            role: "user",
            time: UserMessageTime(created: now),
            summary: nil,
            agent: selectedAgentID,
            model: model,
            system: nil,
            tools: nil
        )

        let part = TextPart(
            id: tempPartID,
            sessionID: session.id,
            messageID: tempMessageID,
            type: "text",
            text: displayText,
            synthetic: true,
            ignored: nil,
            time: nil,
            metadata: nil
        )

        messages.append(MessageWithParts(message: .user(userMessage), parts: [.text(part)]))
        pendingLocalUserMessageIDs.insert(tempMessageID)
        refreshFilteredMessages()
        updatePaginationState(wasFullyLoaded: wasFullyLoaded)
        scrollTrigger &+= 1
    }

    /// Upsert a part into the matching message's parts array.
    private func upsertPart(_ part: Part) {
        guard let msgIdx = messages.firstIndex(where: { $0.id == part.messageID }) else {
            // Message not yet received — buffer the part
            pendingParts[part.messageID, default: []].removeAll { $0.id == part.id }
            pendingParts[part.messageID, default: []].append(part)
            return
        }
        if let partIdx = messages[msgIdx].parts.firstIndex(where: { $0.id == part.id }) {
            messages[msgIdx].parts[partIdx] = part
        } else {
            messages[msgIdx].parts.append(part)
        }
        refreshFilteredMessages()
        drainPendingDeltas(forPartID: part.id)
    }

    private func refreshFilteredMessages() {
        filteredMessagesCache = messages.filter { mwp in
            // User messages always shown
            if mwp.message.role == .user { return true }
            // Empty parts → show (placeholder "…")
            if mwp.parts.isEmpty { return true }
            // Keep if at least one part is NOT step-start/step-finish
            return mwp.parts.contains { part in
                switch part {
                case .stepStart, .stepFinish: return false
                default: return true
                }
            }
        }
    }

    private func updatePaginationState(wasFullyLoaded: Bool) {
        let total = filteredMessagesCache.count
        if visibleMessageCount == 0 {
            visibleMessageCount = min(total, initialMessageBatch)
        } else if wasFullyLoaded {
            visibleMessageCount = total
        } else if visibleMessageCount > total {
            visibleMessageCount = total
        }
        hasMoreMessages = total > visibleMessageCount
    }

    /// Apply a streaming text delta to an existing part.
    /// Reconstructs the Part with the appended text since Part fields are immutable.
    private func applyDelta(_ delta: PartDeltaPayload) {
        guard let msgIdx = messages.firstIndex(where: { $0.id == delta.messageID }) else {
            bufferDelta(delta)
            return
        }
        guard let partIdx = messages[msgIdx].parts.firstIndex(where: { $0.id == delta.partID }) else {
            bufferDelta(delta)
            return
        }

        let existingPart = messages[msgIdx].parts[partIdx]

        switch existingPart {
        case .text(let tp):
            guard delta.field.isEmpty || delta.field == "text" || delta.field == "content" else { break }
            // Reconstruct TextPart with appended delta text
            let updatedText = tp.text + delta.delta
            let updated = TextPart(
                id: tp.id,
                sessionID: tp.sessionID,
                messageID: tp.messageID,
                type: tp.type,
                text: updatedText,
                synthetic: tp.synthetic,
                ignored: tp.ignored,
                time: tp.time,
                metadata: tp.metadata
            )
            messages[msgIdx].parts[partIdx] = .text(updated)
            refreshFilteredMessages()
            scrollTrigger &+= 1

        case .reasoning(let rp):
            guard delta.field.isEmpty || delta.field == "text" || delta.field == "reasoning" || delta.field == "content" else { break }
            // Reconstruct ReasoningPart with appended delta text
            let updatedText = rp.text + delta.delta
            let updated = ReasoningPart(
                id: rp.id,
                sessionID: rp.sessionID,
                messageID: rp.messageID,
                type: rp.type,
                text: updatedText,
                metadata: rp.metadata,
                time: rp.time
            )
            messages[msgIdx].parts[partIdx] = .reasoning(updated)
            refreshFilteredMessages()
            scrollTrigger &+= 1

        default:
            // Other part types don't have streaming text deltas
            break
        }
    }

    private func bufferDelta(_ delta: PartDeltaPayload) {
        pendingDeltas[delta.partID, default: []].append(delta)
    }

    private func drainPendingDeltas(forPartID partID: String) {
        guard let buffered = pendingDeltas.removeValue(forKey: partID) else { return }
        for delta in buffered {
            applyDelta(delta)
        }
    }
}

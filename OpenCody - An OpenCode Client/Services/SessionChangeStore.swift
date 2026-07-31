import Foundation

// MARK: - SessionChangeStore

/// Caches per-session change totals (files, additions, deletions) for list rows.
///
/// ## Why a cache is needed
///
/// `Session.summary` cannot supply these numbers: the server writes it as a
/// hardcoded `{0, 0, 0}` and never updates it (opencode 1.18.9 — there is exactly
/// one `setSummary` call site and it always passes zeros). The real per-turn diffs
/// live on `UserMessage.summary.diffs`, so obtaining totals means fetching a
/// session's whole message list — roughly 30–50 KB per session.
///
/// That is far too expensive to do eagerly for a list, so totals are loaded only
/// for rows that actually appear on screen, then cached. Rows render immediately
/// and fill in the count when it arrives; nothing blocks the list.
///
/// The cache is keyed by server **and** session, and records the session's
/// `time.updated`, so a session that changes is recomputed rather than showing a
/// stale count.
@Observable
final class SessionChangeStore {
    static let shared = SessionChangeStore()

    /// Aggregate change counts for one session.
    struct Totals: Sendable, Equatable {
        let files: Int
        let additions: Int
        let deletions: Int

        static let none = Totals(files: 0, additions: 0, deletions: 0)

        var isEmpty: Bool { files == 0 }
    }

    private struct Key: Hashable {
        let serverID: UUID
        let sessionID: String
    }

    private struct Entry {
        /// `session.time.updated` this total was computed from.
        let updatedAt: Double
        let totals: Totals
    }

    private var cache: [Key: Entry] = [:]

    @ObservationIgnored
    private var inFlight: Set<Key> = []

    /// Bounds concurrent message fetches so scrolling a long list cannot open
    /// dozens of simultaneous multi-tens-of-KB requests.
    @ObservationIgnored
    private let gate = ConcurrencyGate(limit: 3)

    private init() {}

    // MARK: - Reading

    /// Cached totals for a session, or `nil` when not yet computed.
    ///
    /// Returns `nil` — rather than zeros — for an unknown session so callers can
    /// distinguish "not loaded" from "loaded, no changes".
    func totals(for session: Session, serverID: UUID?) -> Totals? {
        guard let serverID else { return nil }
        let key = Key(serverID: serverID, sessionID: session.id)
        guard let entry = cache[key], entry.updatedAt == session.time.updated else { return nil }
        return entry.totals
    }

    // MARK: - Loading

    /// Compute and cache totals for a session, if not already cached.
    ///
    /// Safe to call repeatedly — a cached, current entry short-circuits and a
    /// request already in flight is not duplicated. Intended to be driven from a
    /// row's `.task`, so it runs when the row becomes visible and is cancelled
    /// when it scrolls away.
    func load(session: Session, serverID: UUID?, client: APIClient) async {
        guard let serverID else { return }
        let key = Key(serverID: serverID, sessionID: session.id)

        // Already current, or someone else is fetching it.
        if let entry = cache[key], entry.updatedAt == session.time.updated { return }
        if inFlight.contains(key) { return }

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        await gate.acquire()
        defer { Task { await gate.release() } }

        // The row may have scrolled away while queued behind the gate.
        if Task.isCancelled { return }

        let api = MessageAPI(client: client, directory: session.directory)
        guard let responses = try? await api.list(sessionID: session.id) else { return }
        if Task.isCancelled { return }

        let changeSet = SessionChangeSet(messages: responses.map { $0.toModel() })
        cache[key] = Entry(
            updatedAt: session.time.updated,
            totals: Totals(
                files: changeSet.fileCount,
                additions: changeSet.additions,
                deletions: changeSet.deletions
            )
        )
    }

    /// Drop everything — e.g. on sign-out.
    func clear() {
        cache.removeAll()
    }
}

// MARK: - ConcurrencyGate

/// A counting semaphore limiting how many tasks run at once.
private actor ConcurrencyGate {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            // Hand the slot straight to the next waiter; `active` is unchanged.
            waiters.removeFirst().resume()
        }
    }
}

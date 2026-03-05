//
//  NotificationStore.swift
//  OpenCody - An OpenCode Client
//

import Foundation

// MARK: - NotificationType

/// Distinguishes notification categories for filtering and display.
enum NotificationType: String, Sendable {
    case turnComplete
    case error
    case permission
    case question
}

// MARK: - NotificationEntry

/// A single notification record persisted in the in-app store.
struct NotificationEntry: Identifiable, Sendable {
    let id: UUID
    let type: NotificationType
    let sessionID: String
    let title: String
    let body: String
    let timestamp: Date
    var viewed: Bool

    init(
        id: UUID = UUID(),
        type: NotificationType,
        sessionID: String,
        title: String,
        body: String,
        timestamp: Date = Date(),
        viewed: Bool = false
    ) {
        self.id = id
        self.type = type
        self.sessionID = sessionID
        self.title = title
        self.body = body
        self.timestamp = timestamp
        self.viewed = viewed
    }
}

// MARK: - NotificationStore

/// In-memory store for notification entries.
///
/// Provides unseen counts for badge indicators and methods to mark
/// entries as viewed when the user opens a session.
///
/// Runs on `MainActor` (project default) — safe for SwiftUI observation.
@Observable
final class NotificationStore {

    // MARK: - State

    /// All notification entries, newest first.
    private(set) var entries: [NotificationEntry] = []

    /// Number of unseen entries — drives badge indicators in the UI.
    var unseenCount: Int {
        entries.count(where: { !$0.viewed })
    }

    // MARK: - Capacity

    /// Maximum number of entries kept in memory. Oldest entries are pruned.
    private let maxEntries = 100

    // MARK: - Public API

    /// Add a new notification entry. Newest entries are prepended.
    func add(_ entry: NotificationEntry) {
        entries.insert(entry, at: 0)
        pruneIfNeeded()
    }

    /// Mark all entries for a given session as viewed.
    /// Called when the user navigates into a session.
    func markViewed(sessionID: String) {
        for i in entries.indices where entries[i].sessionID == sessionID && !entries[i].viewed {
            entries[i].viewed = true
        }
    }

    /// Mark all entries as viewed.
    func markAllViewed() {
        for i in entries.indices where !entries[i].viewed {
            entries[i].viewed = true
        }
    }

    /// Remove all entries.
    func clearAll() {
        entries.removeAll()
    }

    // MARK: - Private

    private func pruneIfNeeded() {
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }
}

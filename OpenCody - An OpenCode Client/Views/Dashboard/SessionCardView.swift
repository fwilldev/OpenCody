//
//  SessionCardView.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import SwiftUI

// MARK: - SessionCardView

/// A glass-morphism card displaying session summary information.
struct SessionCardView: View {
    let session: Session
    let status: SessionStatus?
    /// Connection used to lazily compute change totals. When `nil` the card simply
    /// omits them — used by previews and any caller without a live server.
    let connectionManager: ConnectionManager?

    private let changeStore = SessionChangeStore.shared

    init(
        session: Session,
        status: SessionStatus?,
        connectionManager: ConnectionManager? = nil
    ) {
        self.session = session
        self.status = status
        self.connectionManager = connectionManager
    }

    /// Change totals for this session: the server's summary when it is real,
    /// otherwise the lazily computed ones.
    private var changeTotals: SessionChangeStore.Totals? {
        // Prefer the server's own numbers if a future version starts populating them.
        if let summary = session.summary, summary.hasMeaningfulTotals {
            return SessionChangeStore.Totals(
                files: summary.files,
                additions: summary.additions,
                deletions: summary.deletions
            )
        }
        return changeStore.totals(for: session, serverID: connectionManager?.activeServerID)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Top row: title + status badge
            HStack {
                Text(session.title.isEmpty ? "Untitled Session" : session.title)
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.Colors.cloud)
                    .lineLimit(1)

                Spacer()

                if isSessionRunning {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.Colors.cyberBlue)
                }

                StatusBadge(
                    status: connectionStatusFromSession,
                    showLabel: true
                )
            }

            // Middle: directory path
            Text(session.directory)
                .font(Theme.Fonts.codeCaption)
                .foregroundStyle(Theme.Colors.silver)
                .lineLimit(1)
                .truncationMode(.middle)

            // Bottom row: summary + relative time
            HStack {
                // Change totals.
                //
                // `session.summary` cannot be used directly: the server writes it as
                // a hardcoded {0, 0, 0} and never updates it, so an all-zero summary
                // means "not computed", not "no changes". Rendering it would claim
                // "0 files · +0 -0" for a session that did change files. Real totals
                // are computed lazily from the message list once this card appears —
                // see `SessionChangeStore`.
                if let totals = changeTotals, !totals.isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.smoke)
                        Text("\(totals.files) file\(totals.files == 1 ? "" : "s")")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.smoke)

                        Text("·")
                            .foregroundStyle(Theme.Colors.smoke)

                        Text("+\(totals.additions)")
                            .font(Theme.Fonts.codeCaption)
                            .foregroundStyle(Theme.Colors.neonGreen.opacity(0.8))
                        Text("-\(totals.deletions)")
                            .font(Theme.Fonts.codeCaption)
                            .foregroundStyle(Theme.Colors.hotPink.opacity(0.8))
                    }
                    .transition(.opacity)
                } else {
                    Text("No changes yet")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.smoke)
                }

                Spacer()

                // Relative time
                Text(relativeTime)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.smoke)
            }
        }
        .padding(Theme.Spacing.md)
        .glassCard()
        .animation(.easeInOut(duration: 0.2), value: changeTotals)
        // Compute change totals only once this card is actually on screen, and
        // re-run when the session changes. SwiftUI cancels the task when the row
        // scrolls away, which releases the store's concurrency slot.
        .task(id: session.time.updated) {
            guard let connectionManager, let client = connectionManager.activeAPIClient else { return }
            await changeStore.load(
                session: session,
                serverID: connectionManager.activeServerID,
                client: client
            )
        }
    }

    // MARK: - Computed

    /// Convert SessionStatus to ConnectionStatus for the badge.
    private var connectionStatusFromSession: ConnectionStatus {
        guard let status else { return .idle }
        switch status {
        case .idle:
            return .idle
        case .busy:
            return .active
        case .retry:
            return .connecting
        }
    }

    private var isSessionRunning: Bool {
        guard let status else { return false }
        switch status {
        case .idle:
            return false
        case .busy, .retry:
            return true
        }
    }


    /// Format the session's last update time as a relative string.
    private var relativeTime: String {
        // Guard against millisecond timestamps (values > year 3000 in seconds)
        let raw = session.time.updated
        let seconds = raw > 1_000_000_000_000 ? raw / 1000 : raw
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

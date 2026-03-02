//
//  ProjectSessionsView.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 26.02.26.
//

import SwiftUI

// MARK: - ProjectSessionsView

/// Displays the list of sessions for a specific project, with navigation to chat.
struct ProjectSessionsView: View {
    let projectName: String
    let projectPath: String?
    let sessions: [Session]
    let statusMap: [String: SessionStatus]
    let viewModel: DashboardViewModel
    let connectionManager: ConnectionManager
    @State private var showCreateSheet: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.deepBlack
                .ignoresSafeArea()

            if sessions.isEmpty {
                EmptyStateView(
                    systemImage: "rectangle.stack",
                    title: "No Sessions",
                    message: "This project has no sessions yet."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(sessions) { session in
                            NavigationLink(destination: ChatView(session: session, connectionManager: connectionManager)) {
                                SessionCardView(
                                    session: session,
                                    status: statusMap[session.id]
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task {
                                        try? await viewModel.deleteSession(id: session.id)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
        }
        .navigationTitle(projectName)
.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.Colors.cyberBlue)
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateSessionSheet(
                viewModel: viewModel,
                connectionManager: connectionManager,
                preselectedPath: projectPath
            )
            .presentationDetents([.large])
        }
    }
}

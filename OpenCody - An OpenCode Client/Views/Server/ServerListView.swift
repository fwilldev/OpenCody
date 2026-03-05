//
//  ServerListView.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import SwiftUI
import SwiftUI

// MARK: - ServerListView

struct ServerListView: View {
    @EnvironmentObject private var serverStore: ServerStoreModel

    let connectionManager: ConnectionManager

    @State private var showAddServer: Bool = false
    @State private var selectedServer: ServerConnection?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if serverStore.servers.isEmpty {
                emptyState
            } else {
                serverList
            }
        }
        .background(Theme.Colors.deepBlack)
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddServer = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.Colors.cyberBlue)
                }
            }
        }
        .sheet(isPresented: $showAddServer) {
            AddServerView(connectionManager: connectionManager)
                .environmentObject(serverStore)
        }
        .sheet(item: $selectedServer) { server in
            EditServerView(server: server, connectionManager: connectionManager)
                .environmentObject(serverStore)
        }
        .onAppear {
            serverStore.load()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.slate)
                .shadow(color: Theme.Colors.cyberBlue.opacity(0.15), radius: 12)

            VStack(spacing: Theme.Spacing.sm) {
                Text("No Servers")
                    .font(Theme.Fonts.title2)
                    .foregroundStyle(Theme.Colors.cloud)

                Text("Add a server to connect to your OpenCode instance.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.silver)
                    .multilineTextAlignment(.center)
            }

            Button {
                showAddServer = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "plus")
                    Text("Add Server")
                }
            }
            .primaryButton()

            Spacer()
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Server List

    private var serverList: some View {
        List {
            ForEach(serverStore.servers) { server in
                serverRow(server)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: Theme.Spacing.xs,
                        leading: Theme.Spacing.md,
                        bottom: Theme.Spacing.xs,
                        trailing: Theme.Spacing.md
                    ))
            }
            .onDelete { indexSet in
                for index in indexSet {
                    deleteServer(serverStore.servers[index])
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Server Row

    private func serverRow(_ server: ServerConnection) -> some View {
        Button {
            selectedServer = server
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                // Server icon
                Image(systemName: "server.rack")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Colors.cyberBlue)
                    .frame(width: 32, height: 32)

                // Server info
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(server.name)
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.cloud)
                        .lineLimit(1)

                    Text(server.baseURL)
                        .font(Theme.Fonts.codeCaption)
                        .foregroundStyle(Theme.Colors.silver)
                        .lineLimit(1)
                }

                Spacer()

                // Status badge
                StatusBadge(
                    status: connectionStatus(for: server),
                    showLabel: false
                )

                // Chevron
                Image(systemName: "chevron.right")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.smoke)
            }
            .padding(Theme.Spacing.md)
            .glassCard()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                connectToServer(server)
            } label: {
                Label("Connect", systemImage: "bolt.horizontal")
            }

            Button {
                selectedServer = server
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                deleteServer(server)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func connectionStatus(for server: ServerConnection) -> ConnectionStatus {
        connectionManager.connectionState(for: server.id).displayStatus
    }

    // MARK: - Actions

    private func connectToServer(_ server: ServerConnection) {
        let password = (try? KeychainService.retrieve(for: server.keychainIdentifier)) ?? ""
        Task {
            try? await connectionManager.connect(server: server, password: password)
        }
    }

    private func deleteServer(_ server: ServerConnection) {
        connectionManager.disconnect(serverID: server.id)
        try? KeychainService.delete(for: server.keychainIdentifier)
        serverStore.delete(id: server.id)
    }
}

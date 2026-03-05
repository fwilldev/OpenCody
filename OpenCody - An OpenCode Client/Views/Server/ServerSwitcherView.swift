//
//  ServerSwitcherView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Compact nav bar button for switching between connected OpenCode servers.
///
/// Shows the active server name with a colored status dot. Tapping reveals
/// a menu listing all configured servers so the user can switch.
struct ServerSwitcherView: View {
    let servers: [ServerConnection]
    let connectionManager: ConnectionManager

    // MARK: - Computed Properties

    private var activeServer: ServerConnection? {
        guard let id = connectionManager.activeServerID else { return nil }
        return servers.first { $0.id == id }
    }

    private var activeServerName: String {
        activeServer?.name ?? "No Server"
    }

    private var activeStatus: ConnectionStatus {
        guard let id = connectionManager.activeServerID else { return .idle }
        return connectionManager.connectionState(for: id).displayStatus
    }

    // MARK: - Body

    var body: some View {
        Menu {
            serverMenuItems
        } label: {
            menuLabel
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var serverMenuItems: some View {
        if servers.isEmpty {
            Text("No Servers Configured")
                .foregroundStyle(Theme.Colors.silver)
        } else {
            ForEach(servers) { server in
                Button {
                    connectionManager.connectAndActivate(server: server)
                } label: {
                    serverMenuRow(for: server)
                }
            }
        }
    }

    @ViewBuilder
    private func serverMenuRow(for server: ServerConnection) -> some View {
        let state = connectionManager.connectionState(for: server.id)
        let status = state.displayStatus
        let isActive = server.id == connectionManager.activeServerID

        Label {
            HStack {
                Text(server.name)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Colors.cyberBlue)
                }
            }
        } icon: {
            Image(systemName: "server.rack")
                .foregroundStyle(status.color)
        }
    }

    private var menuLabel: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(activeStatus.color)
                .frame(width: 6, height: 6)
                .shadow(color: activeStatus.color.opacity(0.6), radius: 3)

            Text(activeServerName)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.cloud)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140, alignment: .leading)

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.Colors.silver)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

}

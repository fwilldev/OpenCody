//
//  CreateSessionSheet.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import SwiftUI

// MARK: - CreateSessionSheet

/// Sheet for creating a new coding session with folder, agent, model, and provider selection.
struct CreateSessionSheet: View {
    let viewModel: DashboardViewModel
    let connectionManager: ConnectionManager
    let preselectedPath: String?
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var selectedPath: String
    @State private var agents: [Agent] = []
    @State private var selectedAgent: Agent?

    @State private var isCreating: Bool = false
    @State private var loadError: String?
    @State private var showFolderPicker: Bool = false

    // MARK: - Body

    init(
        viewModel: DashboardViewModel,
        connectionManager: ConnectionManager,
        preselectedPath: String? = nil
    ) {
        self.viewModel = viewModel
        self.connectionManager = connectionManager
        self.preselectedPath = preselectedPath
        self._selectedPath = State(initialValue: preselectedPath ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Error banner
                    if let loadError {
                        ErrorBanner(
                            error: .network(loadError),
                            onDismiss: { self.loadError = nil }
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                    }

                    // Folder section
                    if preselectedPath == nil {
                        folderSection
                    } else {
                        fixedFolderSection
                    }

                    // Agent section
                    agentSection

                }
                .padding(.vertical, Theme.Spacing.md)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.deepBlack)
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.silver)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createSession()
                    } label: {
                        if isCreating {
                            ProgressView()
                                .tint(Theme.Colors.cyberBlue)
                        } else {
                            Text("Create")
                        }
                    }
                    .foregroundStyle(selectedPath.isEmpty ? Theme.Colors.smoke : Theme.Colors.cyberBlue)
                    .disabled(selectedPath.isEmpty || isCreating)
                }
            }
            .task {
                await loadFormData()
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            if let client = connectionManager.activeAPIClient {
                NavigationStack {
                    FolderPickerView(apiClient: client) { path in
                        selectedPath = path
                        showFolderPicker = false
                    }
                    .navigationTitle("Select Folder")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showFolderPicker = false }
                        }
                    }
                }
            }
        }
        .presentationBackground(Theme.Colors.carbon)
    }

    // MARK: - Sections

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Project Folder")

            Button {
                showFolderPicker = true
            } label: {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(Theme.Colors.cyberBlue)
                    Text(selectedPath.isEmpty ? "Select a folder..." : selectedPath)
                        .foregroundStyle(selectedPath.isEmpty ? Theme.Colors.smoke : Theme.Colors.cloud)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.smoke)
                }
                .padding(Theme.Spacing.md)
                .glassCard()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var fixedFolderSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Project Folder")

            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(Theme.Colors.cyberBlue)
                Text(selectedPath)
                    .foregroundStyle(Theme.Colors.cloud)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .glassCard()
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Agent")

            if agents.isEmpty {
                Text("Loading agents...")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.smoke)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            } else {
                ForEach(agents.filter { !($0.hidden ?? false) }) { agent in
                    Button {
                        selectedAgent = agent
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(agent.name)
                                    .font(Theme.Fonts.body)
                                    .foregroundStyle(Theme.Colors.cloud)
                                if let description = agent.description {
                                    Text(description)
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.Colors.silver)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if selectedAgent?.id == agent.id {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(Theme.Colors.neonGreen)
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .glassCard()
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card)
                                .stroke(
                                    selectedAgent?.id == agent.id
                                        ? Theme.Colors.neonGreen.opacity(0.4)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }


    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.Fonts.codeCaption)
            .foregroundStyle(Theme.Colors.silver)
            .tracking(1.2)
    }


    // MARK: - Data Loading

    private func loadFormData() async {
        guard let client = connectionManager.activeAPIClient else {
            loadError = "No active server connection"
            return
        }

        do {
            let agentAPI = AgentAPI(client: client)
            agents = try await agentAPI.list()
        } catch {
            loadError = "Failed to load agents: \(error.localizedDescription)"
        }

    }

    // MARK: - Actions

    private func createSession() {
        guard !selectedPath.isEmpty else { return }
        isCreating = true

        Task {
            do {
                _ = try await viewModel.createSession(
                    path: selectedPath,
                    agentName: selectedAgent?.name,
                    modelID: nil,
                    providerID: nil
                )
                dismiss()
            } catch {
                loadError = "Failed to create session: \(error.localizedDescription)"
                isCreating = false
            }
        }
    }
}

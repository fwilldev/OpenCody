//
//  CreateSessionSheet.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import SwiftUI

// MARK: - CreateSessionSheet

/// Sheet for creating a new coding session with folder selection.
/// The default agent and model are applied automatically when the session is opened.
struct CreateSessionSheet: View {
    let viewModel: DashboardViewModel
    let connectionManager: ConnectionManager
    let preselectedPath: String?
    var onSessionCreated: ((Session) -> Void)?
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var selectedPath: String

    @State private var isCreating: Bool = false
    @State private var loadError: String?
    @State private var showFolderPicker: Bool = false

    // MARK: - Body

    init(
        viewModel: DashboardViewModel,
        connectionManager: ConnectionManager,
        preselectedPath: String? = nil,
        onSessionCreated: ((Session) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.connectionManager = connectionManager
        self.preselectedPath = preselectedPath
        self.onSessionCreated = onSessionCreated
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



    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.Fonts.codeCaption)
            .foregroundStyle(Theme.Colors.silver)
            .tracking(1.2)
    }


    // MARK: - Actions

    private func createSession() {
        guard !selectedPath.isEmpty else { return }
        isCreating = true

        Task {
            do {
                let session = try await viewModel.createSession(path: selectedPath)
                onSessionCreated?(session)
                dismiss()
            } catch {
                loadError = "Failed to create session: \(error.localizedDescription)"
                isCreating = false
            }
        }
    }
}

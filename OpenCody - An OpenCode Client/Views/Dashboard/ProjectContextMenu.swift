import SwiftUI

// MARK: - ProjectContextMenu

/// Context menu items for a project row: rename, reset name, close/reopen.
struct ProjectContextMenu: View {
    let group: ProjectGroup
    let viewModel: DashboardViewModel
    let onRename: () -> Void

    var body: some View {
        Button("Rename Project", systemImage: "pencil", action: onRename)

        if group.hasCustomName {
            Button("Reset Name", systemImage: "arrow.uturn.backward") {
                Task { try? await viewModel.renameProject(directory: group.directory, to: "") }
            }
        }

        Divider()

        if viewModel.isProjectClosed(directory: group.directory) {
            Button("Reopen Project", systemImage: "eye") {
                withAnimation { viewModel.reopenProject(directory: group.directory) }
            }
        } else {
            Button("Close Project", systemImage: "eye.slash") {
                withAnimation { viewModel.closeProject(directory: group.directory) }
            }
        }
    }
}

extension View {
    /// The rename alert for projects, saving through `viewModel`.
    func projectRenameAlert(_ group: Binding<ProjectGroup?>, viewModel: DashboardViewModel) -> some View {
        renameAlert(
            "Rename Project",
            item: group,
            currentName: { $0.name },
            message: { $0.directory },
            onSave: { group, name in
                Task {
                    do {
                        try await viewModel.renameProject(directory: group.directory, to: name)
                    } catch {
                        viewModel.error = "Couldn't rename the project: \(error.localizedDescription)"
                    }
                }
            }
        )
    }
}

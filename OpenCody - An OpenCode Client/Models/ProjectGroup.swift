import Foundation

// MARK: - ProjectGroup

/// Sessions sharing one project directory, as listed on the dashboard and iPad sidebar.
struct ProjectGroup: Identifiable {
    let directory: String
    /// Custom name if one is set, else the folder name.
    let name: String
    let hasCustomName: Bool
    /// Newest first.
    let sessions: [Session]

    var id: String { directory }
}

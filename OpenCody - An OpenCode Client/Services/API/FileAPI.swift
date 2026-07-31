import Foundation

// MARK: - FileAPI

/// Typed wrapper for file, search, and project endpoints.
///
/// Endpoints:
/// - `GET   /file`                          → list directory contents
/// - `GET   /file/content`                  → read file content
/// - `GET   /file/status`                   → git status of files
/// - `GET   /find`                          → ripgrep text search
/// - `GET   /find/file`                     → fuzzy file/directory search
/// - `GET   /find/symbol`                   → LSP workspace symbol search
/// - `GET   /path`                          → resolved paths for the instance
/// - `GET   /project`                       → list all known projects
/// - `GET   /project/current`               → the active project
/// - `PATCH /project/{projectID}`           → rename / re-icon a project
/// - `GET   /project/{projectID}/directories` → known directories for a project
/// - `POST  /project/git/init`              → create a git repo for the project
struct FileAPI: Sendable {
    let client: APIClient

    /// Filter for `findFiles` — whether to match files, directories, or both.
    enum FindKind: String, Sendable {
        case file
        case directory
    }

    // MARK: - Request Bodies

    private struct ProjectUpdateBody: Encodable {
        let name: String?
        let icon: ProjectIcon?
        let commands: ProjectCommands?
    }

    // MARK: - Files

    /// List files and directories at a path.
    ///
    /// - Parameter path: Project-relative path (e.g. `"src"`, `"src/views"`).
    func list(path: String, directory: String? = nil) async throws -> [FileNode] {
        var items = [URLQueryItem(name: "path", value: path)]
        if let directory {
            items.append(URLQueryItem(name: "directory", value: directory))
        }
        let data = try await client.requestData(.get("/file", queryItems: items))
        return try JSONDecoder().decode([FileNode].self, from: data)
    }

    /// Read the content of a file.
    ///
    /// - Parameter path: Project-relative path to the file (e.g. `"src/index.ts"`).
    func content(path: String, directory: String? = nil) async throws -> FileContent {
        var items = [URLQueryItem(name: "path", value: path)]
        if let directory {
            items.append(URLQueryItem(name: "directory", value: directory))
        }
        let data = try await client.requestData(.get("/file/content", queryItems: items))
        return try JSONDecoder().decode(FileContent.self, from: data)
    }

    /// Get git status of all changed files, with add/remove counts.
    func status(directory: String? = nil) async throws -> [ChangedFile] {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/file/status", queryItems: items))
        return try JSONDecoder().decode([ChangedFile].self, from: data)
    }

    // MARK: - Search

    /// Search for files or directories by name or glob pattern.
    ///
    /// - Parameters:
    ///   - query: Search query (file name or glob pattern).
    ///   - kind: Restrict results to files or directories. `nil` returns both.
    ///   - limit: Maximum number of results (server caps this at 200).
    /// - Returns: Project-relative paths.
    func findFiles(
        query: String,
        kind: FindKind? = nil,
        directory: String? = nil,
        limit: Int = 20
    ) async throws -> [String] {
        var items = [URLQueryItem(name: "query", value: query)]
        if let kind { items.append(URLQueryItem(name: "type", value: kind.rawValue)) }
        if let directory { items.append(URLQueryItem(name: "directory", value: directory)) }
        items.append(URLQueryItem(name: "limit", value: String(min(limit, 200))))
        let data = try await client.requestData(.get("/find/file", queryItems: items))
        return try JSONDecoder().decode([String].self, from: data)
    }

    /// Search file contents with ripgrep.
    ///
    /// - Parameter pattern: A regular expression, as accepted by ripgrep.
    func findText(pattern: String, directory: String? = nil) async throws -> [TextSearchMatch] {
        var items = [URLQueryItem(name: "pattern", value: pattern)]
        if let directory { items.append(URLQueryItem(name: "directory", value: directory)) }
        let data = try await client.requestData(.get("/find", queryItems: items))
        return try JSONDecoder().decode([TextSearchMatch].self, from: data)
    }

    /// Search workspace symbols (functions, classes, variables) via LSP.
    ///
    /// Returns an empty array when no language server is running for the project.
    func findSymbols(query: String, directory: String? = nil) async throws -> [SymbolInfo] {
        var items = [URLQueryItem(name: "query", value: query)]
        if let directory { items.append(URLQueryItem(name: "directory", value: directory)) }
        let data = try await client.requestData(.get("/find/symbol", queryItems: items))
        return try JSONDecoder().decode([SymbolInfo].self, from: data)
    }

    // MARK: - Paths & Projects

    /// Get resolved paths (home, config, state, worktree, directory) for the instance.
    func path(directory: String? = nil) async throws -> PathInfo {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/path", queryItems: items))
        return try JSONDecoder().decode(PathInfo.self, from: data)
    }

    /// List all projects that have been opened with opencode.
    func listProjects() async throws -> [Project] {
        let data = try await client.requestData(.get("/project"))
        return try JSONDecoder().decode([Project].self, from: data)
    }

    /// Get the project the server currently considers active.
    func currentProject(directory: String? = nil) async throws -> Project {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/project/current", queryItems: items))
        return try JSONDecoder().decode(Project.self, from: data)
    }

    /// List the local absolute directories known for a project.
    ///
    /// A project can span several checkouts (worktrees, copies); this returns all
    /// of them so the client can offer a directory picker.
    func projectDirectories(projectID: String) async throws -> [String] {
        let data = try await client.requestData(.get("/project/\(projectID)/directories"))
        return try JSONDecoder().decode([String].self, from: data)
    }

    /// Update project display properties.
    @discardableResult
    func updateProject(
        projectID: String,
        name: String? = nil,
        icon: ProjectIcon? = nil,
        commands: ProjectCommands? = nil
    ) async throws -> Project {
        let body = ProjectUpdateBody(name: name, icon: icon, commands: commands)
        let data = try await client.requestData(.patch("/project/\(projectID)", body: body))
        return try JSONDecoder().decode(Project.self, from: data)
    }

    /// Initialize a git repository for the current project.
    @discardableResult
    func initGit(directory: String? = nil) async throws -> Project {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(
            APIEndpoint(path: "/project/git/init", method: .POST, queryItems: items)
        )
        return try JSONDecoder().decode(Project.self, from: data)
    }
}

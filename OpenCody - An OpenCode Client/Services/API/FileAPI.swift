import Foundation

// MARK: - FileAPI

/// Typed wrapper for file/project-related REST endpoints.
///
/// Endpoints (per opencode server API):
/// - `GET /file`              → list directory contents
/// - `GET /file/content`      → read file content
/// - `GET /file/status`       → git status of files
/// - `GET /project`           → list all projects
struct FileAPI: Sendable {
    let client: APIClient

    // MARK: - Endpoints

    /// List files and directories at a path.
    ///
    /// - Parameter path: Relative path within the project (e.g. `"src"`, `"src/views"`).
    /// - Returns: Array of `FileNode` entries (files and directories).
    func list(path: String, directory: String? = nil) async throws -> [FileNode] {
        var items = [URLQueryItem(name: "path", value: path)]
        if let directory {
            items.append(URLQueryItem(name: "directory", value: directory))
        }
        let data = try await client.requestData(
            .get("/file", queryItems: items)
        )
        return try JSONDecoder().decode([FileNode].self, from: data)
    }

    /// Read the content of a file.
    ///
    /// - Parameter path: Relative path to the file (e.g. `"src/index.ts"`).
    /// - Returns: `FileContent` with text/binary content.
    func content(path: String, directory: String? = nil) async throws -> FileContent {
        var items = [URLQueryItem(name: "path", value: path)]
        if let directory {
            items.append(URLQueryItem(name: "directory", value: directory))
        }
        let data = try await client.requestData(
            .get(
                "/file/content",
                queryItems: items
            )
        )
        return try JSONDecoder().decode(FileContent.self, from: data)
    }

    /// Get git status of all changed files.
    ///
    /// - Returns: Array of `ChangedFile` entries with add/remove counts and status.
    func status(directory: String? = nil) async throws -> [ChangedFile] {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/file/status", queryItems: items))
        return try JSONDecoder().decode([ChangedFile].self, from: data)
    }

    /// List all known projects.
    func listProjects() async throws -> [Project] {
        let data = try await client.requestData(.get("/project"))
        return try JSONDecoder().decode([Project].self, from: data)
    }

    /// Get path information for the current working directory.
    func path() async throws -> PathInfo {
        let data = try await client.requestData(.get("/path"))
        return try JSONDecoder().decode(PathInfo.self, from: data)
    }

    /// Search for files by name or pattern.
    ///
    /// - Parameters:
    ///   - query: Search query (file name or glob pattern).
    ///   - directory: Optional project directory scope.
    ///   - limit: Maximum number of results (1–200).
    /// - Returns: Array of relative file path strings.
    func findFiles(query: String, directory: String? = nil, limit: Int = 20) async throws -> [String] {
        var items = [URLQueryItem(name: "query", value: query)]
        if let directory {
            items.append(URLQueryItem(name: "directory", value: directory))
        }
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        let data = try await client.requestData(
            .get("/find/file", queryItems: items)
        )
        return try JSONDecoder().decode([String].self, from: data)
    }

}

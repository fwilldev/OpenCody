import Foundation

// MARK: - FileAPI

/// Typed wrapper for all file/project-related REST endpoints.
///
/// Endpoints:
/// - `GET /file/read`              → read file content
/// - `GET /file/find`              → find files (dirs=false) or directories (dirs=true)
/// - `GET /file/search`            → search file contents (grep)
/// - `GET /file/changed`           → list changed files
/// - `GET /file/symbols`           → search for symbols
/// - `GET /file/vcs`               → get VCS info
/// - `GET /file/path`              → get path info
/// - `GET /project`                → list all projects
struct FileAPI: Sendable {
    let client: APIClient

    // MARK: - Endpoints

    /// List files and directories at a path.
    func list(path: String, directory: String? = nil) async throws -> [FileNode] {
        var items = [URLQueryItem(name: "path", value: path)]
        if let directory {
            items.append(URLQueryItem(name: "directory", value: directory))
        }
        let data = try await client.requestData(.get("/file", queryItems: items))
        return try JSONDecoder().decode([FileNode].self, from: data)
    }

    /// Read the content of a file.
    func read(path: String) async throws -> FileContent {
        let data = try await client.requestData(
            .get("/file/read", queryItems: [URLQueryItem(name: "path", value: path)])
        )
        return try JSONDecoder().decode(FileContent.self, from: data)
    }

    /// Find files matching a pattern.
    func findFiles(pattern: String? = nil) async throws -> [FileNode] {
        var items = [URLQueryItem(name: "dirs", value: "false")]
        if let pattern { items.append(URLQueryItem(name: "pattern", value: pattern)) }
        let data = try await client.requestData(.get("/file/find", queryItems: items))
        return try JSONDecoder().decode([FileNode].self, from: data)
    }

    /// Find directories matching a pattern.
    func findDirectories(pattern: String? = nil) async throws -> [FileNode] {
        var items = [URLQueryItem(name: "dirs", value: "true")]
        if let pattern { items.append(URLQueryItem(name: "pattern", value: pattern)) }
        let data = try await client.requestData(.get("/file/find", queryItems: items))
        return try JSONDecoder().decode([FileNode].self, from: data)
    }

    /// Search file contents (grep-like).
    func search(query: String) async throws -> [FileNode] {
        let data = try await client.requestData(
            .get("/file/search", queryItems: [URLQueryItem(name: "query", value: query)])
        )
        return try JSONDecoder().decode([FileNode].self, from: data)
    }

    /// List changed files (uncommitted changes).
    func changed() async throws -> [ChangedFile] {
        let data = try await client.requestData(.get("/file/changed"))
        return try JSONDecoder().decode([ChangedFile].self, from: data)
    }

    /// Search for code symbols.
    func symbols(query: String) async throws -> [SymbolInfo] {
        let data = try await client.requestData(
            .get("/file/symbols", queryItems: [URLQueryItem(name: "query", value: query)])
        )
        return try JSONDecoder().decode([SymbolInfo].self, from: data)
    }

    /// Get VCS (version control) information.
    func vcs() async throws -> VcsInfo {
        let data = try await client.requestData(.get("/file/vcs"))
        return try JSONDecoder().decode(VcsInfo.self, from: data)
    }

    /// Get path information for the current working directory.
    func path() async throws -> PathInfo {
        let data = try await client.requestData(.get("/path"))
        return try JSONDecoder().decode(PathInfo.self, from: data)
    }

    /// List all known projects.
    func listProjects() async throws -> [Project] {
        let data = try await client.requestData(.get("/project"))
        return try JSONDecoder().decode([Project].self, from: data)
    }
}

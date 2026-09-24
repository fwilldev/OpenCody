import Foundation

// MARK: - VcsAPI

/// Typed wrapper for version-control endpoints.
///
/// These replace the older `/file/status`-only view of the working tree with
/// branch information and real unified-diff patches.
///
/// Endpoints:
/// - `GET  /vcs`          → branch + default branch
/// - `GET  /vcs/status`   → changed files without patches (cheap)
/// - `GET  /vcs/diff`     → changed files with patches
/// - `GET  /vcs/diff/raw` → one raw patch for the whole working tree
/// - `POST /vcs/apply`    → apply a raw patch to the working tree
struct VcsAPI: Sendable {
    let client: APIClient

    /// Scope of a `GET /vcs/diff` request.
    enum DiffMode: String, Sendable {
        /// Uncommitted changes in the working tree.
        case git
        /// All changes on the current branch relative to the default branch.
        case branch
    }

    private struct ApplyBody: Encodable {
        let patch: String
    }

    private struct ApplyResponse: Decodable {
        let applied: Bool
    }

    // MARK: - Info

    /// Get the current branch and the repository's default branch.
    func info(directory: String? = nil) async throws -> VcsInfo {
        if client.apiVersion == .v2 { return try await v2Info(directory: directory) }
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/vcs", queryItems: items))
        return try JSONDecoder().decode(VcsInfo.self, from: data)
    }

    /// List changed files in the working tree, without patch bodies.
    ///
    /// Cheaper than `diff` — use this for a change summary or badge counts.
    func status(directory: String? = nil) async throws -> [FileDiff] {
        if client.apiVersion == .v2 { return try await v2Status(directory: directory) }
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/vcs/status", queryItems: items))
        return try JSONDecoder().decode([FileDiff].self, from: data)
    }

    // MARK: - Diffs

    /// Get per-file diffs with unified-diff patches.
    ///
    /// - Parameters:
    ///   - mode: `.git` for uncommitted changes, `.branch` to compare against the default branch.
    ///   - context: Number of context lines around each hunk.
    func diff(
        mode: DiffMode = .git,
        context: Int? = nil,
        directory: String? = nil
    ) async throws -> [FileDiff] {
        if client.apiVersion == .v2 { return try await v2Diff(mode: mode, context: context, directory: directory) }
        var items = [URLQueryItem(name: "mode", value: mode.rawValue)]
        if let context { items.append(URLQueryItem(name: "context", value: String(context))) }
        if let directory { items.append(URLQueryItem(name: "directory", value: directory)) }
        let data = try await client.requestData(.get("/vcs/diff", queryItems: items))
        return try JSONDecoder().decode([FileDiff].self, from: data)
    }

    /// Get a single raw patch covering all uncommitted changes.
    ///
    /// The response is `text/x-diff`, not JSON.
    func rawDiff(directory: String? = nil) async throws -> String {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("Raw diffs") }
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        return try await client.requestString(.get("/vcs/diff/raw", queryItems: items))
    }

    /// Apply a raw unified-diff patch to the working tree.
    ///
    /// - Returns: `true` when the patch applied cleanly.
    /// - Throws: A validation error when the tree is not a git repo or is dirty.
    @discardableResult
    func apply(patch: String, directory: String? = nil) async throws -> Bool {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("Applying patches") }
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let endpoint = APIEndpoint(
            path: "/vcs/apply",
            method: .POST,
            body: try JSONEncoder().encode(ApplyBody(patch: patch)),
            queryItems: items
        )
        let data = try await client.requestData(endpoint)
        return (try? JSONDecoder().decode(ApplyResponse.self, from: data).applied) ?? true
    }
}

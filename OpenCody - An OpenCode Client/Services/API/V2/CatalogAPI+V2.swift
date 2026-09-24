import Foundation

// MARK: - AgentAPI (OpenCode 2.x)

extension AgentAPI {
    func v2List() async throws -> [Agent] {
        let data = try await client.v2Data(.get("/api/agent"))
        let agents = (data as? [V2Adapter.JSON] ?? []).map(V2Adapter.agent)
        return try V2Adapter.decode([Agent].self, from: agents)
    }
}

// MARK: - CommandAPI (OpenCode 2.x)

extension CommandAPI {
    func v2List(directory: String?) async throws -> [SlashCommand] {
        let data = try await client.v2Data(.get("/api/command", queryItems: APIEndpoint.v2Location(directory)))
        let commands = (data as? [V2Adapter.JSON] ?? []).map(V2Adapter.command)
        return try V2Adapter.decode([SlashCommand].self, from: commands)
    }

    func v2Execute(sessionID: String, command: String, arguments: String) async throws {
        try await client.requestVoid(
            .v2(
                "/api/session/\(sessionID)/command",
                method: .POST,
                json: ["name": command, "text": arguments],
                timeout: 300
            )
        )
    }

    func v2ListSkills(directory: String?) async throws -> [Skill] {
        let data = try await client.v2Data(.get("/api/skill", queryItems: APIEndpoint.v2Location(directory)))
        let skills = (data as? [V2Adapter.JSON] ?? []).map(V2Adapter.skill)
        return try V2Adapter.decode([Skill].self, from: skills)
    }
}

// MARK: - ProviderAPI (OpenCode 2.x)

/// 2.x splits v1's provider list: `/api/provider` lists usable providers, `/api/model`
/// their enabled models, and `/api/integration` the connectable catalog with its
/// auth methods and stored credentials.
extension ProviderAPI {
    private typealias JSON = V2Adapter.JSON

    func v2List(directory: String?) async throws -> ProviderListResponse {
        let location = APIEndpoint.v2Location(directory)
        async let providerData = client.v2Data(.get("/api/provider", queryItems: location))
        async let modelData = client.v2Data(.get("/api/model", queryItems: location))
        async let defaultData = client.v2Data(.get("/api/model/default", queryItems: location))
        async let integrationData = client.v2Data(.get("/api/integration", queryItems: location))

        let providers = try await providerData as? [JSON] ?? []
        let models = (try await modelData as? [JSON] ?? []).filter { $0["enabled"] as? Bool ?? true }
        let defaultModel = (try? await defaultData) as? JSON
        let integrations = (try? await integrationData) as? [JSON] ?? []

        let modelsByProvider = Dictionary(grouping: models) { $0["providerID"] as? String ?? "" }
        var all: [JSON] = providers.compactMap { provider in
            guard let id = provider["id"] as? String else { return nil }
            return V2Adapter.provider(
                id: id,
                name: provider["name"] as? String ?? id,
                package: provider["package"] as? String,
                models: modelsByProvider[id] ?? []
            )
        }

        // Integrations that are not usable yet still belong in the list, so they can
        // be connected from the app.
        let listed = Set(providers.compactMap { $0["id"] as? String })
        let integrated = Set(providers.compactMap { $0["integrationID"] as? String })
        for integration in integrations {
            guard let id = integration["id"] as? String, !listed.contains(id), !integrated.contains(id) else { continue }
            all.append(V2Adapter.provider(id: id, name: integration["name"] as? String ?? id, package: nil, models: []))
        }

        var defaults: [String: String] = [:]
        if let providerID = defaultModel?["providerID"] as? String, let modelID = defaultModel?["id"] as? String {
            defaults[providerID] = modelID
        }
        for (providerID, providerModels) in modelsByProvider where defaults[providerID] == nil {
            if let first = providerModels.first?["id"] as? String { defaults[providerID] = first }
        }

        let response: JSON = [
            "all": all,
            "default": defaults,
            // `/api/provider` lists only providers that can serve requests.
            "connected": Array(listed),
        ]
        return try V2Adapter.decode(ProviderListResponse.self, from: response)
    }

    /// Auth methods per provider, from each provider's integration.
    func v2AllAuthMethods(directory: String?) async throws -> [String: [ProviderAuthMethod]] {
        let location = APIEndpoint.v2Location(directory)
        async let providerData = client.v2Data(.get("/api/provider", queryItems: location))
        async let integrationData = client.v2Data(.get("/api/integration", queryItems: location))
        let providers = (try? await providerData) as? [JSON] ?? []
        let integrations = try await integrationData as? [JSON] ?? []

        var providerIDsByIntegration: [String: [String]] = [:]
        for provider in providers {
            guard let id = provider["id"] as? String else { continue }
            providerIDsByIntegration[provider["integrationID"] as? String ?? id, default: []].append(id)
        }

        var result: [String: [ProviderAuthMethod]] = [:]
        for integration in integrations {
            guard let id = integration["id"] as? String else { continue }
            let methods: [JSON] = (integration["methods"] as? [JSON] ?? []).compactMap { method in
                switch method["type"] as? String {
                case "key":
                    return ["type": "api", "label": method["label"] as? String ?? "API Key"]
                case "oauth":
                    return ["type": "oauth", "label": method["label"] as? String ?? "Sign in"]
                default:
                    return nil
                }
            }
            let decoded = try V2Adapter.decode([ProviderAuthMethod].self, from: methods)
            for providerID in providerIDsByIntegration[id] ?? [id] {
                result[providerID] = decoded
            }
        }
        return result
    }

    /// The integration a provider authenticates through (usually the same ID).
    private func v2IntegrationID(providerID: String) async -> String {
        let provider = try? await client.v2Data(.get("/api/provider/\(APIEndpoint.segment(providerID))")) as? JSON
        return provider?["integrationID"] as? String ?? providerID
    }

    func v2SetApiKey(providerID: String, apiKey: String) async throws {
        let integrationID = await v2IntegrationID(providerID: providerID)
        try await client.requestVoid(
            .v2(
                "/api/integration/\(APIEndpoint.segment(integrationID))/connect/key",
                method: .POST,
                json: ["key": apiKey]
            )
        )
    }

    func v2RemoveCredentials(providerID: String) async throws {
        let integrationID = await v2IntegrationID(providerID: providerID)
        let integration = try await client.v2Data(
            .get("/api/integration/\(APIEndpoint.segment(integrationID))")
        ) as? JSON
        let credentials = (integration?["connections"] as? [JSON] ?? []).filter { ($0["type"] as? String) == "credential" }
        for credential in credentials {
            guard let id = credential["id"] as? String else { continue }
            try await client.requestVoid(.delete("/api/credential/\(APIEndpoint.segment(id))"))
        }
    }
}

// MARK: - ConfigAPI (OpenCode 2.x)

extension ConfigAPI {
    /// The parts of v1 `Config` the app reads, rebuilt from 2.x defaults.
    func v2Get() async throws -> ServerConfig {
        let model = try? await client.v2Data(.get("/api/model/default")) as? V2Adapter.JSON
        var config: V2Adapter.JSON = [:]
        if let providerID = model?["providerID"] as? String, let id = model?["id"] as? String {
            config["model"] = "\(providerID)/\(id)"
        }
        return try V2Adapter.decode(ServerConfig.self, from: config)
    }
}

// MARK: - GlobalAPI (OpenCode 2.x)

extension GlobalAPI {
    func v2Health() async throws -> HealthInfo {
        let info = try await client.v2JSON(.get("/api/info")) as? V2Adapter.JSON
        return try V2Adapter.decode(
            HealthInfo.self,
            from: ["healthy": true, "version": info?["version"] as? String ?? "2"] as V2Adapter.JSON
        )
    }

    /// The MCP servers declared in 2.x configuration, as v1 config.
    ///
    /// `GET /api/config` returns every document in the config chain; later documents
    /// override earlier ones, so they are merged in order.
    func v2Config() async throws -> ServerConfig {
        let entries = try await client.v2JSON(.get("/api/config")) as? [V2Adapter.JSON] ?? []
        var servers: V2Adapter.JSON = [:]
        for entry in entries where (entry["type"] as? String) == "document" {
            let info = entry["info"] as? V2Adapter.JSON
            let declared = (info?["mcp"] as? V2Adapter.JSON)?["servers"] as? V2Adapter.JSON ?? [:]
            for (name, value) in declared {
                if let config = value as? V2Adapter.JSON, let v1 = V2Adapter.mcpConfig(fromV2: config) {
                    servers[name] = v1
                }
            }
        }
        return try V2Adapter.decode(ServerConfig.self, from: ["mcp": servers] as V2Adapter.JSON)
    }

    /// 2.x rebuilds every loaded location instead of disposing a single instance.
    /// Pending permissions and forms are cancelled by it.
    func v2DisposeInstance() async throws {
        try await client.requestVoid(.post("/api/location/reload"))
    }
}

// MARK: - MCPAPI (OpenCode 2.x)

extension MCPAPI {
    func v2List(directory: String?) async throws -> McpStatusMap {
        let data = try await client.v2Data(.get("/api/mcp", queryItems: APIEndpoint.v2Location(directory)))
        var map: V2Adapter.JSON = [:]
        for server in data as? [V2Adapter.JSON] ?? [] {
            guard let name = server["name"] as? String else { continue }
            map[name] = V2Adapter.mcpStatus(server["status"] as? V2Adapter.JSON ?? [:])
        }
        return try V2Adapter.decode(McpStatusMap.self, from: map)
    }

    /// Register a server with the running instance. Like v1 `POST /mcp`, 2.x keeps
    /// it in memory only.
    func v2Add(name: String, config: McpConfig, directory: String?) async throws -> McpStatusMap {
        guard let body = V2Adapter.mcpConfig(fromV1: config) else {
            throw OpenCodeError.unsupported("Enable-only MCP overrides")
        }
        try await client.requestVoid(
            .v2(
                "/api/experimental/mcp/\(APIEndpoint.segment(name))",
                method: .PUT,
                json: ["config": body],
                queryItems: APIEndpoint.v2Location(directory)
            )
        )
        return try await v2List(directory: directory)
    }

    func v2Connect(name: String, directory: String?, connect: Bool) async throws {
        let action = connect ? "connect" : "disconnect"
        try await client.requestVoid(
            .post("/api/experimental/mcp/\(APIEndpoint.segment(name))/\(action)", queryItems: APIEndpoint.v2Location(directory))
        )
    }
}

// MARK: - FileAPI (OpenCode 2.x)

extension FileAPI {
    func v2List(path: String, directory: String?) async throws -> [FileNode] {
        let data = try await client.v2Data(
            .get("/api/fs/list", queryItems: APIEndpoint.v2Location(directory, [URLQueryItem(name: "path", value: path)]))
        )
        let nodes = (data as? [V2Adapter.JSON] ?? []).map { V2Adapter.fileNode($0, root: directory) }
        return try V2Adapter.decode([FileNode].self, from: nodes)
    }

    /// `GET /api/fs/read/<path>` serves raw bytes; v1 returned text or base64 JSON.
    func v2Content(path: String, directory: String?) async throws -> FileContent {
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map { APIEndpoint.segment(String($0)) }
        let data = try await client.requestData(
            .get("/api/fs/read/" + segments.joined(separator: "/"), queryItems: APIEndpoint.v2Location(directory))
        )
        let content: V2Adapter.JSON
        if let text = String(data: data, encoding: .utf8), !data.contains(0) {
            content = ["type": "text", "content": text]
        } else {
            content = ["type": "binary", "content": data.base64EncodedString(), "encoding": "base64"]
        }
        return try V2Adapter.decode(FileContent.self, from: content)
    }

    func v2Status(directory: String?) async throws -> [ChangedFile] {
        let data = try await client.v2Data(.get("/api/vcs/status", queryItems: APIEndpoint.v2Location(directory)))
        let files = (data as? [V2Adapter.JSON] ?? []).map(V2Adapter.changedFile)
        return try V2Adapter.decode([ChangedFile].self, from: files)
    }

    func v2FindFiles(query: String, kind: FindKind?, directory: String?, limit: Int) async throws -> [String] {
        var extra = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(min(limit, 200))),
        ]
        if let kind { extra.append(URLQueryItem(name: "type", value: kind.rawValue)) }
        let data = try await client.v2Data(.get("/api/fs/find", queryItems: APIEndpoint.v2Location(directory, extra)))
        return (data as? [V2Adapter.JSON] ?? []).compactMap { entry in
            guard let path = entry["path"] as? String else { return nil }
            // v1 marks directories with a trailing slash.
            return (entry["type"] as? String) == "directory" && !path.hasSuffix("/") ? path + "/" : path
        }
    }

    func v2ListProjects() async throws -> [Project] {
        let data = try await client.v2JSON(.get("/api/project"))
        let projects = (data as? [V2Adapter.JSON] ?? []).map(V2Adapter.project)
        return try V2Adapter.decode([Project].self, from: projects)
    }

    func v2CurrentProject(directory: String?) async throws -> Project {
        let location = try await client.v2JSON(.get("/api/location", queryItems: APIEndpoint.v2Location(directory))) as? V2Adapter.JSON
        let projectID = (location?["project"] as? V2Adapter.JSON)?["id"] as? String
        guard let project = try await v2ListProjects().first(where: { $0.id == projectID }) else {
            throw OpenCodeError.notFound(message: "Project for \(directory ?? "default location")")
        }
        return project
    }

    func v2UpdateProject(projectID: String, name: String?, icon: ProjectIcon?, commands: ProjectCommands?) async throws -> Project {
        var body: V2Adapter.JSON = [:]
        if let name { body["name"] = name }
        if let icon {
            var value: V2Adapter.JSON = [:]
            if let url = icon.url { value["url"] = url }
            if let override = icon.override { value["override"] = override }
            if let color = icon.color { value["color"] = color }
            body["icon"] = value
        }
        if let start = commands?.start { body["commands"] = ["start": start] }
        let data = try await client.v2JSON(.v2("/api/project/\(APIEndpoint.segment(projectID))", method: .PATCH, json: body))
        return try V2Adapter.decode(Project.self, from: V2Adapter.project(data as? V2Adapter.JSON ?? [:]))
    }
}

// MARK: - VcsAPI (OpenCode 2.x)

extension VcsAPI {
    func v2Info(directory: String?) async throws -> VcsInfo {
        let data = try await client.v2Data(.get("/api/vcs", queryItems: APIEndpoint.v2Location(directory))) as? V2Adapter.JSON
        let branch = data?["branch"] as? V2Adapter.JSON
        var info: V2Adapter.JSON = [:]
        if let current = branch?["current"] { info["branch"] = current }
        if let defaultBranch = branch?["default"] { info["default_branch"] = defaultBranch }
        return try V2Adapter.decode(VcsInfo.self, from: info)
    }

    func v2Status(directory: String?) async throws -> [FileDiff] {
        let data = try await client.v2Data(.get("/api/vcs/status", queryItems: APIEndpoint.v2Location(directory)))
        return try V2Adapter.decode([FileDiff].self, from: data)
    }

    func v2Diff(mode: DiffMode, context: Int?, directory: String?) async throws -> [FileDiff] {
        // v1 `git` (uncommitted changes) is 2.x `working`.
        var extra = [URLQueryItem(name: "mode", value: mode == .git ? "working" : "branch")]
        if let context { extra.append(URLQueryItem(name: "context", value: String(context))) }
        let data = try await client.v2Data(.get("/api/vcs/diff", queryItems: APIEndpoint.v2Location(directory, extra)))
        return try V2Adapter.decode([FileDiff].self, from: data)
    }
}

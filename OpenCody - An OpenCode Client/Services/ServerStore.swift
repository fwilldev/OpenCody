import Combine
import Foundation

@MainActor
final class ServerStoreModel: ObservableObject {
    @Published private(set) var servers: [ServerConnection] = []

    func load() {
        servers = ServerStore.shared.load()
    }

    func add(_ server: ServerConnection) {
        servers.append(server)
        ServerStore.shared.save(servers)
    }

    func update(_ server: ServerConnection) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            ServerStore.shared.save(servers)
        }
    }

    func delete(id: UUID) {
        servers.removeAll { $0.id == id }
        ServerStore.shared.save(servers)
    }
}

// MARK: - ServerStore

/// Lightweight persistence for server configurations using `UserDefaults`.
/// This avoids SwiftData setup issues and persists across app restarts.
final class ServerStore {
    static let shared = ServerStore()

    private let storageKey = "opencode.servers"

    private init() {}

    func load() -> [ServerConnection] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        do {
            let stored = try JSONDecoder().decode([StoredServer].self, from: data)
            return stored.map { $0.toModel() }
        } catch {
            return []
        }
    }

    func save(_ servers: [ServerConnection]) {
        let stored = servers.map { StoredServer(from: $0) }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - StoredServer

private struct StoredServer: Codable {
    let id: UUID
    let name: String
    let hostname: String
    let port: Int?
    let useHTTPS: Bool
    let username: String
    let keychainIdentifier: String
    let createdAt: Date
    let lastConnectedAt: Date?
    let isDefault: Bool
    /// Optional so configurations stored before the setting existed still decode.
    let apiVersion: ServerAPIVersion?

    init(from server: ServerConnection) {
        id = server.id
        name = server.name
        hostname = server.hostname
        port = server.port
        useHTTPS = server.useHTTPS
        username = server.username
        keychainIdentifier = server.keychainIdentifier
        createdAt = server.createdAt
        lastConnectedAt = server.lastConnectedAt
        isDefault = server.isDefault
        apiVersion = server.apiVersion
    }

    func toModel() -> ServerConnection {
        ServerConnection(
            id: id,
            name: name,
            hostname: hostname,
            port: port,
            useHTTPS: useHTTPS,
            username: username,
            keychainIdentifier: keychainIdentifier,
            createdAt: createdAt,
            lastConnectedAt: lastConnectedAt,
            isDefault: isDefault,
            apiVersion: apiVersion ?? .v1
        )
    }
}

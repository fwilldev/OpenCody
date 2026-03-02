//
//  ServerConnection.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import Foundation
import Observation
@Observable
final class ServerConnection: Identifiable, Codable {
    var id: UUID
    var name: String
    var hostname: String
    var port: Int
    var useHTTPS: Bool
    var username: String
    var keychainIdentifier: String
    var createdAt: Date
    var lastConnectedAt: Date?
    var isDefault: Bool

    /// Computed base URL — not stored by SwiftData.
    var baseURL: String {
        let scheme = useHTTPS ? "https" : "http"
        return "\(scheme)://\(hostname):\(port)"
    }

    init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int = 4096,
        useHTTPS: Bool = false,
        username: String = "",
        keychainIdentifier: String = UUID().uuidString,
        createdAt: Date = Date(),
        lastConnectedAt: Date? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.useHTTPS = useHTTPS
        self.username = username
        self.keychainIdentifier = keychainIdentifier
        self.createdAt = createdAt
        self.lastConnectedAt = lastConnectedAt
        self.isDefault = isDefault
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case hostname
        case port
        case useHTTPS
        case username
        case keychainIdentifier
        case createdAt
        case lastConnectedAt
        case isDefault
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        hostname = try container.decode(String.self, forKey: .hostname)
        port = try container.decode(Int.self, forKey: .port)
        useHTTPS = try container.decode(Bool.self, forKey: .useHTTPS)
        username = try container.decode(String.self, forKey: .username)
        keychainIdentifier = try container.decode(String.self, forKey: .keychainIdentifier)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(hostname, forKey: .hostname)
        try container.encode(port, forKey: .port)
        try container.encode(useHTTPS, forKey: .useHTTPS)
        try container.encode(username, forKey: .username)
        try container.encode(keychainIdentifier, forKey: .keychainIdentifier)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastConnectedAt, forKey: .lastConnectedAt)
        try container.encode(isDefault, forKey: .isDefault)
    }
}

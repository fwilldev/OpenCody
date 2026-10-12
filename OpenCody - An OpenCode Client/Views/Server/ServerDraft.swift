import Foundation

/// Editable copy of a server's settings, so Cancel never touches the saved server.
struct ServerDraft: Equatable {
    var name = ""
    var hostname = ""
    var port = ""
    var useHTTPS = false
    var username = ""
    var password = ""
    var apiVersion: ServerAPIVersion = .v2

    init() {}

    init(server: ServerConnection, password: String) {
        name = server.name
        hostname = server.hostname
        port = server.port.map(String.init) ?? ""
        useHTTPS = server.useHTTPS
        username = server.username
        self.password = password
        apiVersion = server.apiVersion
    }

    private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    var portNumber: Int? { Int(trimmed(port)) }

    var canSave: Bool {
        !trimmed(name).isEmpty && !trimmed(hostname).isEmpty
            && (trimmed(port).isEmpty || (portNumber ?? 0) > 0)
    }

    var baseURL: String {
        let host = trimmed(hostname).isEmpty ? "hostname" : trimmed(hostname)
        let scheme = useHTTPS ? "https" : "http"
        return portNumber.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
    }

    /// 2.x only accepts `opencode`, so an empty username means that there.
    var effectiveUsername: String {
        let name = trimmed(username)
        return name.isEmpty && apiVersion == .v2 ? PairingAPI.username : name
    }

    /// What decides which server answers — a change re-runs version detection.
    var endpointKey: String { "\(baseURL)|\(username)|\(password)" }

    /// Fill the address and credentials from a redeemed pairing link.
    mutating func apply(pairing link: PairingAPI.Link, token: String) {
        applyURL(link.server.absoluteString)
        if trimmed(name).isEmpty { name = link.server.host ?? "" }
        username = PairingAPI.username
        password = token
        apiVersion = .v2
    }

    /// Accept a full URL typed or pasted into the host field (`https://box.local:4096/`),
    /// splitting it into scheme, host and port. Returns `false` for a plain host name.
    @discardableResult
    mutating func applyURL(_ text: String) -> Bool {
        let value = trimmed(text)
        guard value.contains("://"), let components = URLComponents(string: value),
              let host = components.host, !host.isEmpty else { return false }
        hostname = host
        useHTTPS = components.scheme?.lowercased() == "https"
        port = components.port.map(String.init) ?? ""
        return true
    }

    /// Write the draft into `server` (a new or an existing one).
    func apply(to server: ServerConnection) {
        server.name = trimmed(name)
        server.hostname = trimmed(hostname)
        server.port = portNumber
        server.useHTTPS = useHTTPS
        server.username = effectiveUsername
        server.apiVersion = apiVersion
    }

    func makeServer() -> ServerConnection {
        let server = ServerConnection(name: "", hostname: "")
        apply(to: server)
        return server
    }
}

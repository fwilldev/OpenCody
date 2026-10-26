import SwiftUI

/// Add or edit a server: one native form for both, working on a `ServerDraft`.
///
/// The API generation is detected as soon as the address is entered (2.x first,
/// then 1.x) and preselected; the picker stays available to override it.
struct ServerFormView: View {
    /// `nil` adds a new server.
    let server: ServerConnection?
    let connectionManager: ConnectionManager

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var serverStore: ServerStoreModel

    @State private var draft = ServerDraft()
    @State private var testState: TestState = .idle
    @State private var detection: Detection = .idle
    @State private var showDeleteConfirmation = false
    @State private var pairingText = ""
    @State private var pairing: PairingState = .idle

    private enum PairingState: Equatable {
        case idle, redeeming, paired, failure(String)
    }

    private enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    private enum Detection: Equatable {
        case idle, detecting, found(ServerAPIVersion, String), notFound
    }

    private enum Field: Hashable { case name, host, port, username, password }
    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            Form {
                pairingSection

                Section {
                    TextField("Name", text: $draft.name, prompt: Text("My Server"))
                        .textInputAutocapitalization(.words)
                        .focused($focus, equals: .name)
                        .accessibilityIdentifier("server.name")
                } header: {
                    Text("Name")
                }

                Section {
                    TextField("Host", text: $draft.hostname, prompt: Text("192.168.1.100"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .focused($focus, equals: .host)
                        .onSubmit { draft.applyURL(draft.hostname) }
                        .accessibilityIdentifier("server.host")
                    TextField("Port", text: $draft.port, prompt: Text("Default"))
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .port)
                        .accessibilityIdentifier("server.port")
                    Toggle("Use HTTPS", isOn: $draft.useHTTPS)
                } header: {
                    Text("Address")
                } footer: {
                    Text(draft.baseURL)
                        .font(Theme.Fonts.codeCaption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Section {
                    TextField("Username", text: $draft.username, prompt: Text(draft.apiVersion == .v2 ? "opencode" : "admin"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .focused($focus, equals: .username)
                        .accessibilityIdentifier("server.username")
                    SecureField("Password", text: $draft.password, prompt: Text("Password"))
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .accessibilityIdentifier("server.password")
                } header: {
                    Text("Sign In")
                } footer: {
                    Text(draft.apiVersion == .v2
                 ? "OpenCode 2.x prints its password when it starts. The username is always “opencode”."
                 : "The server's OPENCODE_SERVER_USERNAME and OPENCODE_SERVER_PASSWORD, if set.")
                }

                Section {
                    Picker("Server Version", selection: $draft.apiVersion) {
                        ForEach(ServerAPIVersion.allCases) { version in
                            Text(version.displayName).tag(version)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Server Version")
                } footer: {
                    detectionFooter
                }

                Section {
                    Button(action: testConnection) {
                        HStack {
                            Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            testStatus
                        }
                    }
                    .disabled(draft.hostname.isEmpty || testState == .testing)
                } footer: {
                    if case .failure(let message) = testState {
                        Text(message).foregroundStyle(Theme.Colors.hotPink)
                    }
                }

                if let server, server.apiVersion == .v2 {
                    Section {
                        NavigationLink {
                            PushSetupView(server: server)
                        } label: {
                            Label("Push Notifications", systemImage: "bell.badge")
                        }
                    } footer: {
                        Text("Alerts from this server while OpenCody is closed.")
                    }
                }

                if server != nil {
                    Section {
                        Button("Delete Server", systemImage: "trash", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.deepBlack)
            .navigationTitle(server == nil ? "Add Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(server == nil ? "Save Server" : "Save", action: save)
                        .disabled(!draft.canSave)
                }
            }
            .onAppear(perform: loadDraft)
            .task(id: draft.endpointKey) { await detectVersion() }
            .onChange(of: draft.endpointKey) { testState = .idle }
            .sensoryFeedback(.success, trigger: testState == .success || pairing == .paired)
            .confirmationDialog("Delete Server", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deleteServer)
            } message: {
                Text("This removes “\(draft.name)” and its saved password from this device.")
            }
        }
    }

    // MARK: - Subviews

    private var pairingSection: some View {
        Section {
            HStack {
                TextField("Pairing Link", text: $pairingText, prompt: Text("https://host:4096/auth/connect/…"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { redeem(pairingText) }
                    .accessibilityIdentifier("server.pairingLink")
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    pairingText = text
                    redeem(text)
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
            }
            switch pairing {
            case .idle:
                EmptyView()
            case .redeeming:
                Label { Text("Pairing…") } icon: { ProgressView() }
            case .paired:
                Label("Paired. Address and password are filled in.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.neonGreen)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.hotPink)
            }
        } header: {
            Text("Pair (OpenCode 2.x)")
        } footer: {
            Text("Paste a pairing link from another device or from the server's web app to fill everything in. Or enter the details below.")
        }
    }

    @ViewBuilder
    private var detectionFooter: some View {
        switch detection {
        case .idle:
            Text("New servers use OpenCode 2.x. Choose 1.x for servers installed as opencode-ai.")
        case .detecting:
            Label("Checking which version the server runs…", systemImage: "magnifyingglass")
        case .found(let version, let serverVersion):
            Label("Detected \(version.displayName)\(serverVersion.isEmpty ? "" : " (\(serverVersion))").", systemImage: "checkmark.circle")
                .foregroundStyle(Theme.Colors.neonGreen)
        case .notFound:
            Text("Couldn't detect the version yet. Check the address and password, or pick it yourself.")
        }
    }

    @ViewBuilder
    private var testStatus: some View {
        switch testState {
        case .idle, .failure:
            EmptyView()
        case .testing:
            ProgressView()
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Theme.Colors.neonGreen)
                .accessibilityLabel("Connection successful")
        }
    }

    // MARK: - Actions

    private func loadDraft() {
        guard draft == ServerDraft() else { return }
        if let server {
            let password = (try? KeychainService.retrieve(for: server.keychainIdentifier)) ?? ""
            draft = ServerDraft(server: server, password: password)
        }
    }

    private func redeem(_ text: String) {
        guard let link = PairingAPI.parse(text) else {
            pairing = text.trimmingCharacters(in: .whitespaces).isEmpty
                ? .idle : .failure("That isn't a pairing link (…/auth/connect/…).")
            return
        }
        pairing = .redeeming
        Task {
            do {
                let token = try await PairingAPI.redeem(link)
                draft.apply(pairing: link, token: token)
                pairingText = ""
                withAnimation { pairing = .paired }
            } catch OpenCodeError.auth {
                pairing = .failure("This pairing link has expired or was already used.")
            } catch {
                pairing = .failure(error.localizedDescription)
            }
        }
    }

    private func detectVersion() async {
        guard !draft.hostname.trimmingCharacters(in: .whitespaces).isEmpty else {
            detection = .idle
            return
        }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        if draft.applyURL(draft.hostname) { return }  // Re-runs with the split URL.

        detection = .detecting
        let result = try? await APIClient.detectAPIVersion(
            baseURL: draft.baseURL, username: draft.username, password: draft.password
        )
        guard !Task.isCancelled else { return }
        if let result {
            draft.apiVersion = result.apiVersion
            detection = .found(result.apiVersion, result.serverVersion)
        } else {
            detection = .notFound
        }
    }

    private func testConnection() {
        draft.applyURL(draft.hostname)
        let probe = draft.makeServer()
        let password = draft.password
        testState = .testing
        Task {
            do {
                try await connectionManager.connect(server: probe, password: password)
                connectionManager.disconnect(serverID: probe.id)
                withAnimation { testState = .success }
            } catch {
                withAnimation { testState = .failure(error.localizedDescription) }
            }
        }
    }

    private func save() {
        draft.applyURL(draft.hostname)
        if let server {
            let previousVersion = server.apiVersion
            let previousURL = server.baseURL
            draft.apply(to: server)
            try? KeychainService.save(password: draft.password, for: server.keychainIdentifier)
            serverStore.update(server)
            // A live connection keeps speaking the old address/API; rebuild it.
            if previousVersion != server.apiVersion || previousURL != server.baseURL
                || connectionManager.activeServerID == server.id {
                let wasActive = connectionManager.activeServerID == server.id
                connectionManager.disconnect(serverID: server.id)
                if wasActive { connectionManager.connectAndActivate(server: server) }
            }
        } else {
            let connection = draft.makeServer()
            try? KeychainService.save(password: draft.password, for: connection.keychainIdentifier)
            serverStore.add(connection)
            connectionManager.connectAndActivate(server: connection)
        }
        dismiss()
    }

    private func deleteServer() {
        guard let server else { return }
        connectionManager.disconnect(serverID: server.id)
        try? KeychainService.delete(for: server.keychainIdentifier)
        serverStore.delete(id: server.id)
        dismiss()
    }
}

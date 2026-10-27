import SwiftUI
import UniformTypeIdentifiers

/// Push notifications for one server: pair this device (at the relay and on the server's
/// `opencody-notify` plugin) and explain how to install the plugin.
struct PushSetupView: View {
    let server: ServerConnection

    private enum Guide: String, CaseIterable { case human = "Human", agent = "Agent" }
    private enum TestState: Equatable { case idle, sending, sent(String), failure(String) }

    private let push = PushService.shared
    @State private var busy = false
    @State private var error: String?
    @State private var revealed = false
    @State private var guide = Guide.human
    @State private var test = TestState.idle
    @State private var confirmTurnOff = false

    var body: some View {
        Form {
            if server.apiVersion != .v2 {
                Section {
                    Text("Notifications need OpenCode 2 or later. This server runs OpenCode 1.x.")
                }
            } else {
                let pairing = push.pairing(for: server.id)
                if let pairing {
                    status(pairing)
                } else {
                    Section {
                        Button("Turn On Push Notifications", systemImage: "bell.badge") { Task { await pair() } }
                            .disabled(busy)
                        if busy { Label { Text("Pairing…") } icon: { ProgressView() } }
                    } footer: {
                        Text("Get alerts when a run finishes, fails or needs your answer, even while OpenCody is closed. Your server sends them through the OpenCody relay, which only sees encrypted data.")
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.hotPink)
                    }
                }

                guideSection()

                if let pairing {
                    tools(pairing)
                    advanced(pairing)
                }
            }
        }
        .task {
            // Re-registers silently once, e.g. after the server lost its pairings.
            if case .sent = push.serverReplies[server.id] { return }
            await push.registerOnServer(server)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.deepBlack)
        .navigationTitle("Push Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Turn Off Push", isPresented: $confirmTurnOff, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) { Task { await push.unpair(server: server.id, client: server.makeAPIClient()) } }
        } message: {
            Text("This device stops getting push notifications from “\(server.name)”. If you added its pairing string to the server by hand, remove it there too.")
        }
    }

    @ViewBuilder
    private func status(_ pairing: PushPairing) -> some View {
        if pairing.broken {
            Section {
                Label("This pairing stopped working. Pair again.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.neonOrange)
                Button("Pair Again", systemImage: "arrow.clockwise") { Task { await pair() } }
                    .disabled(busy)
            }
        } else {
            Section {
                if push.registering.contains(server.id) {
                    Label { Text("Registering this device with your server…") } icon: { ProgressView() }
                } else if case .sent(let label) = push.serverReplies[server.id] {
                    Label("Paired with “\(label.isEmpty ? server.name : label)”", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.neonGreen)
                } else if let reply = push.serverReplies[server.id] {
                    Label(reply.message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.neonOrange)
                    Button("Try Again", systemImage: "arrow.clockwise") { Task { await push.registerOnServer(server) } }
                }
            } header: {
                Text("Server")
            } footer: {
                if case .sent = push.serverReplies[server.id] {
                    Text("Your server sends this device notifications now.")
                } else if push.serverReplies[server.id] != nil, !push.registering.contains(server.id) {
                    Text("Or set up the server by hand with the pairing string under Advanced.")
                }
            }
        }
    }

    private func guideSection() -> some View {
        Section {
            Picker("Guide", selection: $guide) {
                ForEach(Guide.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            switch guide {
            case .human:
                ForEach(Array(PushSetupGuide.humanSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text("\(index + 1).").foregroundStyle(Theme.Colors.cyberBlue).monospacedDigit()
                        Text(LocalizedStringKey(step))
                    }
                }
            case .agent:
                Text(PushSetupGuide.agentPrompt(serverName: server.name))
                    .font(Theme.Fonts.codeCaption)
                    .textSelection(.enabled)
                Button("Copy Prompt", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = PushSetupGuide.agentPrompt(serverName: server.name)
                }
            }
        } header: {
            Text("Set Up the Server")
        } footer: {
            Text(guide == .human
                 ? "Needs OpenCode 2.1 or later on the server and outbound HTTPS to the relay."
                 : "Paste this into Claude Code, Codex or OpenCode on a machine that can manage your server. It contains no secrets.")
        }
    }

    @ViewBuilder
    private func tools(_ pairing: PushPairing) -> some View {
        Section {
            Button("Send Test Notification", systemImage: "paperplane") { Task { await sendServerTest(pairing) } }
                .disabled(test == .sending || pairing.broken)
            switch test {
            case .idle: EmptyView()
            case .sending: Label { Text("Sending…") } icon: { ProgressView() }
            case .sent(let message): Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.neonGreen)
            case .failure(let message): Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.hotPink)
            }
        } footer: {
            Text("Your server sends it through its opencody-notify plugin, the relay and Apple to this device, like a real notification.")
        }

        Section {
            Button("Test Relay Only", systemImage: "antenna.radiowaves.left.and.right") { Task { await sendRelayTest(pairing) } }
                .disabled(test == .sending || pairing.broken)
        } footer: {
            Text("Checks the relay and this device, not your server. Useful when the test above fails.")
        }

        Section {
            Button("Turn Off Push", systemImage: "bell.slash", role: .destructive) { confirmTurnOff = true }
        }
    }

    private func advanced(_ pairing: PushPairing) -> some View {
        Section {
            DisclosureGroup("Advanced") {
                Text(revealed ? pairing.pairingString : String(repeating: "•", count: 24))
                    .font(Theme.Fonts.codeCaption)
                    .textSelection(.enabled)
                Button(revealed ? "Hide" : "Reveal", systemImage: revealed ? "eye.slash" : "eye") { revealed.toggle() }
                Button("Copy Pairing String", systemImage: "doc.on.doc") { copy(pairing.pairingString) }
            }
        } footer: {
            Text("Only for servers whose plugin is older than 0.4.0 or that you set up by hand: put this pairing string into OPENCODY_PAIRING on the server and restart OpenCode. Keep it secret, like a password: whoever has it can send notifications to this device and read them.")
        }
    }

    private func pair() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await push.pair(server)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendServerTest(_ pairing: PushPairing) async {
        test = .sending
        let result = await push.sendServerTest(pairing, client: server.makeAPIClient())
        test = if case .sent = result { .sent(result.message) } else { .failure(result.message) }
    }

    private func sendRelayTest(_ pairing: PushPairing) async {
        test = .sending
        do {
            try await push.sendRelayTest(pairing, serverName: server.name)
            test = .sent("Sent through the relay only. It should arrive on this device in a few seconds.")
        } catch {
            test = .failure(error.localizedDescription)
        }
    }

    /// Secrets stay on this device and leave the clipboard after five minutes.
    private func copy(_ text: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]],
                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
    }
}

/// Texts for setting up the `opencody-notify` plugin (opencody-push/plugin/README.md).
enum PushSetupGuide {
    static let humanSteps = [
        "On your OpenCode 2 server, install the plugin globally: `opencode plugin add opencody-notify`.",
        "Restart OpenCode once.",
        "Turn on push for this server here.",
        "Tap Send Test Notification. Your server sends it, so it shows the whole setup works. Then start a run: you get a notification when it finishes, fails or needs your answer.",
    ]

    static func agentPrompt(serverName: String) -> String {
        """
        Set up my OpenCode 2 server ("\(serverName)") for push notifications to the OpenCody app on my device: install the OpenCode plugin `opencody-notify` (version 0.4.0 or later). Afterwards OpenCody registers this device on the server by itself; no pairing string or environment variable is needed.

        Steps:
        1. Find out how OpenCode runs: natively (`opencode serve`, e.g. as a systemd service) or in a container (Docker, docker compose, Coolify). Check it is OpenCode 2.1 or later (`opencode --version`).
        2. Install the plugin in the GLOBAL config of the user that runs OpenCode, with ONE of:
           a. `opencode plugin add opencody-notify`, or
           b. add "opencody-notify" to the "plugins" array in `~/.config/opencode/opencode.jsonc`.
           Not in a project's opencode.jsonc: OpenCody reaches the plugin only at the server's default location. If an older version is installed, update it to 0.4.0 or later.
           If the plugin manager can't install it, unpack the npm package into a folder (`npm pack opencody-notify`, then `tar -xzf opencody-notify-*.tgz --strip-components=1`) and add `{ "package": "<absolute path of that folder>" }` to "plugins".
           In a container, do this in the image or a mounted config so it survives a rebuild, and keep `~/.local/share/opencody-notify/` (the paired devices) on a persistent volume.
           Optional: OPENCODY_SERVER_LABEL=<short name> sets the server name shown in notifications.
        3. The server needs outbound HTTPS to \(PushService.relayURL).
        4. Restart OpenCode once (recreate the container if it runs in one).
        5. Verify: OpenCode starts cleanly, and `GET /api/plugin` on the server (same authentication as the rest of its API) lists `opencody-notify` with state "active". Then tell me to turn on push for this server in OpenCody and tap "Send Test Notification".

        Rules:
        - Change nothing else: no other config, packages or services.
        - Ask me before restarting a production server or one that others use.
        """
    }
}

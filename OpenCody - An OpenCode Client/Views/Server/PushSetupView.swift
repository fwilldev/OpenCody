import SwiftUI
import UniformTypeIdentifiers

/// Push notifications for one server: pair this iPhone, show the pairing string and
/// explain how to install the `opencody-notify` plugin on the server.
struct PushSetupView: View {
    let server: ServerConnection

    private enum Guide: String, CaseIterable { case human = "Human", agent = "Agent" }
    private enum TestState: Equatable { case idle, sending, sent, failure(String) }

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
            } else if let pairing = push.pairing(for: server.id) {
                paired(pairing)
            } else {
                Section {
                    Button("Turn On Push Notifications", systemImage: "bell.badge") { Task { await pair() } }
                        .disabled(busy)
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
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.deepBlack)
        .navigationTitle("Push Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Turn Off Push", isPresented: $confirmTurnOff, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) { Task { await push.unpair(server: server.id) } }
        } message: {
            Text("This iPhone stops getting push notifications from “\(server.name)”. Remove the pairing string from the server too.")
        }
    }

    @ViewBuilder
    private func paired(_ pairing: PushPairing) -> some View {
        if pairing.broken {
            Section {
                Label("This pairing stopped working. Pair again and replace the string on the server.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.neonOrange)
                Button("Pair Again", systemImage: "arrow.clockwise") { Task { await pair() } }
                    .disabled(busy)
            }
        }

        Section {
            Text(revealed ? pairing.pairingString : String(repeating: "•", count: 24))
                .font(Theme.Fonts.codeCaption)
                .textSelection(.enabled)
            Button(revealed ? "Hide" : "Reveal", systemImage: revealed ? "eye.slash" : "eye") { revealed.toggle() }
            Button("Copy Pairing String", systemImage: "doc.on.doc") { copy(pairing.pairingString) }
        } header: {
            Text("Pairing String")
        } footer: {
            Text("Keep it secret, like a password: whoever has it can send notifications to this iPhone and read them.")
        }

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
                Text(PushSetupGuide.agentPrompt(pairing: revealed ? pairing.pairingString : "<pairing string, included when you copy>",
                                                serverName: server.name))
                    .font(Theme.Fonts.codeCaption)
                    .textSelection(.enabled)
                Button("Copy Prompt", systemImage: "doc.on.doc") {
                    copy(PushSetupGuide.agentPrompt(pairing: pairing.pairingString, serverName: server.name))
                }
            }
        } header: {
            Text("Set Up the Server")
        } footer: {
            Text(guide == .human
                 ? "Needs OpenCode 2 on the server and outbound HTTPS to the relay."
                 : "Paste this into Claude Code, Codex or OpenCode on a machine that can manage your server. It contains the pairing string.")
        }

        Section {
            Button("Send Test Notification", systemImage: "paperplane") { Task { await sendTest(pairing) } }
                .disabled(test == .sending || pairing.broken)
            switch test {
            case .idle: EmptyView()
            case .sending: Label { Text("Sending…") } icon: { ProgressView() }
            case .sent: Label("Sent. It should arrive in a few seconds.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.neonGreen)
            case .failure(let message): Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.hotPink)
            }
        } footer: {
            Text("Tests the relay and this iPhone. Your server isn't involved.")
        }

        Section {
            Button("Turn Off Push", systemImage: "bell.slash", role: .destructive) { confirmTurnOff = true }
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

    private func sendTest(_ pairing: PushPairing) async {
        test = .sending
        do {
            try await push.sendTest(pairing, serverName: server.name)
            test = .sent
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
        "On your OpenCode 2 server, run `opencode plugin add opencody-notify`. Or add \"opencody-notify\" to \"plugins\" in opencode.jsonc.",
        "Set the environment variable OPENCODY_PAIRING to the pairing string above. For several iPhones, separate their strings with commas or new lines.",
        "Docker or Coolify: add the variable to the container, ideally as a secret, and restart the container.",
        "Restart OpenCode.",
        "Tap Send Test Notification below. Then start a run: you get a notification when it finishes, fails or needs your answer.",
    ]

    static func agentPrompt(pairing: String, serverName: String) -> String {
        """
        Set up push notifications from my OpenCode 2 server ("\(serverName)") to the OpenCody iPhone app. Install and configure the OpenCode plugin `opencody-notify`.

        Pairing string (a secret, treat it like a password):
        \(pairing)

        Steps:
        1. Find out how OpenCode runs: natively (`opencode serve`, e.g. as a systemd service) or in a container (Docker, docker compose, Coolify). Check it is OpenCode 2 or later (`opencode --version`).
        2. Install the plugin with ONE of:
           a. `opencode plugin add opencody-notify` (adds it to the global config of the user that runs OpenCode), or
           b. add "opencody-notify" to the "plugins" array in `~/.config/opencode/opencode.jsonc` of that user (or `<project>/opencode.jsonc`).
           If the plugin manager can't install it, unpack the npm package into a folder (`npm pack opencody-notify`, then `tar -xzf opencody-notify-*.tgz --strip-components=1`) and add `{ "package": "<absolute path of that folder>" }` to "plugins".
           In a container, do this in the image or a mounted config, so it survives a rebuild.
        3. Give the OpenCode process the environment variable OPENCODY_PAIRING with the pairing string. Several iPhones: separate the strings with commas or new lines.
           - Native: an EnvironmentFile (mode 600) for the systemd unit, or the environment of whatever starts OpenCode.
           - Docker / compose: the service's environment or env_file. Coolify: Environment Variables, marked as secret.
           Optional: OPENCODY_SERVER_LABEL=<short name> sets the name shown in notifications.
        4. The server needs outbound HTTPS to \(PushService.relayURL).
        5. Restart OpenCode (recreate the container so it picks up the variable).
        6. Verify: OpenCode starts cleanly, the plugin is loaded and the log shows no `[opencody-notify]` warning about missing pairings. Then ask me to tap "Send Test Notification" in OpenCody and to start a short run; a notification should arrive when it finishes.

        Rules:
        - Change nothing else: no other config, packages or services.
        - Never print the pairing string in output or logs, and never commit it to a repository, least of all a public one. Keep it in env or secret storage.
        - Ask me before restarting a production server or one that others use.
        """
    }
}

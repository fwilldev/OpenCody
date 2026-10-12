import SwiftUI

/// Creates a single-use pairing link for an OpenCode 2.x server, to sign in another
/// device (or the server's web app) without typing the password.
struct PairDeviceView: View {
    let server: ServerConnection

    @Environment(\.dismiss) private var dismiss
    @State private var link: URL?
    @State private var expiresAt: Date?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let link {
                        Text(link.absoluteString)
                            .font(Theme.Fonts.code)
                            .textSelection(.enabled)
                        ShareLink("Share Link", item: link)
                        Button("Copy Link", systemImage: "doc.on.doc") {
                            UIPasteboard.general.url = link
                        }
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.hotPink)
                        Button("Try Again", systemImage: "arrow.clockwise") { Task { await create() } }
                    } else {
                        Label { Text("Creating link…") } icon: { ProgressView() }
                    }
                } footer: {
                    if let expiresAt {
                        Text("Works once, until \(expiresAt, format: .dateTime.hour().minute()). On the other device, paste it under Add Server → Pairing Link, or open it in a browser.")
                    }
                }

                if link != nil {
                    Section {
                        Button("New Link", systemImage: "arrow.clockwise") { Task { await create() } }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.deepBlack)
            .navigationTitle("Pair a Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await create() }
        }
        .presentationDetents([.medium, .large])
    }

    private func create() async {
        link = nil
        error = nil
        let password = (try? KeychainService.retrieve(for: server.keychainIdentifier)) ?? ""
        let client = APIClient(baseURL: server.baseURL, username: server.username, password: password, apiVersion: .v2)
        do {
            let result = try await PairingAPI.createLink(client: client)
            link = result.url
            expiresAt = Date().addingTimeInterval(TimeInterval(result.expiresIn))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

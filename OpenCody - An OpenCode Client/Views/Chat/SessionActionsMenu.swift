//
//  SessionActionsMenu.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Toolbar menu button (ellipsis icon) with session operations.
/// Shown in ChatView's navigation bar.
struct SessionActionsMenu: View {
    let session: Session
    let viewModel: ChatViewModel
    let apiClient: APIClient
    /// Whether Diff, Todos and Files belong in this menu (no utilities panel beside the chat).
    var showsUtilityItems = true

    @State private var showDiff = false
    @State private var showTodos = false
    @State private var showSummary = false
    @State private var isSummarizing = false
    @State private var actionError: String? = nil
    @State private var successMessage: String? = nil
    @State private var showFileExplorer = false
    @State private var showContextUsage = false
    @State private var renamingSession: Session?
    @State private var confirmRevert = false

    var body: some View {
        Menu {
            Section(session.id) {
                Button("Copy Session ID", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = session.id
                }
            }

            Button("Rename Session", systemImage: "pencil") {
                renamingSession = session
            }

            // Context Usage
            Button {
                showContextUsage = true
            } label: {
                Label("Context Usage", systemImage: "chart.bar")
            }

            Divider()

            // Fork
            Button {
                Task { await viewModel.fork(through: nil) }
            } label: {
                Label("Fork Session", systemImage: "arrow.branch")
            }

            // Summarize (triggers context compaction on the server)
            Button {
                Task { await summarizeSession() }
            } label: {
                Label(isSummarizing ? "Summarizing…" : "Summarize", systemImage: "sparkles.rectangle.stack")
            }
            .disabled(isSummarizing)

            Divider()

            if showsUtilityItems {
                Button {
                    showDiff = true
                } label: {
                    Label("View Diff", systemImage: "list.bullet.rectangle")
                }

                Button {
                    showTodos = true
                } label: {
                    Label("Todos", systemImage: "checkmark.circle")
                }

                Button {
                    showFileExplorer = true
                } label: {
                    Label("File Explorer", systemImage: "folder")
                }
            }

            Divider()

            // Revert
            Button {
                confirmRevert = true
            } label: {
                Label("Revert", systemImage: "arrow.uturn.backward")
            }

            // Unrevert
            Button {
                Task { await unrevertSession() }
            } label: {
                Label("Unrevert", systemImage: "arrow.uturn.forward")
            }

            // Share / Unshare
            if !apiClient.supportsSessionSharing {
                EmptyView()
            } else if session.share != nil {
                Button {
                    Task { await unshareSession() }
                } label: {
                    Label("Unshare", systemImage: "link.badge.plus")
                }

                Button {
                    Task { await shareSession() }
                } label: {
                    Label("Copy Share Link", systemImage: "doc.on.doc.fill")
                }
            } else {
                Button {
                    Task { await shareSession() }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Label("Session Actions", systemImage: "ellipsis")
        }
        .confirmationDialog("Revert the last message?", isPresented: $confirmRevert, titleVisibility: .visible) {
            Button("Revert", role: .destructive) { Task { await revertSession() } }
        } message: {
            Text("The last message is hidden and its file changes are undone. You can bring it back with Unrevert.")
        }
        .renameAlert(
            "Rename Session",
            item: $renamingSession,
            currentName: { $0.title },
            onSave: { _, title in Task { await viewModel.renameSession(to: title) } }
        )
        .sheet(isPresented: $showDiff) {
            SessionDiffView(session: session, apiClient: apiClient)
        }
        .sheet(isPresented: $showTodos) {
            TodoListView(session: session, apiClient: apiClient, viewModel: viewModel)
        }
        .sheet(isPresented: $showFileExplorer) {
            FileExplorerView(
                session: session,
                apiClient: apiClient,
                onReference: { path in
                    viewModel.referenceFile(path: path)
                }
            )
        }
        .sheet(isPresented: $showContextUsage) {
            ContextUsageView(session: session, viewModel: viewModel, apiClient: apiClient)
        }
        .sheet(isPresented: $showSummary) {
            SessionSummaryView(sessionTitle: session.title)
        }
        .alert("Action Error", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert("Done", isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
            Button("OK") { successMessage = nil }
        } message: {
            Text(successMessage ?? "")
        }
    }

    // MARK: - Actions

    private func summarizeSession() async {
        guard let providerID = viewModel.selectedProviderID,
              let modelID = viewModel.selectedModelID else {
            actionError = "No model selected. Please select a model before summarizing."
            return
        }
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            let api = SessionAPI(client: apiClient, directory: session.directory)
            _ = try await api.summarize(id: session.id, providerID: providerID, modelID: modelID)
            await MainActor.run {
                showSummary = true
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func revertSession() async {
        guard let lastMessage = viewModel.messages.last else {
            actionError = "No messages to revert."
            return
        }
        do {
            let api = SessionAPI(client: apiClient, directory: session.directory)
            _ = try await api.revert(id: session.id, messageID: lastMessage.message.id)
            await MainActor.run {
                successMessage = "Session reverted successfully."
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func unrevertSession() async {
        do {
            let api = SessionAPI(client: apiClient, directory: session.directory)
            _ = try await api.unrevert(id: session.id)
            await MainActor.run {
                successMessage = "Revert undone successfully."
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func shareSession() async {
        do {
            let api = SessionAPI(client: apiClient, directory: session.directory)
            let updated = try await api.share(id: session.id)
            guard let urlString = updated.share?.url else {
                actionError = "Share failed: no URL returned."
                return
            }
            await MainActor.run {
                // Copy to clipboard always
                UIPasteboard.general.string = urlString
                // Also present native share sheet if URL is valid
                if let url = URL(string: urlString), let presenter = topmostViewController() {
                    let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    if let popover = av.popoverPresentationController {
                        popover.sourceView = presenter.view
                        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
                    }
                    presenter.present(av, animated: true)
                } else {
                    successMessage = "Share link copied to clipboard."
                }
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func unshareSession() async {
        do {
            let api = SessionAPI(client: apiClient, directory: session.directory)
            try await api.unshare(id: session.id)
            await MainActor.run {
                successMessage = "Session unshared."
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// The view controller currently on top of the presentation stack.
    ///
    /// Presenting on the window's root controller fails ("already presenting") whenever
    /// a sheet from this menu is open, so walk down to whatever is actually frontmost.
    @MainActor
    private func topmostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? scene?.windows.first?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

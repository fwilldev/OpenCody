import SwiftUI

/// Files, Todos and Diff: a sheet in compact width, a panel beside the chat when there is room.
enum ChatUtility: String, CaseIterable, Identifiable {
    case files
    case todos
    case diff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: return "Files"
        case .todos: return "Todos"
        case .diff: return "Diff"
        }
    }

    var systemImage: String {
        switch self {
        case .files: return "folder"
        case .todos: return "checkmark.circle"
        case .diff: return "list.bullet.rectangle"
        }
    }
}

struct ChatUtilitiesPanel: View {
    let session: Session
    let apiClient: APIClient
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(Theme.Colors.border)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.carbon)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Utilities")
                .font(Theme.Fonts.captionBold)
                .foregroundStyle(Theme.Colors.silver)

            Spacer()

            Picker("Utilities", selection: $viewModel.utilityTab) {
                ForEach(ChatUtility.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.utilityTab {
        case .files:
            FileExplorerView(
                session: session,
                apiClient: apiClient,
                showsCloseButton: false,
                onReference: { path in
                    viewModel.referenceFile(path: path)
                }
            )
        case .todos:
            TodoListView(session: session, apiClient: apiClient, viewModel: viewModel, showsCloseButton: false)
        case .diff:
            SessionDiffView(session: session, apiClient: apiClient, showsCloseButton: false)
        }
    }
}

/// A chat in the regular-width layout, with its utilities beside it when there is room.
struct ChatWithUtilitiesView: View {
    let session: Session
    let connectionManager: ConnectionManager

    @State private var viewModel: ChatViewModel
    @State private var width: CGFloat = 0

    init(session: Session, connectionManager: ConnectionManager) {
        self.session = session
        self.connectionManager = connectionManager
        self._viewModel = State(initialValue: .shared(session: session, connectionManager: connectionManager))
    }

    /// The panel only fits next to a usable chat in a wide detail column. Narrower ones
    /// (iPhone Duo's inner display, iPad portrait or Split View) get the sheet instead.
    /// Before the first measurement it assumes the panel, so a restored utility doesn't flash up as a sheet.
    private var showsPanel: Bool { width == 0 || width >= 680 }

    var body: some View {
        // Side by side, so the panel narrows the chat instead of covering its input.
        // (`.inspector` overlays here, inside the split view's detail stack.)
        HStack(spacing: 0) {
            ChatView(
                session: session,
                connectionManager: connectionManager,
                viewModel: viewModel,
                showsUtilitiesPanel: showsPanel
            )

            if showsPanel, viewModel.isUtilityOpen, let client = connectionManager.activeAPIClient {
                Divider()
                ChatUtilitiesPanel(session: session, apiClient: client, viewModel: viewModel)
                    .frame(width: 360)
                    .transition(.move(edge: .trailing))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

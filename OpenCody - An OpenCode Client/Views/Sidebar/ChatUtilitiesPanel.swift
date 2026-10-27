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
                isSheet: false,
                onReference: { path in
                    viewModel.referenceFile(path: path)
                }
            )
        case .todos:
            TodoListView(session: session, apiClient: apiClient, viewModel: viewModel, isSheet: false)
        case .diff:
            SessionDiffView(session: session, apiClient: apiClient, isSheet: false)
        }
    }
}

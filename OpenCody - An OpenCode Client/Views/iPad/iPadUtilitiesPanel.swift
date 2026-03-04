import SwiftUI

enum iPadUtilityTab: String, CaseIterable, Identifiable {
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

struct iPadUtilitiesState {
    let isOpen: Binding<Bool>
    let selectedTab: Binding<iPadUtilityTab>
}

struct iPadUtilitiesPanel: View {
    let session: Session
    let apiClient: APIClient
    let viewModel: ChatViewModel
    @Binding var selectedTab: iPadUtilityTab

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(Color.white.opacity(0.08))

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.carbon)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1),
            alignment: .leading
        )
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Utilities")
                .font(Theme.Fonts.captionBold)
                .foregroundStyle(Theme.Colors.silver)

            Spacer()

            Picker("Utilities", selection: $selectedTab) {
                ForEach(iPadUtilityTab.allCases) { tab in
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
        switch selectedTab {
        case .files:
            FileExplorerView(session: session, apiClient: apiClient, showsCloseButton: false)
        case .todos:
            TodoListView(session: session, apiClient: apiClient, viewModel: viewModel, showsCloseButton: false)
        case .diff:
            SessionDiffView(session: session, apiClient: apiClient, showsCloseButton: false)
        }
    }
}

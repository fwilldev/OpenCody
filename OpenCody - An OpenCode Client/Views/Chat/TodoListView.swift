//
//  TodoListView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Sheet showing the todo list for the current session.
/// Updates in real-time via `todo.updated` SSE events (observed through ChatViewModel).
struct TodoListView: View {
    let session: Session
    let apiClient: APIClient
    let viewModel: ChatViewModel
    let showsCloseButton: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var todos: [TodoItem] = []
    @State private var isLoading = true
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.deepBlack.ignoresSafeArea()

                if isLoading && todos.isEmpty {
                    ProgressView("Loading todos…")
                        .tint(Theme.Colors.cyberBlue)
                        .foregroundStyle(Theme.Colors.silver)
                } else if let err = error {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(Theme.Colors.hotPink)
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.silver)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if todos.isEmpty {
                    EmptyStateView(
                        systemImage: "checkmark.circle",
                        title: "No Todos",
                        message: "This session has no todos yet."
                    )
                } else {
                    todoList
                }
            }
            .navigationTitle("Todos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(Theme.Colors.silver)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    let pending = todos.filter { $0.status == .pending || $0.status == .inProgress }.count
                    Text("\(pending) open")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.silver)
                }
            }
        }
        .presentationBackground(Theme.Colors.carbon)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadTodos()
        }
    }

    init(session: Session, apiClient: APIClient, viewModel: ChatViewModel, showsCloseButton: Bool = true) {
        self.session = session
        self.apiClient = apiClient
        self.viewModel = viewModel
        self.showsCloseButton = showsCloseButton
    }

    private var todoList: some View {
        List {
            let groups: [(String, [TodoItem])] = [
                ("In Progress", todos.filter { $0.status == .inProgress }),
                ("Pending", todos.filter { $0.status == .pending }),
                ("Completed", todos.filter { $0.status == .completed }),
                ("Cancelled", todos.filter { $0.status == .cancelled })
            ]

            ForEach(groups, id: \.0) { group in
                if !group.1.isEmpty {
                    Section(header: Text(group.0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.silver)
                        .textCase(nil)
                    ) {
                        ForEach(group.1) { todo in
                            TodoRow(todo: todo)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func loadTodos() async {
        isLoading = true
        error = nil
        do {
            let api = SessionAPI(client: apiClient, directory: session.directory)
            todos = try await api.todos(id: session.id)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - TodoRow

private struct TodoRow: View {
    let todo: TodoItem

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // Status icon
            Image(systemName: statusIcon)
                .font(.body)
                .foregroundStyle(statusColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.content)
                    .font(.subheadline)
                    .foregroundStyle(contentColor)
                    .strikethrough(todo.status == .completed || todo.status == .cancelled)

                HStack(spacing: 6) {
                    Text(todo.priority.rawValue.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(priorityColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(priorityColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var statusIcon: String {
        switch todo.status {
        case .pending: return "circle"
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch todo.status {
        case .pending: return Theme.Colors.silver
        case .inProgress: return Theme.Colors.cyberBlue
        case .completed: return Theme.Colors.neonGreen
        case .cancelled: return Theme.Colors.smoke
        }
    }

    private var contentColor: Color {
        switch todo.status {
        case .completed, .cancelled: return Theme.Colors.smoke
        default: return Theme.Colors.cloud
        }
    }

    private var priorityColor: Color {
        switch todo.priority {
        case .high: return Theme.Colors.hotPink
        case .medium: return Theme.Colors.neonOrange
        case .low: return Theme.Colors.silver
        }
    }
}

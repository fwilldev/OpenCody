//
//  ChatView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

struct ChatView: View {
    let session: Session
    let connectionManager: ConnectionManager
    let utilitiesState: iPadUtilitiesState?
    @State private var viewModel: ChatViewModel
    @State private var isAtBottom = true
    @FocusState private var isInputFocused: Bool

    init(
        session: Session,
        connectionManager: ConnectionManager,
        utilitiesState: iPadUtilitiesState? = nil
    ) {
        self.session = session
        self.connectionManager = connectionManager
        self.utilitiesState = utilitiesState
        self._viewModel = State(initialValue: ChatViewModel(session: session, connectionManager: connectionManager))
    }

    init(
        session: Session,
        connectionManager: ConnectionManager,
        viewModel: ChatViewModel,
        utilitiesState: iPadUtilitiesState? = nil
    ) {
        self.session = session
        self.connectionManager = connectionManager
        self.utilitiesState = utilitiesState
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                // Agent/Model Picker header
                AgentModelPicker(viewModel: viewModel, connectionManager: connectionManager)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)

                // Error banner
                if let errorMsg = viewModel.error {
                    ErrorBanner(
                        error: .network(errorMsg),
                        onDismiss: { viewModel.error = nil }
                    )
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
                }

                // Message list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            // Load more button at top
                            if viewModel.hasMoreMessages {
                                Button {
                                    Task { await viewModel.loadMore() }
                                } label: {
                                    HStack {
                                        if viewModel.isLoadingMore {
                                            ProgressView()
                                                .tint(Theme.Colors.cyberBlue)
                                                .scaleEffect(0.8)
                                        }
                                        Text(viewModel.isLoadingMore ? "Loading…" : "Load Earlier Messages")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.cyberBlue)
                                    }
                                    .padding(.vertical, Theme.Spacing.sm)
                                }
                            }

                            // Loading indicator for initial message load
                            if viewModel.messages.isEmpty && viewModel.hasMoreMessages {
                                VStack(spacing: Theme.Spacing.sm) {
                                    ProgressView()
                                        .tint(Theme.Colors.cyberBlue)
                                    Text("Loading messages…")
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.Colors.smoke)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            }

                            ForEach(viewModel.displayMessages) { msgWithParts in
                                MessageBubbleView(messageWithParts: msgWithParts, viewModel: viewModel)
                            }

                            // Typing indicator while waiting for AI response
                            if viewModel.isGenerating {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(Theme.Colors.cyberBlue)
                                        .scaleEffect(0.7)
                                    Text("Generating…")
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.Colors.smoke)
                                }
                                .padding(.vertical, Theme.Spacing.sm)
                                .padding(.horizontal, Theme.Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                .animation(.easeInOut(duration: 0.2), value: viewModel.isGenerating)
                            }

                            // Hidden steps indicator
                            if viewModel.hiddenStepMessageCount > 0 {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.Colors.smoke)
                                    Text("\(viewModel.hiddenStepMessageCount) intermediate steps hidden")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.Colors.smoke)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.04))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                        )
                                )
                                .frame(maxWidth: .infinity)
                            }
                            // Bottom anchor for auto-scroll
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        isInputFocused = false
                    }
                    .onChange(of: viewModel.displayMessages.count) { _, _ in
                        if isAtBottom {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.isGenerating) { _, newValue in
                        guard newValue else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            // Permission overlay
            if let permission = viewModel.pendingPermission {
                permissionOverlay(permission: permission)
            }

            // Question dock overlay
            if let questionRequest = viewModel.activeQuestionRequest {
                SessionQuestionDock(request: questionRequest, viewModel: viewModel)
            }
        }
        .navigationTitle(session.title.isEmpty ? "Session" : session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let utilitiesState {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            utilitiesState.isOpen.wrappedValue = true
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .foregroundStyle(Theme.Colors.silver)
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: Theme.Spacing.sm) {
                    RefreshButton {
                        await viewModel.loadMessages()
                    }

                    if let client = connectionManager.activeAPIClient {
                        SessionActionsMenu(
                            session: session,
                            viewModel: viewModel,
                            apiClient: client
                        )
                    } else {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Theme.Colors.silver)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            ChatInputView(viewModel: viewModel, apiClient: connectionManager.activeAPIClient, isInputFocused: $isInputFocused)
        }
        .task {
            await viewModel.loadMessages()
            viewModel.startObservingEvents()
        }
        .onDisappear {
            viewModel.stopObservingEvents()
        }
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Permission Overlay

    @ViewBuilder
    private func permissionOverlay(permission: Permission) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "lock.shield")
                    .font(.title)
                    .foregroundStyle(Theme.Colors.neonOrange)

                Text("Permission Required")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.cloud)

                Text("Tool: \(permission.id)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.silver)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.md)

                HStack(spacing: Theme.Spacing.md) {
                    Button("Deny") {
                        Task { try? await viewModel.replyToPermission(permission, allow: false) }
                    }
                    .foregroundStyle(Theme.Colors.hotPink)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.Colors.hotPink.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.Colors.hotPink.opacity(0.4), lineWidth: 1)
                            )
                    )

                    Button("Allow") {
                        Task { try? await viewModel.replyToPermission(permission, allow: true) }
                    }
                    .foregroundStyle(Theme.Colors.cyberBlue)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.Colors.cyberBlue.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.Colors.cyberBlue.opacity(0.4), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.3))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 12)
            )
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }
}

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
    @State private var scrollViewHeight: CGFloat = 0
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
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .bottom)
                                                .combined(with: .opacity)
                                                .combined(with: .scale(
                                                    scale: 0.96,
                                                    anchor: msgWithParts.message.role == .user ? .bottomTrailing : .bottomLeading
                                                )),
                                            removal: .opacity
                                        )
                                    )
                            }

                            // Typing indicator while waiting for AI response
                            if viewModel.isGenerating {
                                TypingIndicatorView()
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .bottom)
                                                .combined(with: .opacity)
                                                .combined(with: .scale(scale: 0.9, anchor: .bottomLeading)),
                                            removal: .opacity
                                        )
                                    )
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
                                        .fill(Theme.Colors.fillSubtle)
                                        .overlay(
                                            Capsule()
                                                .stroke(Theme.Colors.hairline, lineWidth: 1)
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
                        // Animate message arrival (new bubbles slide up) and the
                        // typing indicator. Keyed on count so streaming updates and
                        // local-to-server ID swaps don't re-trigger transitions.
                        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: viewModel.displayMessages.count)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isGenerating)
                        // Track scroll position to detect when user scrolls away from bottom
                        .onGeometryChange(for: CGFloat.self) { geo in
                            geo.frame(in: .named("chatScroll")).maxY
                        } action: { contentBottom in
                            // Content bottom relative to scroll viewport.
                            // When the bottom of the content is near the bottom of the viewport,
                            // the user is "at bottom".  Allow generous slack (80pt) for rounding
                            // and partial-pixel differences.
                            isAtBottom = contentBottom < scrollViewHeight + 80
                        }
                    }
                    .coordinateSpace(name: "chatScroll")
                    .onGeometryChange(for: CGFloat.self) { geo in
                        geo.size.height
                    } action: { height in
                        scrollViewHeight = height
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        isInputFocused = false
                    }
                    .onChange(of: viewModel.scrollTrigger) { _, _ in
                        if isAtBottom {
                            withAnimation(.easeOut(duration: 0.15)) {
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
            Theme.Colors.scrim
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "lock.shield")
                    .font(.title)
                    .foregroundStyle(Theme.Colors.neonOrange)

                Text("Permission Required")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.cloud)

                Text(permission.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.silver)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.md)

                if let pattern = permission.primaryPattern, pattern != permission.displayTitle {
                    Text(pattern)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.Colors.cloud)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(8)
                        .background(Theme.Colors.graphite)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, Theme.Spacing.md)
                }

                HStack(spacing: Theme.Spacing.md) {
                    Button("Deny") {
                        Task { try? await viewModel.replyToPermission(permission, decision: .reject) }
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
                        Task { try? await viewModel.replyToPermission(permission, decision: .once) }
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

                if permission.supportsAlways {
                    Button("Always Allow") {
                        Task { try? await viewModel.replyToPermission(permission, decision: .always) }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.Colors.silver)
                }
            }
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Theme.Colors.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Theme.Colors.border, lineWidth: 1)
                    )
                    .shadow(color: Theme.Colors.shadow, radius: 12)
            )
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }
}

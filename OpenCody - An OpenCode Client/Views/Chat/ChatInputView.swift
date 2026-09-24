//
//  ChatInputView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

struct ChatInputView: View {
    let viewModel: ChatViewModel
    /// APIClient needed for CommandPaletteView to fetch slash commands.
    let apiClient: APIClient?
    var isInputFocused: FocusState<Bool>.Binding

    /// Which floating palette is currently shown above the input bar.
    ///
    /// A single piece of state instead of one flag per palette: the text `onChange`
    /// then performs at most one state write per frame, which is what SwiftUI's
    /// "action tried to update multiple times per frame" complaint was about.
    private enum Palette {
        case none
        case command
        case fileMention
    }

    @State private var palette: Palette = .none
    @State private var showAttachmentPicker = false
    @State private var attachmentManager = AttachmentManager()
    @State private var isShellMode = false
    /// Bumped on every send to drive haptic feedback and the send-button bounce.
    @State private var sendPulse = 0

    init(viewModel: ChatViewModel, apiClient: APIClient? = nil, isInputFocused: FocusState<Bool>.Binding) {
        self.viewModel = viewModel
        self.apiClient = apiClient
        self.isInputFocused = isInputFocused
    }

    /// The message being composed. Lives in the view model so the file explorer and
    /// the mention palette can insert file references into it.
    private var text: String { viewModel.draftText }

    private var canSend: Bool {
        (!text.trimmingCharacters(in: .whitespaces).isEmpty || !attachmentManager.attachments.isEmpty)
            && !viewModel.isGenerating
            && !viewModel.isBlockedByQuestion
    }

    /// The portion of the text after the leading "/" for palette filtering.
    private var commandQuery: String {
        guard text.hasPrefix("/") else { return "" }
        return String(text.dropFirst())
    }

    /// Extract the query portion after the last "@" for file searching.
    /// Returns nil if no active @-mention is in progress.
    private var fileMentionQuery: String? {
        // Find the last "@" in the text
        guard let atRange = text.range(of: "@", options: .backwards) else { return nil }
        let afterAt = String(text[atRange.upperBound...])
        // If there's a space after the @, it's not an active mention
        if afterAt.contains(" ") { return nil }
        return afterAt
    }

    var body: some View {
        @Bindable var draft = viewModel

        VStack(spacing: 0) {
            // Command palette overlay — rendered above the input bar
            if palette == .command, let client = apiClient {
                CommandPaletteView(
                    apiClient: client,
                    query: commandQuery,
                    onSelect: { command in
                        viewModel.draftText = command + " "
                        palette = .none
                    },
                    onDismiss: {
                        palette = .none
                    }
                )
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // File mention palette overlay — rendered above the input bar
            if palette == .fileMention, let client = apiClient {
                FileMentionPaletteView(
                    apiClient: client,
                    directory: viewModel.session.directory,
                    query: fileMentionQuery ?? "",
                    onSelect: { filePath in
                        palette = .none
                        viewModel.completeFileMention(with: filePath)
                    },
                    onDismiss: {
                        palette = .none
                    }
                )
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Main input area
            VStack(spacing: 0) {
                // Attachment picker row (visible when toggled)
                if showAttachmentPicker {
                    AttachmentPickerView(manager: attachmentManager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Error from attachment manager
                if let attachErr = attachmentManager.error {
                    Text(attachErr)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.hotPink)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, 4)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                attachmentManager.error = nil
                            }
                        }
                }

                // Referenced files pending on the next prompt
                if !viewModel.draftFileAttachments.isEmpty {
                    referencedFilesRow
                }

                HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                    // Attachment toggle button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAttachmentPicker.toggle()
                        }
                    } label: {
                        Image(systemName: showAttachmentPicker ? "paperclip.circle.fill" : "paperclip")
                            .foregroundStyle(
                                showAttachmentPicker
                                    ? Theme.Colors.cyberBlue
                                    : (attachmentManager.attachments.isEmpty ? Theme.Colors.silver : Theme.Colors.neonGreen)
                            )
                            .font(.system(size: 18))
                            .frame(width: 32, height: 32)
                    }

                    // Shell mode toggle button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShellMode.toggle()
                        }
                    } label: {
                        Image(systemName: isShellMode ? "terminal.fill" : "terminal")
                            .foregroundStyle(isShellMode ? Theme.Colors.neonGreen : Theme.Colors.silver)
                            .font(.system(size: 18))
                            .frame(width: 32, height: 32)
                    }

                    // Text input with placeholder
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(isShellMode ? "Shell command\u{2026}" : "Message\u{2026}")
                                .foregroundStyle(Theme.Colors.silver)
                                .font(.body)
                                .padding(.horizontal, 8)
                                .padding(.top, 9)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $draft.draftText)
                            .focused(isInputFocused)
                            .frame(minHeight: 36, maxHeight: 120)
                            .fixedSize(horizontal: false, vertical: true)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .foregroundStyle(Theme.Colors.cloud)
                            .font(.body)
                            .padding(.horizontal, 4)
                            .onChange(of: viewModel.draftText) { _, newValue in
                                updatePaletteVisibility(for: newValue)
                            }
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.Colors.border, lineWidth: 1)
                            )
                    )

                    // Abort button (visible only when generating)
                    if viewModel.isGenerating {
                        Button {
                            Task { try? await viewModel.abort() }
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .foregroundStyle(Theme.Colors.hotPink)
                                .font(.title3)
                                .frame(width: 32, height: 32)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Send button
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(canSend ? Theme.Colors.cyberBlue : Theme.Colors.smoke)
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .scaleEffect(canSend ? 1.0 : 0.88)
                            .symbolEffect(.bounce, value: sendPulse)
                            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: canSend)
                    }
                    .disabled(!canSend)
                    .sensoryFeedback(.impact(weight: .light), trigger: sendPulse)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.carbon.opacity(0.96))
                .animation(.easeInOut(duration: 0.15), value: viewModel.isGenerating)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: palette)
        .animation(.easeInOut(duration: 0.2), value: showAttachmentPicker)
        .animation(.easeInOut(duration: 0.2), value: viewModel.draftFileAttachments.count)
    }

    // MARK: - Referenced Files

    /// Chips for the files referenced in the draft, so it's obvious what will be
    /// sent along with the message.
    private var referencedFilesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(viewModel.draftFileAttachments.enumerated()), id: \.offset) { _, attachment in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                        Text(attachment.filename)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.Colors.cyberBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.cyberBlue.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(Theme.Colors.cyberBlue.opacity(0.35), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, 6)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Sending

    private func send() {
        let toSend = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = attachmentManager.attachments
        let fileReferences = viewModel.draftFileAttachments
        sendPulse += 1
        viewModel.clearDraft()
        palette = .none
        if showAttachmentPicker && attachments.isEmpty {
            withAnimation { showAttachmentPicker = false }
        }

        if isShellMode {
            // Shell mode: send as shell command
            if !toSend.isEmpty {
                attachmentManager.clearAll()
                Task { await viewModel.executeShellCommand(command: toSend) }
            }
        } else if toSend.hasPrefix("/") {
            // Detect slash commands: "/commandName arguments..."
            let withoutSlash = String(toSend.dropFirst())
            let parts = withoutSlash.split(separator: " ", maxSplits: 1)
            let commandName = String(parts.first ?? "")
            let arguments = parts.count > 1 ? String(parts[1]) : nil
            if !commandName.isEmpty {
                attachmentManager.clearAll()
                Task { await viewModel.executeCommand(name: commandName, arguments: arguments) }
            }
        } else {
            var promptAttachments = attachments.map { a in
                let base64 = a.data.base64EncodedString()
                let dataURI = "data:\(a.mimeType);base64,\(base64)"
                return PromptAttachment(mime: a.mimeType, filename: a.filename, url: dataURI)
            }
            // Append file references collected from the mention palette / file explorer
            promptAttachments.append(contentsOf: fileReferences)
            attachmentManager.clearAll()
            Task { await viewModel.sendPrompt(toSend, attachments: promptAttachments) }
        }
    }

    // MARK: - Palettes

    private func updatePaletteVisibility(for newText: String) {
        guard apiClient != nil else {
            if palette != .none { palette = .none }
            return
        }

        // Slash command palette: leading "/" and no argument typed yet.
        // File mention palette: an unfinished "@…" token.
        let next: Palette
        if newText.hasPrefix("/") && !newText.dropFirst().contains(" ") {
            next = .command
        } else if fileMentionQuery != nil {
            next = .fileMention
        } else {
            next = .none
        }

        if next != palette { palette = next }
    }
}

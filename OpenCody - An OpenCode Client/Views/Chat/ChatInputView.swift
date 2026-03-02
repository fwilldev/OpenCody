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

    @State private var text: String = ""
    @State private var showCommandPalette = false
    @State private var showAttachmentPicker = false
    @State private var attachmentManager = AttachmentManager()

    init(viewModel: ChatViewModel, apiClient: APIClient? = nil, isInputFocused: FocusState<Bool>.Binding) {
        self.viewModel = viewModel
        self.apiClient = apiClient
        self.isInputFocused = isInputFocused
    }

    private var canSend: Bool {
        (!text.trimmingCharacters(in: .whitespaces).isEmpty || !attachmentManager.attachments.isEmpty)
            && !viewModel.isGenerating
    }

    /// The portion of the text after the leading "/" for palette filtering.
    private var commandQuery: String {
        guard text.hasPrefix("/") else { return "" }
        return String(text.dropFirst())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Command palette overlay — rendered above the input bar
            if showCommandPalette, let client = apiClient {
                CommandPaletteView(
                    apiClient: client,
                    query: commandQuery,
                    onSelect: { command in
                        text = command + " "
                        showCommandPalette = false
                    },
                    onDismiss: {
                        showCommandPalette = false
                    }
                )
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
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

                    // Text input with placeholder
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Message\u{2026}")
                                .foregroundStyle(Theme.Colors.silver)
                                .font(.body)
                                .padding(.horizontal, 8)
                                .padding(.top, 9)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .focused(isInputFocused)
                            .frame(minHeight: 36, maxHeight: 120)
                            .fixedSize(horizontal: false, vertical: true)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .foregroundStyle(Theme.Colors.cloud)
                            .font(.body)
                            .padding(.horizontal, 4)
                            .onChange(of: text) { _, newValue in
                                updatePaletteVisibility(for: newValue)
                            }
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                        let toSend = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let attachments = attachmentManager.attachments
                        text = ""
                        showCommandPalette = false
                        if showAttachmentPicker && attachments.isEmpty {
                            withAnimation { showAttachmentPicker = false }
                        }
                        let promptAttachments = attachments.map { a in
                            let base64 = a.data.base64EncodedString()
                            let dataURI = "data:\(a.mimeType);base64,\(base64)"
                            return PromptAttachment(mime: a.mimeType, filename: a.filename, url: dataURI)
                        }
                        attachmentManager.clearAll()
                        Task { await viewModel.sendPrompt(toSend, attachments: promptAttachments) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(canSend ? Theme.Colors.cyberBlue : Theme.Colors.smoke)
                            .font(.title3)
                            .frame(width: 32, height: 32)
                    }
                    .disabled(!canSend)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.carbon.opacity(0.96))
                .animation(.easeInOut(duration: 0.15), value: viewModel.isGenerating)
            }
            .zIndex(0)
        }
        .animation(.easeInOut(duration: 0.2), value: showCommandPalette)
        .animation(.easeInOut(duration: 0.2), value: showAttachmentPicker)
    }

    private func updatePaletteVisibility(for newText: String) {
        let shouldShow = newText.hasPrefix("/") && apiClient != nil
        if shouldShow != showCommandPalette {
            showCommandPalette = shouldShow
        }
    }
}

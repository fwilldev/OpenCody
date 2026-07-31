//
//  AttachmentPickerView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Horizontal scroll row of attachment thumbnails shown below the chat input.
/// Also provides photo + document picker triggers.
struct AttachmentPickerView: View {
    @Bindable var manager: AttachmentManager

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showDocumentPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !manager.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(manager.attachments) { attachment in
                            AttachmentThumbnail(attachment: attachment) {
                                manager.removeAttachment(id: attachment.id)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                }
                .background(Theme.Colors.graphite.opacity(0.6))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Picker toolbar row
            HStack(spacing: Theme.Spacing.sm) {
                // Photo picker
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.caption)
                        Text("Photo")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.Colors.silver)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.graphite)
                            .overlay(Capsule().stroke(Theme.Colors.border, lineWidth: 1))
                    )
                }
                .onChange(of: selectedPhotos) { _, newItems in
                    Task {
                        for item in newItems {
                            await manager.addImage(from: item)
                        }
                        selectedPhotos = []
                    }
                }

                // Document picker
                Button {
                    showDocumentPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc")
                            .font(.caption)
                        Text("File")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.Colors.silver)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.graphite)
                            .overlay(Capsule().stroke(Theme.Colors.border, lineWidth: 1))
                    )
                }
                .fileImporter(
                    isPresented: $showDocumentPicker,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        for url in urls {
                            manager.addFile(at: url)
                        }
                    case .failure(let err):
                        manager.error = err.localizedDescription
                    }
                }

                Spacer()

                if !manager.attachments.isEmpty {
                    Button {
                        withAnimation {
                            manager.clearAll()
                        }
                    } label: {
                        Text("Clear all")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.hotPink)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 8)
        }
        .animation(.easeInOut(duration: 0.2), value: manager.attachments.isEmpty)
    }
}

// MARK: - AttachmentThumbnail

private struct AttachmentThumbnail: View {
    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Preview
            if let preview = attachment.previewImage {
                preview
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                // Non-image file placeholder
                VStack(spacing: 4) {
                    Image(systemName: fileIcon(for: attachment.mimeType))
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.cyberBlue)
                    Text(attachment.filename)
                        .font(.system(size: 9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Colors.silver)
                }
                .frame(width: 64, height: 64)
                .background(Theme.Colors.graphite)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.cloud)
                    .background(
                        Circle()
                            .fill(Theme.Colors.carbon)
                            .frame(width: 14, height: 14)
                    )
            }
            .offset(x: 6, y: -6)
        }
        .frame(width: 64, height: 64)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.Colors.border, lineWidth: 1)
        )
    }

    private func fileIcon(for mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") { return "video" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType.contains("pdf") { return "doc.richtext" }
        if mimeType.contains("zip") || mimeType.contains("archive") { return "archivebox" }
        if mimeType.contains("text") { return "doc.text" }
        return "doc"
    }
}

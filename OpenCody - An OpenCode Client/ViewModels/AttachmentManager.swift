//
//  AttachmentManager.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Attachment Model

struct Attachment: Identifiable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let data: Data
    /// UIImage preview for images, nil for documents.
    let previewImage: Image?

    init(id: UUID = UUID(), filename: String, mimeType: String, data: Data, previewImage: Image? = nil) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.previewImage = previewImage
    }
}

// MARK: - AttachmentManager

@Observable
@MainActor
final class AttachmentManager {
    var attachments: [Attachment] = []
    var isPickingPhoto = false
    var error: String? = nil

    // MARK: - Add

    func addImage(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                error = "Could not load image data."
                return
            }
            let mimeType = item.supportedContentTypes.first.flatMap { UTType($0.identifier)?.preferredMIMEType } ?? "image/jpeg"
            let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? "jpg"
            let filename = "image_\(attachments.count + 1).\(ext)"

            // Build SwiftUI Image from data
            let previewImage: Image?
            #if canImport(UIKit)
            if let uiImg = UIImage(data: data) {
                previewImage = Image(uiImage: uiImg)
            } else {
                previewImage = nil
            }
            #else
            previewImage = nil
            #endif

            let attachment = Attachment(filename: filename, mimeType: mimeType, data: data, previewImage: previewImage)
            attachments.append(attachment)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addFile(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            error = "Could not read file: \(url.lastPathComponent)"
            return
        }

        let mimeType: String
        if let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType {
            mimeType = type
        } else {
            mimeType = "application/octet-stream"
        }

        let attachment = Attachment(filename: url.lastPathComponent, mimeType: mimeType, data: data, previewImage: nil)
        attachments.append(attachment)
    }

    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    func clearAll() {
        attachments.removeAll()
    }

    // MARK: - Upload

    /// Encode attachments as inline base64 data URIs for the message prompt.
    /// Returns array of strings suitable for attaching to a prompt.
    func encodedAttachments() -> [String] {
        attachments.map { attachment in
            let base64 = attachment.data.base64EncodedString()
            return "data:\(attachment.mimeType);base64,\(base64)"
        }
    }
}

//
//  FileExplorerView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI
import HighlightSwift
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Sheet presenting a file explorer for the session's project directory.
/// Lets the user browse directory trees and view file contents using
/// the OpenCode server's `/file` and `/file/content` endpoints.
struct FileExplorerView: View {
    let session: Session
    let apiClient: APIClient
    let showsCloseButton: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var pathStack: [String] = []
    @State private var nodes: [FileNode] = []
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var selectedFile: FileNode? = nil

    /// Current browsing path (root = ".")
    private var currentPath: String {
        pathStack.last ?? "."
    }

    /// Display name for the navigation title.
    private var displayTitle: String {
        if pathStack.isEmpty {
            return "File Explorer"
        }
        return URL(fileURLWithPath: currentPath).lastPathComponent
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.deepBlack.ignoresSafeArea()

                if isLoading && nodes.isEmpty {
                    ProgressView("Loading…")
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
                        Button("Retry") {
                            Task { await loadDirectory() }
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Colors.cyberBlue)
                        .padding(.top, Theme.Spacing.sm)
                    }
                    .padding()
                } else if nodes.isEmpty {
                    EmptyStateView(
                        systemImage: "folder",
                        title: "Empty Directory",
                        message: "This directory contains no files."
                    )
                } else {
                    directoryList
                }
            }
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(Theme.Colors.silver)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !pathStack.isEmpty {
                        Button {
                            pathStack.removeLast()
                            Task { await loadDirectory() }
                        } label: {
                            Image(systemName: "arrow.up.doc")
                                .foregroundStyle(Theme.Colors.silver)
                        }
                    }
                }
            }
        }
        .presentationBackground(Theme.Colors.carbon)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $selectedFile) { file in
            FileContentView(filePath: file.path, apiClient: apiClient, directory: session.directory)
        }
        .task {
            await loadDirectory()
        }
    }

    init(session: Session, apiClient: APIClient, showsCloseButton: Bool = true) {
        self.session = session
        self.apiClient = apiClient
        self.showsCloseButton = showsCloseButton
    }

    // MARK: - Directory List

    private var directoryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Breadcrumb
                if !pathStack.isEmpty {
                    breadcrumb
                }

                ForEach(sortedNodes) { node in
                    Button {
                        handleTap(node)
                    } label: {
                        FileNodeRow(node: node)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .overlay(Color.white.opacity(0.06))
                }
            }
        }
    }

    /// Directories first, then files. Alphabetical within each group.
    private var sortedNodes: [FileNode] {
        let dirs = nodes.filter { $0.type == .directory }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let files = nodes.filter { $0.type == .file }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return dirs + files
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    pathStack.removeAll()
                    Task { await loadDirectory() }
                } label: {
                    Image(systemName: "house.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.cyberBlue)
                }

                ForEach(Array(pathStack.enumerated()), id: \.offset) { index, segment in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.Colors.smoke)

                    Button {
                        pathStack = Array(pathStack.prefix(index + 1))
                        Task { await loadDirectory() }
                    } label: {
                        Text(URL(fileURLWithPath: segment).lastPathComponent)
                            .font(.system(.caption2, design: .monospaced).weight(.medium))
                            .foregroundStyle(index == pathStack.count - 1 ? Theme.Colors.cloud : Theme.Colors.cyberBlue)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(Theme.Colors.graphite)
    }

    // MARK: - Actions

    private func handleTap(_ node: FileNode) {
        if node.type == .directory {
            pathStack.append(node.path)
            Task { await loadDirectory() }
        } else {
            selectedFile = node
        }
    }

    private func loadDirectory() async {
        isLoading = true
        error = nil
        do {
            let api = FileAPI(client: apiClient)
#if DEBUG
            print("[FileExplorer] session.directory=\(session.directory)")
            print("[FileExplorer] currentPath=\(currentPath)")
#endif
            nodes = try await api.list(path: currentPath, directory: session.directory)
#if DEBUG
            print("[FileExplorer] loaded \(nodes.count) nodes")
            for node in nodes.prefix(50) {
                print("[FileExplorer] node name=\(node.name) path=\(node.path) type=\(node.type.rawValue)")
            }
#endif
        } catch {
#if DEBUG
            print("[FileExplorer] ERROR: \(error)")
#endif
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - FileNodeRow

private struct FileNodeRow: View {
    let node: FileNode

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(node.ignored ? Theme.Colors.smoke : Theme.Colors.cloud)
                    .lineLimit(1)

                if node.ignored {
                    Text("ignored")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.smoke)
                }
            }

            Spacer()

            if node.type == .directory {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.smoke)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var icon: String {
        if node.type == .directory {
            return "folder.fill"
        }
        return fileIcon(for: node.name)
    }

    private var iconColor: Color {
        if node.ignored {
            return Theme.Colors.smoke
        }
        if node.type == .directory {
            return Theme.Colors.cyberBlue
        }
        return fileIconColor(for: node.name)
    }

    private func fileIcon(for name: String) -> String {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        switch ext {
        case "swift", "ts", "tsx", "js", "jsx", "py", "go", "rs", "java", "kt", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml", "xml", "plist":
            return "doc.text"
        case "md", "txt", "rtf":
            return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "ico":
            return "photo"
        case "css", "scss", "less":
            return "paintbrush"
        case "lock":
            return "lock.fill"
        default:
            return "doc"
        }
    }

    private func fileIconColor(for name: String) -> Color {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        switch ext {
        case "swift":
            return Theme.Colors.neonOrange
        case "ts", "tsx":
            return Theme.Colors.cyberBlue
        case "js", "jsx":
            return Color(hex: "F7DF1E")
        case "json", "yaml", "yml", "toml", "xml", "plist":
            return Theme.Colors.electricPurple
        case "md", "txt":
            return Theme.Colors.silver
        case "css", "scss", "less":
            return Theme.Colors.hotPink
        default:
            return Theme.Colors.silver
        }
    }
}

// MARK: - FileContentView

/// Sheet for displaying the content of a single file with syntax highlighting.
private struct FileContentView: View {
    let filePath: String
    let apiClient: APIClient
    let directory: String

    @Environment(\.dismiss) private var dismiss
    @State private var content: FileContent? = nil
    @State private var isLoading = true
    @State private var error: String? = nil

    private var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    /// Determine the highlight language from the file extension.
    private var highlightLanguage: HighlightLanguage? {
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "ts": return .typeScript
        case "tsx": return .typeScript
        case "js": return .javaScript
        case "jsx": return .javaScript
        case "py": return .python
        case "go": return .go
        case "rs": return .rust
        case "java": return .java
        case "kt", "kts": return .kotlin
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp": return .cPlusPlus
        case "cs": return .cSharp
        case "rb": return .ruby
        case "php": return .php
        case "html", "htm": return .html
        case "css": return .css
        case "scss": return .scss
        case "less": return .less
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "xml", "plist": return .html
        case "sql": return .sql
        case "sh", "bash", "zsh": return .bash
        case "md", "markdown": return .markdown
        case "toml": return .toml
        case "dockerfile": return .dockerfile
        case "r": return .r
        case "lua": return .lua
        case "perl", "pl": return .perl
        case "scala": return .scala
        case "dart": return .dart
        case "ex", "exs": return .elixir
        case "erl": return .erlang
        case "hs": return .haskell
        case "m": return .objectiveC
        default: return nil
        }
    }

    private var fileExtension: String {
        URL(fileURLWithPath: filePath).pathExtension.lowercased()
    }

    private var isImageFile: Bool {
        if let mime = content?.mimeType?.lowercased(), mime.hasPrefix("image/") {
            return true
        }
        if let type = UTType(filenameExtension: fileExtension) {
            return type.conforms(to: .image)
        }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.deepBlack.ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading file…")
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
                } else if let content {
                    if isImageFile, let data = fileData(from: content) {
                        imageContentView(data: data)
                    } else if content.type == .binary {
                        EmptyStateView(
                            systemImage: "doc.zipper",
                            title: "Binary File",
                            message: "This file cannot be displayed as text."
                        )
                    } else {
                        highlightedContentView(content)
                    }
                }
            }
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.Colors.silver)
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: Theme.Spacing.md) {
                        if let content, content.type != .binary {
                            let lineCount = content.content.components(separatedBy: "\n").count
                            Text("\(lineCount) lines")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.silver)
                        }

                        if content != nil {
                            Button {
                                saveFileToDevice()
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                                    .foregroundStyle(Theme.Colors.cyberBlue)
                            }
                        }
                    }
                }
            }
        }
        .presentationBackground(Theme.Colors.carbon)
        .task {
            await loadContent()
        }
    }

    /// Syntax-highlighted file content view using HighlightSwift's CodeText.
    private func highlightedContentView(_ content: FileContent) -> some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 0) {
                // Line numbers column
                let lines = content.content.components(separatedBy: "\n")
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(0..<lines.count, id: \.self) { index in
                        Text("\(index + 1)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.Colors.smoke)
                            .frame(height: 18.5)
                    }
                }
                .padding(.leading, Theme.Spacing.sm)
                .padding(.trailing, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.deepBlack.opacity(0.5))

                // Highlighted code content
                codeTextView(content.content)
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.trailing, Theme.Spacing.md)
            }
        }
        .background(Theme.Colors.carbon)
    }

    @ViewBuilder
    private func imageContentView(data: Data) -> some View {
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.carbon)
        } else {
            EmptyStateView(
                systemImage: "photo",
                title: "Image Preview Failed",
                message: "Unable to decode this image file."
            )
        }
        #else
        EmptyStateView(
            systemImage: "photo",
            title: "Image Preview Unavailable",
            message: "Image previews are not supported on this platform."
        )
        #endif
    }

    @ViewBuilder
    private func codeTextView(_ code: String) -> some View {
        if let language = highlightLanguage {
            CodeText(code)
                .highlightLanguage(language)
                .codeTextColors(.theme(.atomOne))
                .font(.system(size: 12, design: .monospaced))
        } else {
            CodeText(code)
                .codeTextColors(.theme(.atomOne))
                .font(.system(size: 12, design: .monospaced))
        }
    }

    // MARK: - File Saving

    private func saveFileToDevice() {
        guard let content else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            if let data = fileData(from: content) {
                try data.write(to: fileURL, options: .atomic)
            } else {
                try content.content.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            presentShareSheet(for: fileURL)
        } catch {
            self.error = "Failed to prepare file for saving: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func presentShareSheet(for url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController,
           let root = rootViewController() {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1, height: 1)
        }
        rootViewController()?.present(controller, animated: true)
    }

    @MainActor
    private func rootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return nil
        }
        return scene.windows.first?.rootViewController
    }

    private func fileData(from content: FileContent) -> Data? {
        if let encoded = content.encoding?.lowercased(), encoded.contains("base64") {
            return decodeBase64Payload(content.content)
        }
        if content.content.hasPrefix("data:") {
            return decodeBase64Payload(content.content)
        }
        if content.type == .binary {
            return decodeBase64Payload(content.content)
        }
        if isImageFile {
            return decodeBase64Payload(content.content) ?? content.content.data(using: .utf8)
        }
        return content.content.data(using: .utf8)
    }

    private func decodeBase64Payload(_ value: String) -> Data? {
        let payload: String
        if let commaIndex = value.firstIndex(of: ",") {
            payload = String(value[value.index(after: commaIndex)...])
        } else {
            payload = value
        }
        let sanitized = payload.replacingOccurrences(of: "\n", with: "")
        return Data(base64Encoded: sanitized)
    }

    private func loadContent() async {
        isLoading = true
        error = nil
        do {
            let api = FileAPI(client: apiClient)
            content = try await api.content(path: filePath, directory: directory)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - ShareSheet

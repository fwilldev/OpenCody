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
/// Lets the user browse directory trees, search the project by file name, view file
/// contents, and reference a file in the chat input — using the OpenCode server's
/// `/file`, `/file/content` and `/find/file` endpoints.
struct FileExplorerView: View {
    let session: Session
    let apiClient: APIClient
    let showsCloseButton: Bool
    /// Called with a project-relative path when the user wants to reference a file in
    /// the message they're composing. `nil` hides the reference affordances.
    let onReference: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var pathStack: [String] = []
    @State private var nodes: [FileNode] = []
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var selectedFile: FileNode? = nil

    // Search state
    @State private var searchQuery: String = ""
    @State private var searchResults: [String] = []
    @State private var isSearching = false
    @State private var searchError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    /// Path of the file most recently referenced, shown as a brief confirmation.
    @State private var referenceNotice: String? = nil

    /// Current browsing path (root = ".")
    private var currentPath: String {
        pathStack.last ?? "."
    }

    /// Whether the view is showing search results rather than the browsed directory.
    private var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
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
            ZStack(alignment: .bottom) {
                Theme.Colors.deepBlack.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchField

                    Divider()
                        .overlay(Theme.Colors.hairline)

                    if isSearchActive {
                        searchContent
                    } else {
                        browseContent
                    }
                }

                if let notice = referenceNotice {
                    referenceToast(notice)
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
                    if !pathStack.isEmpty && !isSearchActive {
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
            FileContentView(
                filePath: file.path,
                apiClient: apiClient,
                directory: session.directory,
                onReference: onReference.map { handler in
                    { path in
                        handler(path)
                        showReferenceNotice(for: path)
                    }
                }
            )
        }
        .task {
            await loadDirectory()
        }
    }

    init(
        session: Session,
        apiClient: APIClient,
        showsCloseButton: Bool = true,
        onReference: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.apiClient = apiClient
        self.showsCloseButton = showsCloseButton
        self.onReference = onReference
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(Theme.Colors.smoke)

            TextField("Search files…", text: $searchQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Theme.Colors.cloud)
                .submitLabel(.search)
                .onChange(of: searchQuery) { _, newValue in
                    debounceSearch(query: newValue)
                }

            if isSearching {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(Theme.Colors.cyberBlue)
            } else if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.smoke)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.graphite)
    }

    private func debounceSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }
        searchTask = Task {
            // Debounce so a fast typist doesn't fire a request per keystroke.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await runSearch(query: trimmed)
        }
    }

    private func runSearch(query: String) async {
        isSearching = true
        searchError = nil
        do {
            let api = FileAPI(client: apiClient)
            searchResults = try await api.findFiles(
                query: query,
                directory: session.directory,
                limit: 100
            )
        } catch {
            if !Task.isCancelled {
                searchError = error.localizedDescription
                searchResults = []
            }
        }
        isSearching = false
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchContent: some View {
        if let err = searchError {
            messageState(icon: "exclamationmark.triangle", tint: Theme.Colors.hotPink, text: err)
        } else if searchResults.isEmpty {
            if isSearching {
                messageState(icon: "magnifyingglass", tint: Theme.Colors.smoke, text: "Searching…")
            } else {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No Matches",
                    message: "No files match “\(searchQuery)”."
                )
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(searchResults, id: \.self) { path in
                        SearchResultRow(
                            path: path,
                            onTap: { handleSearchTap(path) },
                            onReference: onReference == nil ? nil : { reference(path: path) }
                        )

                        Divider()
                            .overlay(Theme.Colors.hairline)
                    }
                }
            }
        }
    }

    /// Search results are plain paths; directories come back with a trailing slash.
    private func handleSearchTap(_ path: String) {
        if path.hasSuffix("/") {
            searchQuery = ""
            pathStack = [path]
            Task { await loadDirectory() }
        } else {
            selectedFile = FileNode(
                name: URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                absolute: session.directory + "/" + path,
                type: .file,
                ignored: false
            )
        }
    }

    // MARK: - Directory Browsing

    @ViewBuilder
    private var browseContent: some View {
        if isLoading && nodes.isEmpty {
            ProgressView("Loading…")
                .tint(Theme.Colors.cyberBlue)
                .foregroundStyle(Theme.Colors.silver)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var directoryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Breadcrumb
                if !pathStack.isEmpty {
                    breadcrumb
                }

                ForEach(sortedNodes) { node in
                    FileNodeRow(
                        node: node,
                        onTap: { handleTap(node) },
                        onReference: (onReference == nil || node.type == .directory)
                            ? nil
                            : { reference(path: node.path) }
                    )

                    Divider()
                        .overlay(Theme.Colors.hairline)
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

    // MARK: - Shared Pieces

    private func messageState(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.Colors.silver)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func referenceToast(_ path: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Colors.neonGreen)
            Text("Added \(URL(fileURLWithPath: path).lastPathComponent) to your message")
                .font(.caption)
                .foregroundStyle(Theme.Colors.cloud)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Theme.Colors.glassFill))
                .overlay(Capsule().stroke(Theme.Colors.border, lineWidth: 1))
        )
        .padding(.bottom, Theme.Spacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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

    private func reference(path: String) {
        onReference?(path)
        showReferenceNotice(for: path)
    }

    private func showReferenceNotice(for path: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            referenceNotice = path
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeIn(duration: 0.2)) {
                referenceNotice = nil
            }
        }
    }

    private func loadDirectory() async {
        isLoading = true
        error = nil
        do {
            let api = FileAPI(client: apiClient)
            nodes = try await api.list(path: currentPath, directory: session.directory)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - FileNodeRow

private struct FileNodeRow: View {
    let node: FileNode
    let onTap: () -> Void
    /// `nil` when referencing isn't available in this context.
    let onReference: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
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
                .padding(.leading, Theme.Spacing.md)
                .padding(.trailing, onReference == nil ? Theme.Spacing.md : Theme.Spacing.xs)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onReference {
                ReferenceButton(action: onReference)
            }
        }
    }

    private var icon: String {
        if node.type == .directory {
            return "folder.fill"
        }
        return FileIconStyle.symbol(for: node.name)
    }

    private var iconColor: Color {
        if node.ignored {
            return Theme.Colors.smoke
        }
        if node.type == .directory {
            return Theme.Colors.cyberBlue
        }
        return FileIconStyle.color(for: node.name)
    }
}

// MARK: - SearchResultRow

/// Row for a `/find/file` hit — a bare project-relative path.
private struct SearchResultRow: View {
    let path: String
    let onTap: () -> Void
    let onReference: (() -> Void)?

    private var isDirectory: Bool { path.hasSuffix("/") }

    private var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private var parentPath: String {
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent().relativePath
        return dir == "." ? "" : dir + "/"
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: isDirectory ? "folder.fill" : FileIconStyle.symbol(for: fileName))
                        .font(.body)
                        .foregroundStyle(isDirectory ? Theme.Colors.cyberBlue : FileIconStyle.color(for: fileName))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileName)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(Theme.Colors.cloud)
                            .lineLimit(1)

                        if !parentPath.isEmpty {
                            Text(parentPath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.Colors.smoke)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }

                    Spacer()
                }
                .padding(.leading, Theme.Spacing.md)
                .padding(.trailing, onReference == nil ? Theme.Spacing.md : Theme.Spacing.xs)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onReference, !isDirectory {
                ReferenceButton(action: onReference)
            }
        }
    }
}

// MARK: - ReferenceButton

/// Trailing "@" button that pulls a file into the chat draft.
private struct ReferenceButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "at")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.cyberBlue)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, Theme.Spacing.xs)
        .accessibilityLabel("Reference in message")
    }
}

// MARK: - FileIconStyle

/// Icon and tint for a file name, shared by the explorer's row types.
enum FileIconStyle {
    static func symbol(for name: String) -> String {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
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

    static func color(for name: String) -> Color {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "swift":
            return Theme.Colors.neonOrange
        case "ts", "tsx":
            return Theme.Colors.cyberBlue
        case "js", "jsx":
            return Theme.Colors.javascriptYellow
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
    /// Called to reference this file in the chat draft. `nil` hides the action.
    let onReference: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var content: FileContent? = nil
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var didReference = false

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

                        if let onReference {
                            Button {
                                onReference(filePath)
                                didReference = true
                                dismiss()
                            } label: {
                                Image(systemName: didReference ? "checkmark" : "at")
                                    .foregroundStyle(Theme.Colors.cyberBlue)
                            }
                            .accessibilityLabel("Reference in message")
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

    // MARK: - Content Decoding

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

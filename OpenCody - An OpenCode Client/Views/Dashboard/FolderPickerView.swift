//
//  FolderPickerView.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import SwiftUI

// MARK: - FolderPickerView

/// A searchable project browser that lists all known OpenCode projects.
/// Uses `FileAPI.listProjects()` to fetch projects from the server.
struct FolderPickerView: View {
    let apiClient: APIClient
    let onSelect: @MainActor (String) -> Void

    private enum Mode: String, CaseIterable, Identifiable {
        case projects = "Projects"
        case folders = "Folders"

        var id: String { rawValue }
    }

    // MARK: - State

    @State private var searchText: String = ""
    @State private var projects: [Project] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var selectedPath: String?

    @State private var mode: Mode = .projects
    @State private var browsePath: String?
    @State private var browseRootName: String?
    @State private var browseRootAbsolute: String?
    @State private var directories: [FileNode] = []
    @State private var isLoadingDirectories: Bool = false
    @State private var directoriesError: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            modePicker

            // Breadcrumb / path context
            if let selectedPath {
                breadcrumbBar(path: selectedPath)
            }

            // Content
            contentView
        }
        .background(Theme.Colors.deepBlack)
        .task {
            await loadProjects()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.silver)
                .font(Theme.Fonts.body)

            TextField("Search projects...", text: $searchText)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.cloud)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(Theme.Colors.smoke)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.md)
        .glassCard(radius: Theme.Radius.small)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Breadcrumb Bar

    private func breadcrumbBar(path: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.cyberBlue)

            Text(path)
                .font(Theme.Fonts.codeCaption)
                .foregroundStyle(Theme.Colors.cyberBlue)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch mode {
        case .projects:
            if isLoading {
                loadingView
            } else if let errorMessage {
                errorView(errorMessage)
            } else if filteredProjects.isEmpty {
                emptyView
            } else {
                projectList
            }
        case .folders:
            folderBrowser
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.cyberBlue)
                .scaleEffect(1.2)

            Text("Loading projects...")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Error State

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(Theme.Colors.neonOrange)

            Text("Failed to load projects")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.cloud)

            Text(message)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)

            Button {
                Task {
                    await loadProjects()
                }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.cyberBlue)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .glassCard(radius: Theme.Radius.button)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        EmptyStateView(
            systemImage: "folder.badge.questionmark",
            title: "No projects found",
            message: searchText.isEmpty
                ? "No projects are known to this server yet. Open a project in OpenCode first."
                : "No projects match \"\(searchText)\". Try a different search term."
        )
    }

    // MARK: - Folder Browser

    private var folderBrowser: some View {
        VStack(spacing: 0) {
            if browseRootAbsolute == nil {
                folderRootPicker
            } else {
                if let path = currentBrowsePath {
                    folderBreadcrumb(path: path)
                }

                if isLoadingDirectories {
                    loadingDirectoriesView
                } else if let directoriesError {
                    directoryErrorView(directoriesError)
                } else {
                    directoryList
                }
            }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(Mode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private func folderBreadcrumb(path: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "folder")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.cyberBlue)
            Text(displayPath(for: path))
                .font(Theme.Fonts.codeCaption)
                .foregroundStyle(Theme.Colors.cyberBlue)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            if let parent = parentRelativePath(from: path) {
                Button("Up") {
                    browsePath = parent
                    Task { await loadDirectory(path: parent) }
                }
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
            }
            Button("Select") {
                if let absolute = currentAbsolutePath {
                    selectedPath = absolute
                    onSelect(absolute)
                }
            }
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.cyberBlue)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingDirectoriesView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.cyberBlue)
                .scaleEffect(1.2)
            Text("Loading folders...")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
    }

    private func directoryErrorView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(Theme.Colors.neonOrange)

            Text("Failed to load folders")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.cloud)

            Text(message)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)

            Button {
                if let browsePath {
                    Task { await loadDirectory(path: browsePath) }
                }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.cyberBlue)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .glassCard(radius: Theme.Radius.button)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
    }

    private var directoryList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(filteredDirectories) { node in
                    Button {
                        let nextPath = normalizeRelativePath(node.path)
                        browsePath = nextPath
                        Task { await loadDirectory(path: nextPath) }
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "folder")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.Colors.cyberBlue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.name)
                                    .font(Theme.Fonts.body)
                                    .foregroundStyle(Theme.Colors.cloud)
                                    .lineLimit(1)
                                Text(node.absolute)
                                    .font(Theme.Fonts.codeCaption)
                                    .foregroundStyle(Theme.Colors.silver)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.smoke)
                        }
                        .padding(Theme.Spacing.md)
                        .glassCard()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private var folderRootPicker: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Select a project to browse")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)

            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(filteredProjects) { project in
                        Button {
                            startBrowsing(project: project)
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "folder")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Theme.Colors.cyberBlue)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(projectName(from: project.worktree))
                                        .font(Theme.Fonts.body)
                                        .foregroundStyle(Theme.Colors.cloud)
                                        .lineLimit(1)
                                    Text(project.worktree)
                                        .font(Theme.Fonts.codeCaption)
                                        .foregroundStyle(Theme.Colors.silver)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.smoke)
                            }
                            .padding(Theme.Spacing.md)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Project List

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(filteredProjects) { project in
                    projectRow(project)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private func projectRow(_ project: Project) -> some View {
        Button {
            selectedPath = project.worktree
            onSelect(project.worktree)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: project.vcs != nil ? "arrow.triangle.branch" : "folder")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Colors.cyberBlue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(projectName(from: project.worktree))
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Colors.cloud)
                        .lineLimit(1)

                    Text(project.worktree)
                        .font(Theme.Fonts.codeCaption)
                        .foregroundStyle(Theme.Colors.silver)
                        .lineLimit(1)
                        .truncationMode(.head)

                    if let vcs = project.vcs {
                        Text(vcs.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.Colors.neonGreen.opacity(0.8))
                            .tracking(0.8)
                    }
                }

                Spacer()

                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Theme.Colors.smoke)
            }
            .padding(Theme.Spacing.md)
            .glassCard()
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(
                        selectedPath == project.worktree
                            ? Theme.Colors.cyberBlue.opacity(0.4)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtered Projects

    private var filteredProjects: [Project] {
        guard !searchText.isEmpty else { return projects }
        let query = searchText.lowercased()
        return projects.filter {
            $0.worktree.lowercased().contains(query)
        }
    }

    private var filteredDirectories: [FileNode] {
        let dirs = directories.filter { $0.type == .directory }
        guard !searchText.isEmpty else { return dirs }
        let query = searchText.lowercased()
        return dirs.filter { $0.name.lowercased().contains(query) || $0.absolute.lowercased().contains(query) }
    }

    // MARK: - Helpers

    private func projectName(from worktree: String) -> String {
        URL(fileURLWithPath: worktree).lastPathComponent
    }

    // MARK: - Data Loading

    private func loadProjects() async {
        isLoading = true
        errorMessage = nil

        let fileAPI = FileAPI(client: apiClient)

        do {
            projects = try await fileAPI.listProjects()
            isLoading = false
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadDirectory(path: String) async {
        isLoadingDirectories = true
        directoriesError = nil

        let fileAPI = FileAPI(client: apiClient)
        do {
            directories = try await fileAPI.list(path: path, directory: browseRootAbsolute)
            isLoadingDirectories = false
        } catch {
            if !Task.isCancelled {
                directoriesError = error.localizedDescription
                isLoadingDirectories = false
            }
        }
    }

    private var currentBrowsePath: String? {
        browsePath ?? "."
    }

    private var currentAbsolutePath: String? {
        guard let rootName = browseRootName,
              let rootAbsolute = browseRootAbsolute,
              let path = currentBrowsePath else {
            return nil
        }
        let sanitized = normalizeRelativePath(path)
        if sanitized == "." {
            return rootAbsolute
        }
        return rootAbsolute + "/" + sanitized
    }

    private func parentRelativePath(from path: String) -> String? {
        let sanitized = normalizeRelativePath(path)
        if sanitized == "." { return nil }
        let parent = (sanitized as NSString).deletingLastPathComponent
        return parent.isEmpty || parent == "." ? "." : parent
    }

    private func startBrowsing(project: Project) {
        let rootName = projectName(from: project.worktree)
        browseRootName = rootName
        browseRootAbsolute = project.worktree
        browsePath = "."
        Task { await loadDirectory(path: ".") }
    }

    private func normalizeRelativePath(_ path: String) -> String {
        let sanitized = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        return sanitized.isEmpty ? "." : sanitized
    }

    private func displayPath(for path: String) -> String {
        let sanitized = normalizeRelativePath(path)
        let rootName = browseRootName ?? ""
        if sanitized == "." { return rootName.isEmpty ? "." : rootName }
        return rootName.isEmpty ? sanitized : "\(rootName)/\(sanitized)"
    }
}

import AppKit
import Foundation
import SwiftUI

struct RecentWorkspace: Identifiable, Equatable {
    let url: URL
    let bookmarkData: Data

    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }
    var displayPath: String { url.path }
}

enum ReaderPaneID: String, Sendable {
    case primary
    case reference

    var otherPane: ReaderPaneID {
        self == .primary ? .reference : .primary
    }
}

private enum ReaderFileOperationError: LocalizedError {
    case emptyName
    case nameContainsSeparator
    case targetOutsideWorkspace
    case targetAlreadyExists
    case workspaceUnavailable
    case bookmarkCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyName: L10n.string(.errorEmptyName)
        case .nameContainsSeparator: L10n.string(.errorNameSeparator)
        case .targetOutsideWorkspace: L10n.string(.errorRenameOutside)
        case .targetAlreadyExists: L10n.string(.errorTargetExists)
        case .workspaceUnavailable: L10n.string(.errorRecentUnavailable)
        case .bookmarkCreationFailed(let message): L10n.format(.errorBookmarkSave, message)
        }
    }
}

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var rootNodes: [FileNode] = []
    @Published private(set) var rootIsLoading = false

    @Published private(set) var selectedURL: URL?
    @Published private(set) var documentState: ReaderDocumentState = .welcome
    @Published var scrollRequest: ScrollRequest?
    @Published var selectedOutlineID: UUID?

    @Published private(set) var referenceURL: URL?
    @Published private(set) var referenceDocumentState: ReaderDocumentState?
    @Published var referenceScrollRequest: ScrollRequest?
    @Published var referenceSelectedOutlineID: UUID?
    @Published var activePane: ReaderPaneID = .primary

    @Published var outlineIsVisible = true
    @Published private(set) var appAppearance: AppAppearance
    @Published private(set) var markdownStyle: MarkdownStyle
    @Published private(set) var systemColorScheme: ColorScheme
    @Published private(set) var recentWorkspaces: [RecentWorkspace] = []
    @Published private(set) var fileOperationError: String?

    private var workspaceAccessSession: WorkspaceAccessSession?
    private var rootTask: Task<Void, Never>?
    private var documentTask: Task<Void, Never>?
    private var referenceDocumentTask: Task<Void, Never>?
    private var workspaceGeneration = UUID()
    private var treeGeneration = UUID()
    private var documentGeneration = UUID()
    private var referenceDocumentGeneration = UUID()
    private var debugArgumentsHandled = false

    private static let recentWorkspaceBookmarksKey = "recentWorkspaceBookmarks.v1"
    private static let readerThemeKey = "readerTheme.v2"
    private static let maximumRecentWorkspaceCount = 8

    init() {
        let defaults = UserDefaults.standard
        let legacyTheme = defaults.string(forKey: "readerTheme")
        systemColorScheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark
            : .light

        let savedTheme = defaults.string(forKey: Self.readerThemeKey)
            ?? defaults.string(forKey: "markdownStyle")
            ?? legacyTheme
        markdownStyle = MarkdownStyle.migrated(from: savedTheme) ?? .newsprint

        if
            let savedAppearance = defaults.string(forKey: "appAppearance"),
            let restored = AppAppearance(rawValue: savedAppearance)
        {
            appAppearance = restored
        } else if legacyTheme == "dark" || legacyTheme == "graphite" {
            appAppearance = .dark
        } else if legacyTheme != nil {
            appAppearance = .light
        } else {
            appAppearance = .system
        }

        restoreRecentWorkspaces()
        if let mostRecentWorkspace = recentWorkspaces.first {
            openRecentWorkspace(mostRecentWorkspace, reportFailure: false)
        }
    }

    deinit {
        rootTask?.cancel()
        documentTask?.cancel()
        referenceDocumentTask?.cancel()
    }

    var rootName: String { rootURL?.lastPathComponent ?? L10n.string(.workspaceNotOpened) }
    var hasSecondPane: Bool { referenceDocumentState != nil }
    var currentTitle: String { currentTitle(for: activePane) }
    var resolvedTheme: ResolvedReaderTheme {
        ResolvedReaderTheme(
            style: markdownStyle,
            isDark: appAppearance.resolvesDark(systemColorScheme: systemColorScheme)
        )
    }

    var canReloadActiveDocument: Bool {
        selectedURL(for: activePane).map {
            FileNode.previewableExtensions.contains($0.pathExtension.lowercased())
        } ?? false
    }

    func currentTitle(for pane: ReaderPaneID) -> String {
        switch documentState(for: pane) {
        case .loaded(let url, _), .loading(let url), .unsupported(let url): url.lastPathComponent
        case .failed(let url, _): url?.lastPathComponent ?? L10n.string(.documentLoadFailed)
        case .welcome: L10n.string(.appName)
        }
    }

    func documentState(for pane: ReaderPaneID) -> ReaderDocumentState {
        switch pane {
        case .primary: documentState
        case .reference: referenceDocumentState ?? .welcome
        }
    }

    func selectedURL(for pane: ReaderPaneID) -> URL? {
        pane == .primary ? selectedURL : referenceURL
    }

    func scrollRequest(for pane: ReaderPaneID) -> ScrollRequest? {
        pane == .primary ? scrollRequest : referenceScrollRequest
    }

    func selectedOutlineID(for pane: ReaderPaneID) -> UUID? {
        pane == .primary ? selectedOutlineID : referenceSelectedOutlineID
    }

    func outlineItems(for pane: ReaderPaneID) -> [OutlineItem] {
        if case .loaded(_, let rendered) = documentState(for: pane) {
            return rendered.outline
        }
        return []
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.string(.folderPickerTitle)
        panel.message = L10n.string(.folderPickerMessage)
        panel.prompt = L10n.string(.folderPickerPrompt)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWorkspace(url)
    }

    func openDebugArgumentsIfNeeded() {
        guard !debugArgumentsHandled else { return }
        debugArgumentsHandled = true
        let arguments = CommandLine.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "--open-file"),
            arguments.indices.contains(flagIndex + 1)
        else { return }

        let rawPath = arguments[flagIndex + 1]
        let fileURL = URL(
            fileURLWithPath: rawPath,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        ).standardizedFileURL
        let anchor = arguments.firstIndex(of: "--open-anchor").flatMap { anchorIndex in
            arguments.indices.contains(anchorIndex + 1) ? arguments[anchorIndex + 1] : nil
        }
        openWorkspace(fileURL.deletingLastPathComponent())
        loadDocument(at: fileURL, anchor: anchor, in: .primary)

        if
            let referenceIndex = arguments.firstIndex(of: "--reference-file"),
            arguments.indices.contains(referenceIndex + 1)
        {
            let referenceURL = URL(
                fileURLWithPath: arguments[referenceIndex + 1],
                relativeTo: URL(
                    fileURLWithPath: FileManager.default.currentDirectoryPath,
                    isDirectory: true
                )
            ).standardizedFileURL
            loadDocument(at: referenceURL, in: .reference)
            activatePane(.reference)
        }
    }

    func openWorkspace(_ url: URL) {
        openWorkspace(url, bookmarkData: nil)
    }

    private func openWorkspace(_ url: URL, bookmarkData: Data?) {
        rootTask?.cancel()
        documentTask?.cancel()
        referenceDocumentTask?.cancel()

        let accessSession = WorkspaceAccessSession(url: url)
        workspaceAccessSession = accessSession
        let workspaceURL = accessSession.rootURL
        rootURL = workspaceURL
        rootNodes = []
        rootIsLoading = true
        selectedURL = nil
        documentState = .welcome
        scrollRequest = nil
        selectedOutlineID = nil
        referenceURL = nil
        referenceDocumentState = nil
        referenceScrollRequest = nil
        referenceSelectedOutlineID = nil
        activePane = .primary
        workspaceGeneration = UUID()
        documentGeneration = UUID()
        referenceDocumentGeneration = UUID()
        fileOperationError = nil

        rememberWorkspace(url, existingBookmarkData: bookmarkData)
        rescanWorkspace()
    }

    func rescanWorkspace(revealing revealingURL: URL? = nil) {
        guard let rootURL, let accessSession = workspaceAccessSession else { return }
        rootTask?.cancel()
        let expandedDirectories = Self.expandedDirectoryURLs(in: rootNodes)
        FileTreeMerger.prepareForRefresh(rootNodes)
        let shouldShowInitialLoading = rootNodes.isEmpty
        if rootIsLoading != shouldShowInitialLoading {
            rootIsLoading = shouldShowInitialLoading
        }

        let workspaceToken = workspaceGeneration
        let treeToken = UUID()
        treeGeneration = treeToken
        let directoriesToReveal = Self.directoryURLsToExpand(
            revealing: revealingURL,
            inside: rootURL
        )
        let directoriesToRefresh = Self.uniqueDirectoryURLs(
            expandedDirectories + directoriesToReveal
        )
        let forcedExpandedPaths = Set(
            directoriesToReveal.map { $0.standardizedFileURL.path }
        )
        rootTask = Task { [weak self, accessSession] in
            defer { _ = accessSession }
            do {
                let entries = try await FileSystemService.entries(at: rootURL, inside: rootURL)
                var expandedEntries: [String: [FileEntry]] = [:]
                for directoryURL in directoriesToRefresh {
                    try Task.checkCancellation()
                    do {
                        expandedEntries[directoryURL.standardizedFileURL.path] = try await FileSystemService.entries(
                            at: directoryURL,
                            inside: rootURL
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // 根目录结果仍可移除已经不存在的节点；单个展开目录读取失败时
                        // 保留其当前子树，避免一次局部权限或 IO 故障清空整棵目录树。
                        continue
                    }
                }
                try Task.checkCancellation()
                guard
                    let self,
                    self.workspaceGeneration == workspaceToken,
                    self.treeGeneration == treeToken
                else { return }
                let mergedNodes = FileTreeMerger.merge(
                    entries: entries,
                    reusing: self.rootNodes,
                    refreshedEntriesByDirectory: expandedEntries,
                    forcedExpandedPaths: forcedExpandedPaths
                )
                if !FileTreeMerger.hasSameIdentityOrder(self.rootNodes, mergedNodes) {
                    self.rootNodes = mergedNodes
                }
                if self.rootIsLoading {
                    self.rootIsLoading = false
                }
                self.rootTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                    self.workspaceGeneration == workspaceToken,
                    self.treeGeneration == treeToken
                else { return }
                if self.rootIsLoading {
                    self.rootIsLoading = false
                }
                self.fileOperationError = L10n.format(.errorReloadDirectory, error.localizedDescription)
                self.rootTask = nil
            }
        }
    }

    func setExpanded(_ node: FileNode, expanded: Bool) {
        guard node.isDirectory else { return }
        node.loadingTask?.cancel()
        node.loadingTask = nil
        node.loadingGeneration = UUID()
        if !expanded {
            node.isExpanded = false
            node.isLoading = false
            node.children = nil
            return
        }

        node.isExpanded = true
        node.isLoading = true
        guard let rootURL, let accessSession = workspaceAccessSession else { return }
        let workspaceToken = workspaceGeneration
        let treeToken = treeGeneration
        let loadingToken = node.loadingGeneration
        let nodeURL = node.url

        let loadingTask = Task { [weak self, weak node, accessSession] in
            defer { _ = accessSession }
            do {
                let entries = try await FileSystemService.entries(at: nodeURL, inside: rootURL)
                try Task.checkCancellation()
                guard
                    let node,
                    let self,
                    self.workspaceGeneration == workspaceToken,
                    self.treeGeneration == treeToken,
                    node.isExpanded,
                    node.loadingGeneration == loadingToken
                else { return }
                node.children = entries.map(FileNode.init)
                node.isLoading = false
                node.loadingTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard
                    !Task.isCancelled,
                    let node,
                    node.isExpanded,
                    node.loadingGeneration == loadingToken
                else { return }
                node.children = []
                node.isLoading = false
                node.loadingTask = nil
            }
        }
        node.loadingTask = loadingTask
    }

    func select(_ node: FileNode) {
        guard !node.isDirectory else {
            setExpanded(node, expanded: !node.isExpanded)
            return
        }

        let targetPane = hasSecondPane ? activePane : .primary
        activePane = targetPane
        loadDocumentOrUnsupported(at: node.url, in: targetPane)
    }

    func openInOtherPane(_ node: FileNode) {
        guard !node.isDirectory else { return }
        let targetPane = hasSecondPane ? activePane.otherPane : .reference
        activePane = targetPane
        loadDocumentOrUnsupported(at: node.url, in: targetPane)
    }

    func toggleSplitReading() {
        if hasSecondPane {
            closePane(activePane)
            return
        }

        referenceDocumentTask?.cancel()
        referenceDocumentGeneration = UUID()
        clearSecondPaneState()
        referenceDocumentState = .welcome
        activePane = .reference
    }

    func closePane(_ pane: ReaderPaneID) {
        guard hasSecondPane else { return }

        if pane == .primary {
            documentTask?.cancel()
            referenceDocumentTask?.cancel()
            documentGeneration = UUID()
            referenceDocumentGeneration = UUID()

            selectedURL = referenceURL
            documentState = referenceDocumentState ?? .welcome
            scrollRequest = referenceScrollRequest
            selectedOutlineID = referenceSelectedOutlineID

            let stateToResume = referenceDocumentState
            clearSecondPaneState()
            activePane = .primary

            if case .loading(let url) = stateToResume {
                loadDocument(at: url, in: .primary)
            }
            return
        }

        referenceDocumentTask?.cancel()
        referenceDocumentGeneration = UUID()
        clearSecondPaneState()
        activePane = .primary
    }

    func activatePane(_ pane: ReaderPaneID) {
        guard pane == .primary || hasSecondPane else { return }
        activePane = pane
    }

    @discardableResult
    func rename(_ node: FileNode, to proposedName: String) -> URL? {
        fileOperationError = nil

        do {
            guard let rootURL else { throw ReaderFileOperationError.targetOutsideWorkspace }
            guard !proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ReaderFileOperationError.emptyName
            }
            guard !proposedName.contains("/") else {
                throw ReaderFileOperationError.nameContainsSeparator
            }

            let sourceURL = node.url.standardizedFileURL
            let parentURL = sourceURL.deletingLastPathComponent().standardizedFileURL
            let targetURL = parentURL
                .appendingPathComponent(proposedName, isDirectory: node.isDirectory)
                .standardizedFileURL

            try FileSystemService.validate(sourceURL, inside: rootURL)
            try FileSystemService.validate(targetURL, inside: rootURL)
            guard targetURL.deletingLastPathComponent().standardizedFileURL == parentURL else {
                throw ReaderFileOperationError.targetOutsideWorkspace
            }
            if targetURL == sourceURL { return sourceURL }
            guard !FileManager.default.fileExists(atPath: targetURL.path) else {
                throw ReaderFileOperationError.targetAlreadyExists
            }

            let updatedPrimary = selectedURL.flatMap {
                replacingPathPrefix(in: $0, from: sourceURL, to: targetURL)
            }
            let updatedReference = referenceURL.flatMap {
                replacingPathPrefix(in: $0, from: sourceURL, to: targetURL)
            }

            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            rescanWorkspace(revealing: targetURL)

            if let updatedPrimary {
                loadDocumentOrUnsupported(at: updatedPrimary, in: .primary)
            }
            if let updatedReference {
                loadDocumentOrUnsupported(at: updatedReference, in: .reference)
            }
            return targetURL
        } catch {
            fileOperationError = error.localizedDescription
            return nil
        }
    }

    func copyAbsolutePath(of node: FileNode) {
        fileOperationError = nil
        do {
            guard let rootURL else { throw ReaderFileOperationError.targetOutsideWorkspace }
            try FileSystemService.validate(node.url, inside: rootURL)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(node.url.standardizedFileURL.path, forType: .string) else {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            fileOperationError = error.localizedDescription
        }
    }

    func dismissFileOperationError() {
        fileOperationError = nil
    }

    func loadDocument(
        at url: URL,
        anchor: String? = nil,
        in pane: ReaderPaneID = .primary
    ) {
        guard
            let rootURL,
            let accessSession = workspaceAccessSession,
            FileNode.previewableExtensions.contains(url.pathExtension.lowercased())
        else {
            return
        }

        let documentToken = UUID()
        switch pane {
        case .primary:
            documentTask?.cancel()
            documentGeneration = documentToken
            selectedURL = url
            documentState = .loading(url)
            selectedOutlineID = nil
            scrollRequest = nil
        case .reference:
            referenceDocumentTask?.cancel()
            referenceDocumentGeneration = documentToken
            referenceURL = url
            referenceDocumentState = .loading(url)
            referenceSelectedOutlineID = nil
            referenceScrollRequest = nil
        }

        let selectedStyle = resolvedTheme
        let workspaceToken = workspaceGeneration
        let task = Task { [weak self, accessSession] in
            defer { _ = accessSession }
            do {
                let (source, size, modifiedAt) = try await FileSystemService.readText(at: url, inside: rootURL)
                try Task.checkCancellation()
                let rendered = try await CancellableWorker.run(priority: .userInitiated) {
                    if FileNode.htmlExtensions.contains(url.pathExtension.lowercased()) {
                        return try HTMLDocumentRenderer(
                            style: selectedStyle,
                            documentURL: url,
                            rootURL: rootURL
                        ).render(source, fileSize: size, modifiedAt: modifiedAt)
                    }
                    return try MarkdownRenderer(
                        style: selectedStyle,
                        documentURL: url,
                        rootURL: rootURL
                    ).render(source, fileSize: size, modifiedAt: modifiedAt)
                }

                guard
                    let self,
                    self.workspaceGeneration == workspaceToken,
                    self.documentGeneration(for: pane) == documentToken
                else { return }
                self.setLoaded(rendered, at: url, anchor: anchor, in: pane)
                self.clearDocumentTask(in: pane)
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                    self.workspaceGeneration == workspaceToken,
                    self.documentGeneration(for: pane) == documentToken
                else { return }
                self.setFailed(error.localizedDescription, at: url, in: pane)
                self.clearDocumentTask(in: pane)
            }
        }

        switch pane {
        case .primary: documentTask = task
        case .reference: referenceDocumentTask = task
        }
    }

    func reloadActiveDocument() {
        guard let url = selectedURL(for: activePane) else { return }
        loadDocument(at: url, in: activePane)
    }

    func selectAppAppearance(_ newAppearance: AppAppearance) {
        guard appAppearance != newAppearance else { return }
        appAppearance = newAppearance
        UserDefaults.standard.set(newAppearance.rawValue, forKey: "appAppearance")
    }

    func selectMarkdownStyle(_ newStyle: MarkdownStyle) {
        guard markdownStyle != newStyle else { return }
        markdownStyle = newStyle
        UserDefaults.standard.set(newStyle.rawValue, forKey: Self.readerThemeKey)
        UserDefaults.standard.set(newStyle.rawValue, forKey: "markdownStyle")
    }

    func updateSystemColorScheme(_ newColorScheme: ColorScheme) {
        guard systemColorScheme != newColorScheme else { return }
        systemColorScheme = newColorScheme
    }

    func openRecentWorkspace(_ workspace: RecentWorkspace) {
        guard workspace.id != rootURL?.standardizedFileURL.path else { return }
        openRecentWorkspace(workspace, reportFailure: true)
    }

    func clearRecentWorkspaces() {
        recentWorkspaces = []
        UserDefaults.standard.removeObject(forKey: Self.recentWorkspaceBookmarksKey)
    }

    func scroll(to item: OutlineItem, in pane: ReaderPaneID) {
        switch pane {
        case .primary:
            selectedOutlineID = item.id
            scrollRequest = ScrollRequest(anchor: item.anchor)
        case .reference:
            referenceSelectedOutlineID = item.id
            referenceScrollRequest = ScrollRequest(anchor: item.anchor)
        }
    }

    func updateActiveOutline(anchor: String?, in pane: ReaderPaneID) {
        guard case .loaded(_, let rendered) = documentState(for: pane) else {
            setSelectedOutlineID(nil, in: pane)
            return
        }

        guard
            let anchor,
            let item = rendered.outline.first(where: { $0.anchor == anchor })
        else {
            setSelectedOutlineID(nil, in: pane)
            return
        }
        if selectedOutlineID(for: pane) != item.id {
            setSelectedOutlineID(item.id, in: pane)
        }
    }

    func openMarkdownLink(_ url: URL, anchor: String? = nil, in pane: ReaderPaneID) {
        guard
            let rootURL,
            FileNode.previewableExtensions.contains(url.pathExtension.lowercased()),
            (try? FileSystemService.validate(url, inside: rootURL)) != nil
        else { return }
        loadDocument(at: url, anchor: anchor, in: pane)
    }

    private func loadDocumentOrUnsupported(at url: URL, in pane: ReaderPaneID) {
        if FileNode.previewableExtensions.contains(url.pathExtension.lowercased()) {
            loadDocument(at: url, in: pane)
        } else {
            switch pane {
            case .primary:
                documentTask?.cancel()
                documentGeneration = UUID()
                selectedURL = url
                documentState = .unsupported(url)
                scrollRequest = nil
                selectedOutlineID = nil
            case .reference:
                referenceDocumentTask?.cancel()
                referenceDocumentGeneration = UUID()
                referenceURL = url
                referenceDocumentState = .unsupported(url)
                referenceScrollRequest = nil
                referenceSelectedOutlineID = nil
            }
        }
    }

    private func clearSecondPaneState() {
        referenceURL = nil
        referenceDocumentState = nil
        referenceScrollRequest = nil
        referenceSelectedOutlineID = nil
    }

    private func clearDocumentTask(in pane: ReaderPaneID) {
        switch pane {
        case .primary: documentTask = nil
        case .reference: referenceDocumentTask = nil
        }
    }

    private func documentGeneration(for pane: ReaderPaneID) -> UUID {
        pane == .primary ? documentGeneration : referenceDocumentGeneration
    }

    private func setLoaded(
        _ rendered: RenderedMarkdown,
        at url: URL,
        anchor: String?,
        in pane: ReaderPaneID
    ) {
        switch pane {
        case .primary:
            documentState = .loaded(url, rendered)
            if let anchor {
                selectedOutlineID = rendered.outline.first(where: { $0.anchor == anchor })?.id
                scrollRequest = ScrollRequest(anchor: anchor)
            }
        case .reference:
            referenceDocumentState = .loaded(url, rendered)
            if let anchor {
                referenceSelectedOutlineID = rendered.outline.first(where: { $0.anchor == anchor })?.id
                referenceScrollRequest = ScrollRequest(anchor: anchor)
            }
        }
    }

    private func setFailed(_ message: String, at url: URL, in pane: ReaderPaneID) {
        switch pane {
        case .primary: documentState = .failed(url, message)
        case .reference: referenceDocumentState = .failed(url, message)
        }
    }

    private func setSelectedOutlineID(_ id: UUID?, in pane: ReaderPaneID) {
        switch pane {
        case .primary: selectedOutlineID = id
        case .reference: referenceSelectedOutlineID = id
        }
    }

    private func replacingPathPrefix(in candidate: URL, from source: URL, to target: URL) -> URL? {
        let candidatePath = candidate.standardizedFileURL.path
        let sourcePath = source.standardizedFileURL.path
        if candidatePath == sourcePath { return target }

        let sourceDirectoryPrefix = sourcePath + "/"
        guard candidatePath.hasPrefix(sourceDirectoryPrefix) else { return nil }
        let relativePath = String(candidatePath.dropFirst(sourceDirectoryPrefix.count))
        return target.appendingPathComponent(relativePath).standardizedFileURL
    }

    private static func directoryURLsToExpand(revealing targetURL: URL?, inside rootURL: URL) -> [URL] {
        guard let targetURL else { return [] }
        let root = rootURL.standardizedFileURL
        let parent = targetURL.deletingLastPathComponent().standardizedFileURL
        let rootPath = root.path
        let parentPath = parent.path
        guard parentPath.hasPrefix(rootPath + "/") else { return [] }

        let relativePath = String(parentPath.dropFirst(rootPath.count + 1))
        var current = root
        return relativePath.split(separator: "/").map { component in
            current.appendPathComponent(String(component), isDirectory: true)
            return current
        }
    }

    private static func expandedDirectoryURLs(in nodes: [FileNode]) -> [URL] {
        var result: [URL] = []
        for node in nodes where node.isDirectory && node.isExpanded {
            result.append(node.url.standardizedFileURL)
            if let children = node.children {
                result.append(contentsOf: expandedDirectoryURLs(in: children))
            }
        }
        return result
    }

    private static func uniqueDirectoryURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func restoreRecentWorkspaces() {
        let storedValues = UserDefaults.standard.array(forKey: Self.recentWorkspaceBookmarksKey) ?? []
        let storedBookmarks = storedValues.compactMap { $0 as? Data }
        var restored: [RecentWorkspace] = []
        var seenPaths: Set<String> = []

        for bookmarkData in storedBookmarks {
            guard restored.count < Self.maximumRecentWorkspaceCount else { break }
            guard let workspace = resolvedRecentWorkspace(from: bookmarkData) else { continue }
            guard seenPaths.insert(workspace.id).inserted else { continue }
            restored.append(workspace)
        }

        recentWorkspaces = restored
        persistRecentWorkspaces()
    }

    private func resolvedRecentWorkspace(from bookmarkData: Data) -> RecentWorkspace? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing { url.stopAccessingSecurityScopedResource() }
            }

            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { return nil }

            let currentBookmark = isStale ? try makeBookmark(for: url) : bookmarkData
            return RecentWorkspace(url: url, bookmarkData: currentBookmark)
        } catch {
            return nil
        }
    }

    private func openRecentWorkspace(_ workspace: RecentWorkspace, reportFailure: Bool) {
        guard let resolvedWorkspace = resolvedRecentWorkspace(from: workspace.bookmarkData) else {
            recentWorkspaces.removeAll { $0.id == workspace.id }
            persistRecentWorkspaces()
            if reportFailure {
                fileOperationError = ReaderFileOperationError.workspaceUnavailable.localizedDescription
            }
            return
        }
        openWorkspace(resolvedWorkspace.url, bookmarkData: resolvedWorkspace.bookmarkData)
    }

    private func rememberWorkspace(_ url: URL, existingBookmarkData: Data?) {
        do {
            let bookmarkData = try existingBookmarkData ?? makeBookmark(for: url)
            let workspace = RecentWorkspace(url: url, bookmarkData: bookmarkData)
            recentWorkspaces.removeAll { $0.id == workspace.id }
            recentWorkspaces.insert(workspace, at: 0)
            if recentWorkspaces.count > Self.maximumRecentWorkspaceCount {
                recentWorkspaces.removeLast(recentWorkspaces.count - Self.maximumRecentWorkspaceCount)
            }
            persistRecentWorkspaces()
        } catch {
            fileOperationError = ReaderFileOperationError
                .bookmarkCreationFailed(error.localizedDescription)
                .localizedDescription
        }
    }

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: [.isDirectoryKey],
            relativeTo: nil
        )
    }

    private func persistRecentWorkspaces() {
        UserDefaults.standard.set(
            recentWorkspaces.map(\.bookmarkData),
            forKey: Self.recentWorkspaceBookmarksKey
        )
    }
}

import AppKit
import Combine
import Foundation
import SwiftUI

struct RecentWorkspace: Identifiable, Equatable {
    let url: URL
    let bookmarkData: Data

    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }
    var displayPath: String { url.path }
}

enum FileTreeSelectionTarget: Equatable {
    case none
    case firstRootNode
    case url(URL)
}

struct FileTreeSelectionRequest: Equatable {
    let id = UUID()
    let target: FileTreeSelectionTarget
}

enum ReaderPaneID: String, Hashable, Sendable {
    case primary
    case reference

    var otherPane: ReaderPaneID {
        self == .primary ? .reference : .primary
    }
}

struct PaneTaskRegistration {
    let id: UUID
    let task: Task<Void, Never>
}

enum ReaderPaneRetry {
    case sourcePaging(SourceViewportDirection, edgePageIndex: Int)
    case sourceLanguage(SourceLanguage)
    case sourceViewportRestore
}

struct ReaderPaneState {
    var selectedURL: URL?
    var documentState: ReaderDocumentState = .welcome
    var scrollRequest: ScrollRequest?
    var selectedOutlineID: UUID?

    var documentTask: Task<Void, Never>?
    var documentGeneration = UUID()
    var sourceSession: SourceFileSession?

    var documentSearchState = DocumentSearchState()
    var documentSearchFocusRequest: UUID?
    var documentSearchRequest: DocumentSearchRequest?
    var sourceViewportUpdates: [SourceViewportUpdate] = []
    var sourceViewportTasks: [SourceViewportDirection: PaneTaskRegistration] = [:]
    var sourceVisiblePageIndex: Int?
    var sourceLineJumpState = SourceLineJumpState()
    var sourceLineJumpFocusRequest: UUID?
    var sourceLineJumpTask: PaneTaskRegistration?
    var operationFailure: ReaderFailure?
    var operationRetry: ReaderPaneRetry?

    mutating func cancelAllTasks() {
        documentTask?.cancel()
        sourceViewportTasks.values.forEach { $0.task.cancel() }
        sourceLineJumpTask?.task.cancel()
        documentTask = nil
        sourceViewportTasks = [:]
        sourceLineJumpTask = nil
    }

    mutating func prepareForMove() {
        cancelAllTasks()
        documentGeneration = UUID()
        sourceViewportUpdates = []
        documentSearchState.isSearching = false
        sourceLineJumpState.isResolving = false
        if documentSearchState.isPresented {
            documentSearchFocusRequest = UUID()
        }
        if sourceLineJumpState.isPresented {
            sourceLineJumpFocusRequest = UUID()
        }
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
    @Published private(set) var fileTreeSelectionRequest: FileTreeSelectionRequest?

    @Published private var paneStates: [ReaderPaneID: ReaderPaneState] = [
        .primary: ReaderPaneState()
    ]
    @Published var activePane: ReaderPaneID = .primary

    @Published var outlineIsVisible = true
    @Published private(set) var systemColorScheme: ColorScheme
    @Published private(set) var fileOperationError: String?
    private let applicationState: ApplicationState
    private var applicationStateSubscriptions: Set<AnyCancellable> = []
    private var workspaceAccessSession: WorkspaceAccessSession?
    private var rootTask: Task<Void, Never>?
    private var workspaceGeneration = UUID()
    private var treeGeneration = UUID()
    private var pendingFileTreeSelectionTarget: FileTreeSelectionTarget?
    private var sourceLanguageOverrides: [String: SourceLanguage] = [:]
    private let documentLoadCompletionBarrier: (@Sendable (URL, UUID) async -> Void)?
    private var debugArgumentsHandled = false
    private var debugLineJumpRequested = false

    init(
        restorePersistedState: Bool = true,
        applicationState: ApplicationState? = nil,
        documentLoadCompletionBarrier: (@Sendable (URL, UUID) async -> Void)? = nil
    ) {
        self.documentLoadCompletionBarrier = documentLoadCompletionBarrier
        self.applicationState = applicationState
            ?? ApplicationState(restoreRecentWorkspaces: restorePersistedState)
        systemColorScheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark
            : .light
        observeApplicationState()

        if restorePersistedState {
            if let mostRecentWorkspace = recentWorkspaces.first {
                openRecentWorkspace(mostRecentWorkspace, reportFailure: false)
            }
        }
    }

    private func observeApplicationState() {
        applicationState.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &applicationStateSubscriptions)

        applicationState.$appLanguage
            .dropFirst()
            .sink { [weak self] _ in
                self?.reloadSelectedDocumentsForLanguageChange()
            }
            .store(in: &applicationStateSubscriptions)

        applicationState.$appAppearance
            .dropFirst()
            .sink { [weak self] appearance in
                guard appearance == .system else { return }
                self?.refreshSystemColorSchemeAfterAppearanceReset()
            }
            .store(in: &applicationStateSubscriptions)
    }

    var rootName: String { rootURL?.lastPathComponent ?? L10n.string(.workspaceNotOpened) }
    var selectedURL: URL? { paneStates[.primary]?.selectedURL }
    var documentState: ReaderDocumentState { paneStates[.primary]?.documentState ?? .welcome }
    var scrollRequest: ScrollRequest? { paneStates[.primary]?.scrollRequest }
    var selectedOutlineID: UUID? { paneStates[.primary]?.selectedOutlineID }
    var referenceURL: URL? { paneStates[.reference]?.selectedURL }
    var referenceDocumentState: ReaderDocumentState? { paneStates[.reference]?.documentState }
    var referenceScrollRequest: ScrollRequest? { paneStates[.reference]?.scrollRequest }
    var referenceSelectedOutlineID: UUID? { paneStates[.reference]?.selectedOutlineID }
    var hasSecondPane: Bool { paneStates[.reference] != nil }
    var currentTitle: String { currentTitle(for: activePane) }
    var appLanguage: AppLanguage { applicationState.appLanguage }
    var appAppearance: AppAppearance { applicationState.appAppearance }
    var markdownStyle: MarkdownStyle { applicationState.markdownStyle }
    var recentWorkspaces: [RecentWorkspace] { applicationState.recentWorkspaces }
    var resolvedTheme: ResolvedReaderTheme {
        ResolvedReaderTheme(
            style: markdownStyle,
            isDark: appAppearance.resolvesDark(systemColorScheme: systemColorScheme)
        )
    }

    var canReloadActiveDocument: Bool {
        switch documentState(for: activePane) {
        case .loading, .loaded, .failed: true
        case .welcome, .unsupported: false
        }
    }

    var canFindInActiveDocument: Bool {
        if case .loaded(_, let document) = documentState(for: activePane) {
            return document.renderingMode != .image
        }
        return false
    }

    var canJumpToLineInActiveDocument: Bool {
        guard
            sourceSession(for: activePane) != nil,
            case .loaded(_, let document) = documentState(for: activePane)
        else { return false }
        return document.sourcePage != nil
    }

    func currentTitle(for pane: ReaderPaneID) -> String {
        switch documentState(for: pane) {
        case .loaded(let url, _), .loading(let url), .unsupported(let url): url.lastPathComponent
        case .failed(let url, _): url?.lastPathComponent ?? L10n.string(.documentLoadFailed)
        case .welcome: L10n.string(.appName)
        }
    }

    func documentState(for pane: ReaderPaneID) -> ReaderDocumentState {
        paneStates[pane]?.documentState ?? .welcome
    }

    func selectedURL(for pane: ReaderPaneID) -> URL? {
        paneStates[pane]?.selectedURL
    }

#if DEBUG
    func installPaneStateForTesting(_ state: ReaderPaneState, in pane: ReaderPaneID) {
        paneStates[pane] = state
    }

    func paneStateForTesting(_ pane: ReaderPaneID) -> ReaderPaneState? {
        paneStates[pane]
    }

    func installWorkspaceForTesting(_ url: URL) {
        rootTask?.cancel()
        let accessSession = WorkspaceAccessSession(url: url)
        workspaceAccessSession = accessSession
        rootURL = accessSession.rootURL
        rootNodes = []
        rootIsLoading = false
        workspaceGeneration = UUID()
    }
#endif

    func scrollRequest(for pane: ReaderPaneID) -> ScrollRequest? {
        paneStates[pane]?.scrollRequest
    }

    func selectedOutlineID(for pane: ReaderPaneID) -> UUID? {
        paneStates[pane]?.selectedOutlineID
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
        debugLineJumpRequested = arguments.contains("--show-line-jump")
        openWorkspace(
            fileURL.deletingLastPathComponent(),
            bookmarkData: nil,
            fileTreeSelectionTarget: .url(fileURL)
        )
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
        openWorkspace(url, bookmarkData: nil, fileTreeSelectionTarget: .firstRootNode)
    }

    func openWorkspace(_ request: WorkspaceOpenRequest) {
        openWorkspace(
            request.workspaceURL,
            bookmarkData: nil,
            fileTreeSelectionTarget: request.documentURL.map(FileTreeSelectionTarget.url)
                ?? .firstRootNode
        )
        if let documentURL = request.documentURL {
            loadDocument(at: documentURL, in: .primary)
        }
    }

    private func openWorkspace(
        _ url: URL,
        bookmarkData: Data?,
        fileTreeSelectionTarget: FileTreeSelectionTarget
    ) {
        rootTask?.cancel()
        for pane in Array(paneStates.keys) {
            updatePane(pane) { $0.cancelAllTasks() }
        }

        let accessSession = WorkspaceAccessSession(url: url)
        workspaceAccessSession = accessSession
        let workspaceURL = accessSession.rootURL
        rootURL = workspaceURL
        rootNodes = []
        rootIsLoading = true
        paneStates = [.primary: ReaderPaneState()]
        sourceLanguageOverrides = [:]
        activePane = .primary
        workspaceGeneration = UUID()
        pendingFileTreeSelectionTarget = fileTreeSelectionTarget
        fileTreeSelectionRequest = FileTreeSelectionRequest(target: .none)
        fileOperationError = nil

        rememberWorkspace(url, existingBookmarkData: bookmarkData)
        let revealingURL: URL?
        if case .url(let url) = fileTreeSelectionTarget {
            revealingURL = url
        } else {
            revealingURL = nil
        }
        rescanWorkspace(revealing: revealingURL)
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
                if let selectionTarget = self.pendingFileTreeSelectionTarget {
                    self.pendingFileTreeSelectionTarget = nil
                    self.fileTreeSelectionRequest = FileTreeSelectionRequest(
                        target: selectionTarget
                    )
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
        if pane(targetPane, isShowing: node.url) {
            activePane = targetPane
            return
        }
        if hasSecondPane {
            let otherPane = targetPane.otherPane
            if pane(otherPane, isShowing: node.url) {
                activePane = otherPane
                return
            }
        }
        activePane = targetPane
        loadDocumentOrUnsupported(at: node.url, in: targetPane)
    }

    func openInOtherPane(_ node: FileNode) {
        guard !node.isDirectory else { return }
        let targetPane = hasSecondPane ? activePane.otherPane : .reference
        activePane = targetPane
        if pane(targetPane, isShowing: node.url) {
            return
        }
        loadDocumentOrUnsupported(at: node.url, in: targetPane)
    }

    private func pane(_ pane: ReaderPaneID, isShowing url: URL) -> Bool {
        selectedURL(for: pane)?.standardizedFileURL == url.standardizedFileURL
    }

    func toggleSplitReading() {
        if hasSecondPane {
            closePane(activePane)
            return
        }

        paneStates[.reference] = ReaderPaneState()
        activePane = .reference
    }

    func closePane(_ pane: ReaderPaneID) {
        guard hasSecondPane else { return }

        if pane == .primary {
            updatePane(.primary) { $0.cancelAllTasks() }
            guard var survivor = paneStates.removeValue(forKey: .reference) else { return }
            survivor.prepareForMove()
            let stateToResume = survivor.documentState
            paneStates[.primary] = survivor
            activePane = .primary

            if case .loading(let url) = stateToResume {
                loadDocument(at: url, in: .primary)
            } else {
                restoreMovedSourceViewportIfNeeded(in: .primary)
            }
            return
        }

        updatePane(.reference) { $0.cancelAllTasks() }
        paneStates.removeValue(forKey: .reference)
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
            sourceLanguageOverrides = Self.migratingSourceLanguageOverrides(
                sourceLanguageOverrides,
                from: sourceURL,
                to: targetURL
            )
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
            let previewKind = FileSystemService.previewKind(at: url)
        else {
            return
        }

        if paneStates[pane] == nil {
            paneStates[pane] = ReaderPaneState()
        }
        resetSourcePresentation(in: pane)
        let documentToken = UUID()
        updatePane(pane) { state in
            state.documentTask?.cancel()
            state.documentTask = nil
            state.documentGeneration = documentToken
            state.selectedURL = url
            state.documentState = .loading(url)
            state.selectedOutlineID = nil
            state.scrollRequest = nil
            state.sourceSession = nil
            state.documentSearchState = DocumentSearchState()
            state.documentSearchRequest = nil
            state.operationFailure = nil
            state.operationRetry = nil
        }

        let selectedStyle = resolvedTheme
        let languageOverride = sourceLanguageOverrides[url.path]
        let workspaceToken = workspaceGeneration
        let loadCompletionBarrier = documentLoadCompletionBarrier
        let task = Task { [weak self, accessSession] in
            defer { _ = accessSession }
            do {
                let result: (rendered: RenderedDocument, sourceSession: SourceFileSession?)
                switch previewKind {
                case .source(let inferredLanguage):
                    result = try await CancellableWorker.run(priority: .userInitiated) {
                        let session = try SourceFileSession(fileURL: url, rootURL: rootURL)
                        let page = try session.page(at: 0)
                        let resolvedInferredLanguage = inferredLanguage == .plaintext
                            ? session.suggestedLanguage ?? inferredLanguage
                            : inferredLanguage
                        let selectedLanguage = languageOverride ?? resolvedInferredLanguage
                        let rendered = try SourceDocumentRenderer(
                            style: selectedStyle,
                            documentURL: url
                        ).render(
                            page: page,
                            language: selectedLanguage,
                            inferredLanguage: resolvedInferredLanguage,
                            fileSize: session.fileSize,
                            modifiedAt: session.modifiedAt
                        )
                        return (rendered, session)
                    }
                case .image:
                    let rendered = try await CancellableWorker.run(priority: .userInitiated) {
                        try ImageDocumentRenderer(
                            style: selectedStyle,
                            documentURL: url,
                            rootURL: rootURL
                        ).render()
                    }
                    result = (rendered, nil)
                case .html, .markdown:
                    do {
                        let (source, size, modifiedAt) = try await FileSystemService.readText(
                            at: url,
                            inside: rootURL,
                            maximumBytes: LocalDocumentResourcePolicy.maximumStructuredDocumentBytes
                        )
                        try Task.checkCancellation()
                        let rendered = try await CancellableWorker.run(priority: .userInitiated) {
                            switch previewKind {
                            case .html:
                                return try HTMLDocumentRenderer(
                                    style: selectedStyle,
                                    documentURL: url,
                                    rootURL: rootURL
                                ).render(source, fileSize: size, modifiedAt: modifiedAt)
                            case .markdown:
                                return try MarkdownRenderer(
                                    style: selectedStyle,
                                    documentURL: url,
                                    rootURL: rootURL
                                ).render(source, fileSize: size, modifiedAt: modifiedAt)
                            case .source, .image:
                                throw CancellationError()
                            }
                        }
                        result = (rendered, nil)
                    } catch FileSystemError.structuredDocumentTooLarge {
                        result = try await CancellableWorker.run(priority: .userInitiated) {
                            let session = try SourceFileSession(fileURL: url, rootURL: rootURL)
                            let inferredLanguage: SourceLanguage = previewKind == .html ? .xml : .markdown
                            let selectedLanguage = languageOverride ?? inferredLanguage
                            let page = try session.page(at: 0)
                            let rendered = try SourceDocumentRenderer(
                                style: selectedStyle,
                                documentURL: url
                            ).render(
                                page: page,
                                language: selectedLanguage,
                                inferredLanguage: inferredLanguage,
                                fileSize: session.fileSize,
                                modifiedAt: session.modifiedAt
                            )
                            return (rendered, session)
                        }
                    }
                }

                if let loadCompletionBarrier {
                    await loadCompletionBarrier(url, documentToken)
                }

                guard
                    let self,
                    self.workspaceGeneration == workspaceToken,
                    self.documentGeneration(for: pane) == documentToken
                else { return }
                self.setSourceSession(result.sourceSession, in: pane)
                if result.sourceSession != nil {
                    self.updatePane(pane) { $0.sourceVisiblePageIndex = 0 }
                }
                self.setLoaded(result.rendered, at: url, anchor: anchor, in: pane)
                if pane == .primary, self.debugLineJumpRequested {
                    self.debugLineJumpRequested = false
                    self.requestSourceLineJumpFocus()
                }
                self.clearDocumentTask(in: pane)
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                    self.workspaceGeneration == workspaceToken,
                    self.documentGeneration(for: pane) == documentToken
                else { return }
                self.setFailed(error, operation: .documentLoad, at: url, in: pane)
                self.clearDocumentTask(in: pane)
            }
        }

        setDocumentTask(task, in: pane)
    }

    func reloadActiveDocument() {
        guard let url = selectedURL(for: activePane) else { return }
        loadDocument(at: url, in: activePane)
    }

    func documentSearchState(for pane: ReaderPaneID) -> DocumentSearchState {
        paneStates[pane]?.documentSearchState ?? DocumentSearchState()
    }

    func documentSearchFocusRequest(for pane: ReaderPaneID) -> UUID? {
        paneStates[pane]?.documentSearchFocusRequest
    }

    func documentSearchRequest(for pane: ReaderPaneID) -> DocumentSearchRequest? {
        paneStates[pane]?.documentSearchRequest
    }

    func requestDocumentSearchFocus() {
        guard canFindInActiveDocument else { return }
        if sourceLineJumpState(for: activePane).isPresented {
            dismissSourceLineJump(in: activePane)
        }
        var state = documentSearchState(for: activePane)
        state.isPresented = true
        updatePane(activePane) { paneState in
            paneState.documentSearchState = state
            paneState.documentSearchFocusRequest = UUID()
        }
    }

    func dismissDocumentSearch(in pane: ReaderPaneID) {
        cancelDocumentSearch(in: pane)
        var state = documentSearchState(for: pane)
        state.isPresented = false
        state.isSearching = false
        updatePane(pane) { paneState in
            paneState.documentSearchState = state
            paneState.documentSearchRequest = DocumentSearchRequest(
                id: UUID(),
                query: "",
                isCaseSensitive: state.isCaseSensitive,
                direction: .next
            )
        }
    }

    func updateDocumentSearchQuery(_ query: String, in pane: ReaderPaneID) {
        var state = documentSearchState(for: pane)
        guard state.query != query else { return }
        cancelDocumentSearch(in: pane)
        state.query = query
        state.isSearching = false
        state.match = nil
        state.didWrap = false
        state.didFail = false
        state.failure = nil
        updatePane(pane) { $0.documentSearchState = state }
    }

    func toggleDocumentSearchCaseSensitivity(in pane: ReaderPaneID) {
        var state = documentSearchState(for: pane)
        cancelDocumentSearch(in: pane)
        state.isCaseSensitive.toggle()
        state.isSearching = false
        state.match = nil
        state.didWrap = false
        state.didFail = false
        state.failure = nil
        updatePane(pane) { $0.documentSearchState = state }
    }

    func sourceViewportUpdates(for pane: ReaderPaneID) -> [SourceViewportUpdate] {
        paneStates[pane]?.sourceViewportUpdates ?? []
    }

    func operationFailure(for pane: ReaderPaneID) -> ReaderFailure? {
        paneStates[pane]?.operationFailure
    }

    func dismissOperationFailure(in pane: ReaderPaneID) {
        updatePane(pane) { state in
            state.operationFailure = nil
            state.operationRetry = nil
        }
    }

    func retryOperation(in pane: ReaderPaneID) {
        guard let retry = paneStates[pane]?.operationRetry else { return }
        dismissOperationFailure(in: pane)
        switch retry {
        case .sourcePaging(let direction, let edgePageIndex):
            loadAdjacentSourceSegment(direction, edgePageIndex: edgePageIndex, in: pane)
        case .sourceLanguage(let language):
            selectSourceLanguage(language, in: pane)
        case .sourceViewportRestore:
            restoreMovedSourceViewportIfNeeded(in: pane)
        }
    }

    func updateVisibleSourcePage(_ pageIndex: Int, in pane: ReaderPaneID) {
        guard sourceSession(for: pane) != nil else { return }
        updatePane(pane) { $0.sourceVisiblePageIndex = pageIndex }
    }

    func loadAdjacentSourceSegment(
        _ direction: SourceViewportDirection,
        edgePageIndex: Int,
        in pane: ReaderPaneID
    ) {
        guard
            paneStates[pane]?.sourceViewportTasks[direction] == nil,
            let session = sourceSession(for: pane),
            case .loaded(_, let document) = documentState(for: pane),
            let source = document.sourcePage,
            let accessSession = workspaceAccessSession
        else { return }

        let targetIndex = edgePageIndex + (direction == .next ? 1 : -1)
        guard targetIndex >= 0 else { return }
        let documentToken = documentGeneration(for: pane)
        let workspaceToken = workspaceGeneration
        let taskID = UUID()
        let task = Task { [weak self, accessSession] in
            defer { _ = accessSession }
            do {
                let page = try await CancellableWorker.run(priority: .userInitiated) {
                    try session.page(at: targetIndex)
                }
                guard
                    let self,
                    self.workspaceGeneration == workspaceToken,
                    self.documentGeneration(for: pane) == documentToken
                else { return }
                self.enqueueSourceViewportUpdate(SourceViewportUpdate(
                    action: direction == .next ? .append : .prepend,
                    page: page,
                    language: source.language,
                    selectedRange: nil,
                    targetLine: nil
                ), in: pane)
                self.updatePane(pane) { state in
                    state.operationFailure = nil
                    state.operationRetry = nil
                }
                self.clearSourceViewportTask(direction, id: taskID, in: pane)
            } catch is CancellationError {
                self?.clearSourceViewportTask(direction, id: taskID, in: pane)
            } catch {
                guard
                    let self,
                    self.documentGeneration(for: pane) == documentToken,
                    let url = self.selectedURL(for: pane)
                else { return }
                self.clearSourceViewportTask(direction, id: taskID, in: pane)
                self.enqueueSourceViewportUpdate(SourceViewportUpdate(
                    action: direction == .previous ? .releasePrevious : .releaseNext,
                    page: source.page,
                    language: source.language,
                    selectedRange: nil,
                    targetLine: nil
                ), in: pane)
                self.setOperationFailure(
                    error,
                    operation: .sourcePaging,
                    at: url,
                    retry: .sourcePaging(direction, edgePageIndex: edgePageIndex),
                    in: pane
                )
            }
        }
        updatePane(pane) {
            $0.sourceViewportTasks[direction] = PaneTaskRegistration(id: taskID, task: task)
        }
    }

    func sourceLineJumpState(for pane: ReaderPaneID) -> SourceLineJumpState {
        paneStates[pane]?.sourceLineJumpState ?? SourceLineJumpState()
    }

    func sourceLineJumpFocusRequest(for pane: ReaderPaneID) -> UUID? {
        paneStates[pane]?.sourceLineJumpFocusRequest
    }

    func requestSourceLineJumpFocus() {
        let pane = activePane
        guard sourceSession(for: pane) != nil else { return }
        if documentSearchState(for: pane).isPresented {
            dismissDocumentSearch(in: pane)
        }
        var state = sourceLineJumpState(for: pane)
        state.isPresented = true
        state.didFail = false
        state.failure = nil
        updatePane(pane) { paneState in
            paneState.sourceLineJumpState = state
            paneState.sourceLineJumpFocusRequest = UUID()
        }
    }

    func updateSourceLineJumpInput(_ value: String, in pane: ReaderPaneID) {
        var state = sourceLineJumpState(for: pane)
        state.input = value.filter { "0123456789".contains($0) }
        state.didFail = false
        state.failure = nil
        updatePane(pane) { $0.sourceLineJumpState = state }
    }

    func dismissSourceLineJump(in pane: ReaderPaneID) {
        updatePane(pane) { state in
            state.sourceLineJumpTask?.task.cancel()
            state.sourceLineJumpTask = nil
            state.sourceLineJumpState = SourceLineJumpState()
            state.sourceLineJumpFocusRequest = nil
        }
    }

    func jumpToSourceLine(in pane: ReaderPaneID) {
        var state = sourceLineJumpState(for: pane)
        guard
            state.isPresented,
            !state.isResolving,
            let line = Int(state.input),
            line > 0,
            let session = sourceSession(for: pane),
            case .loaded(_, let document) = documentState(for: pane),
            let source = document.sourcePage,
            let accessSession = workspaceAccessSession
        else {
            state.didFail = true
            updatePane(pane) { $0.sourceLineJumpState = state }
            return
        }

        updatePane(pane) { paneState in
            paneState.sourceLineJumpTask?.task.cancel()
            paneState.sourceLineJumpTask = nil
        }
        state.isResolving = true
        state.didFail = false
        state.failure = nil
        updatePane(pane) { $0.sourceLineJumpState = state }
        let documentToken = documentGeneration(for: pane)
        let workspaceToken = workspaceGeneration
        let taskID = UUID()
        let task = Task { [weak self, accessSession] in
            defer { _ = accessSession }
            do {
                let page = try await CancellableWorker.run(priority: .userInitiated) {
                    try session.page(containingLine: line)
                }
                guard
                    let self,
                    self.workspaceGeneration == workspaceToken,
                    self.documentGeneration(for: pane) == documentToken
                else { return }
                self.clearSourceLineJumpTask(id: taskID, in: pane)
                guard let page else {
                    var failed = self.sourceLineJumpState(for: pane)
                    failed.isResolving = false
                    failed.didFail = true
                    self.updatePane(pane) { paneState in
                        paneState.sourceLineJumpState = failed
                        paneState.sourceLineJumpFocusRequest = UUID()
                    }
                    return
                }
                self.cancelSourceViewportLoading(in: pane)
                self.updatePane(pane) { $0.sourceVisiblePageIndex = page.index }
                self.enqueueSourceViewportUpdate(SourceViewportUpdate(
                    action: .replace,
                    page: page,
                    language: source.language,
                    selectedRange: nil,
                    targetLine: line
                ), in: pane)
                self.updatePane(pane) { paneState in
                    paneState.sourceLineJumpState = SourceLineJumpState()
                    paneState.sourceLineJumpFocusRequest = nil
                }
            } catch is CancellationError {
                self?.clearSourceLineJumpTask(id: taskID, in: pane)
            } catch {
                guard let self else { return }
                self.clearSourceLineJumpTask(id: taskID, in: pane)
                var failed = self.sourceLineJumpState(for: pane)
                failed.isResolving = false
                failed.didFail = true
                failed.failure = ReaderFailure(error: error, operation: .lineJump)
                self.updatePane(pane) { paneState in
                    paneState.sourceLineJumpState = failed
                    paneState.sourceLineJumpFocusRequest = UUID()
                }
            }
        }
        updatePane(pane) {
            $0.sourceLineJumpTask = PaneTaskRegistration(id: taskID, task: task)
        }
    }

    func selectSourceLanguage(_ language: SourceLanguage, in pane: ReaderPaneID) {
        guard
            let url = selectedURL(for: pane),
            case .loaded(_, let document) = documentState(for: pane),
            let source = document.sourcePage,
            let session = sourceSession(for: pane),
            let accessSession = workspaceAccessSession
        else { return }
        guard source.language != language else { return }

        cancelDocumentSearch(in: pane)
        sourceLanguageOverrides[url.path] = language
        cancelSourceViewportLoading(in: pane)
        documentTask(in: pane)?.cancel()
        let token = UUID()
        setDocumentGeneration(token, in: pane)
        let style = resolvedTheme
        let workspaceToken = workspaceGeneration
        let pageIndex = paneStates[pane]?.sourceVisiblePageIndex ?? source.page.index
        let selectedRange = documentSearchState(for: pane).match.flatMap { match in
            match.pageIndex == pageIndex ? match.range : nil
        }

        let task = Task { [weak self, accessSession] in
            defer { _ = accessSession }
            do {
                let rendered = try await CancellableWorker.run(priority: .userInitiated) {
                    let page = try session.page(at: pageIndex)
                    return try SourceDocumentRenderer(style: style, documentURL: url).render(
                        page: page,
                        language: language,
                        inferredLanguage: source.inferredLanguage,
                        fileSize: session.fileSize,
                        modifiedAt: session.modifiedAt,
                        selectedRange: selectedRange
                    )
                }
                guard
                    let self,
                    self.workspaceGeneration == workspaceToken,
                    self.documentGeneration(for: pane) == token
                else { return }
                self.updatePane(pane) { paneState in
                    paneState.sourceViewportUpdates = []
                    paneState.sourceVisiblePageIndex = pageIndex
                    paneState.operationFailure = nil
                    paneState.operationRetry = nil
                }
                self.setLoaded(rendered, at: url, anchor: nil, in: pane)
                self.clearDocumentTask(in: pane)
            } catch is CancellationError {
                return
            } catch {
                guard
                    let self,
                    self.documentGeneration(for: pane) == token,
                    let currentURL = self.selectedURL(for: pane)
                else { return }
                self.setOperationFailure(
                    error,
                    operation: .sourcePaging,
                    at: currentURL,
                    retry: .sourceLanguage(language),
                    in: pane
                )
                self.clearDocumentTask(in: pane)
            }
        }
        setDocumentTask(task, in: pane)
    }

    func findInDocument(_ direction: DocumentSearchDirection, in pane: ReaderPaneID) {
        let state = documentSearchState(for: pane)
        guard state.isPresented, !state.query.isEmpty else { return }

        if sourceSession(for: pane) != nil {
            findInSource(direction, in: pane)
            return
        }

        guard case .loaded = documentState(for: pane) else { return }
        let request = DocumentSearchRequest(
            id: UUID(),
            query: state.query,
            isCaseSensitive: state.isCaseSensitive,
            direction: direction
        )
        var searchingState = state
        searchingState.isSearching = true
        searchingState.match = nil
        searchingState.didWrap = false
        searchingState.didFail = false
        searchingState.failure = nil
        updatePane(pane) { paneState in
            paneState.documentSearchState = searchingState
            paneState.documentSearchRequest = request
        }
    }

    func updateDocumentSearchResult(
        requestID: UUID,
        found: Bool,
        in pane: ReaderPaneID
    ) {
        guard paneStates[pane]?.documentSearchRequest?.id == requestID else { return }
        var state = documentSearchState(for: pane)
        state.isSearching = false
        state.match = nil
        state.didWrap = false
        state.didFail = !found
        state.failure = nil
        updatePane(pane) { $0.documentSearchState = state }
    }

    private func findInSource(_ direction: DocumentSearchDirection, in pane: ReaderPaneID) {
        guard
            let session = sourceSession(for: pane),
            case .loaded(_, let currentDocument) = documentState(for: pane),
            let currentSource = currentDocument.sourcePage,
            let accessSession = workspaceAccessSession
        else { return }

        var state = documentSearchState(for: pane)
        guard !state.query.isEmpty else { return }
        state.isSearching = true
        state.didFail = false
        state.failure = nil
        updatePane(pane) { $0.documentSearchState = state }

        cancelSourceViewportLoading(in: pane)
        documentTask(in: pane)?.cancel()
        let token = UUID()
        setDocumentGeneration(token, in: pane)
        let workspaceToken = workspaceGeneration
        let query = state.query
        let caseSensitive = state.isCaseSensitive
        let currentMatch = state.match
        let currentPageIndex = paneStates[pane]?.sourceVisiblePageIndex ?? currentSource.page.index

        let task = Task { [weak self, accessSession] in
            defer { _ = accessSession }
            do {
                let result = try await CancellableWorker.run(priority: .userInitiated) {
                    let search = try session.find(
                        query,
                        caseSensitive: caseSensitive,
                        direction: direction,
                        currentPageIndex: currentPageIndex,
                        currentMatch: currentMatch
                    )
                    guard let match = search.match else {
                        return (page: Optional<SourcePage>.none, match: Optional<SourceSearchMatch>.none, search.didWrap)
                    }
                    let page = try session.page(at: match.pageIndex)
                    return (Optional(page), Optional(match), search.didWrap)
                }

                guard
                    let self,
                    self.workspaceGeneration == workspaceToken,
                    self.documentGeneration(for: pane) == token
                else { return }
                if let page = result.page, let match = result.match {
                    self.updatePane(pane) { $0.sourceVisiblePageIndex = page.index }
                    self.enqueueSourceViewportUpdate(SourceViewportUpdate(
                        action: .replace,
                        page: page,
                        language: currentSource.language,
                        selectedRange: match.range,
                        targetLine: match.line
                    ), in: pane)
                } else {
                    self.clearSourceViewportPending(in: pane, source: currentSource)
                }
                var latest = self.documentSearchState(for: pane)
                latest.isSearching = false
                latest.match = result.match
                latest.didWrap = result.2
                latest.didFail = result.match == nil
                latest.failure = nil
                self.updatePane(pane) { $0.documentSearchState = latest }
                self.clearDocumentTask(in: pane)
            } catch is CancellationError {
                return
            } catch {
                guard
                    let self,
                    self.documentGeneration(for: pane) == token
                else { return }
                var failed = self.documentSearchState(for: pane)
                failed.isSearching = false
                failed.didFail = true
                failed.failure = ReaderFailure(error: error, operation: .documentSearch)
                self.updatePane(pane) { $0.documentSearchState = failed }
                self.clearDocumentTask(in: pane)
            }
        }
        setDocumentTask(task, in: pane)
    }

    private func reloadSelectedDocumentsForLanguageChange() {
        let selectedDocuments = paneStates.compactMap { pane, state in
            state.selectedURL.map { (pane, $0) }
        }
        for (pane, url) in selectedDocuments {
            loadDocument(at: url, in: pane)
        }
    }

    private func refreshSystemColorSchemeAfterAppearanceReset() {
        // preferredColorScheme 解除后，NSApp 的有效外观会在后续主循环才恢复为系统值。
        // 延后刷新，避免 WebView 使用切换前的强制明暗配色。
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let newColorScheme: ColorScheme = NSApp.effectiveAppearance
                    .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? .dark
                    : .light
                self.updateSystemColorScheme(newColorScheme)
            }
        }
    }

    func selectMarkdownStyle(_ newStyle: MarkdownStyle) {
        applicationState.selectMarkdownStyle(newStyle)
    }

    func updateSystemColorScheme(_ newColorScheme: ColorScheme) {
        guard systemColorScheme != newColorScheme else { return }
        systemColorScheme = newColorScheme
    }

    func openRecentWorkspace(_ workspace: RecentWorkspace) {
        guard workspace.id != rootURL?.standardizedFileURL.path else { return }
        openRecentWorkspace(workspace, reportFailure: true)
    }

    var canClearRecentWorkspaces: Bool {
        recentWorkspaces.contains { $0.id != rootURL?.standardizedFileURL.path }
    }

    func removeRecentWorkspace(_ workspace: RecentWorkspace) {
        guard workspace.id != rootURL?.standardizedFileURL.path else { return }
        applicationState.removeRecentWorkspace(id: workspace.id)
    }

    func clearRecentWorkspaces() {
        do {
            try applicationState.clearRecentWorkspaces(preserving: rootURL)
        } catch {
            fileOperationError = ReaderFileOperationError
                .bookmarkCreationFailed(error.localizedDescription)
                .localizedDescription
        }
    }

    func scroll(to item: OutlineItem, in pane: ReaderPaneID) {
        updatePane(pane) { state in
            state.selectedOutlineID = item.id
            state.scrollRequest = ScrollRequest(anchor: item.anchor)
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

    func openDocumentLink(_ url: URL, anchor: String? = nil, in pane: ReaderPaneID) {
        guard
            let rootURL,
            FileSystemService.previewKind(at: url) != nil,
            (try? FileSystemService.validate(url, inside: rootURL)) != nil
        else { return }
        loadDocument(at: url, anchor: anchor, in: pane)
    }

    private func loadDocumentOrUnsupported(at url: URL, in pane: ReaderPaneID) {
        if FileSystemService.previewKind(at: url) != nil {
            loadDocument(at: url, in: pane)
        } else {
            if paneStates[pane] == nil {
                paneStates[pane] = ReaderPaneState()
            }
            resetSourcePresentation(in: pane)
            updatePane(pane) { state in
                state.documentTask?.cancel()
                state.documentTask = nil
                state.documentGeneration = UUID()
                state.sourceSession = nil
                state.selectedURL = url
                state.documentState = .unsupported(url)
                state.scrollRequest = nil
                state.selectedOutlineID = nil
                state.documentSearchState = DocumentSearchState()
                state.documentSearchFocusRequest = nil
                state.documentSearchRequest = nil
                state.operationFailure = nil
                state.operationRetry = nil
            }
        }
    }

    private func cancelDocumentSearch(in pane: ReaderPaneID) {
        guard documentSearchState(for: pane).isSearching else { return }
        documentTask(in: pane)?.cancel()
        setDocumentTask(nil, in: pane)
        setDocumentGeneration(UUID(), in: pane)
        var state = documentSearchState(for: pane)
        state.isSearching = false
        updatePane(pane) { paneState in
            paneState.documentSearchState = state
            paneState.documentSearchRequest = nil
        }
        if
            case .loaded(_, let document) = documentState(for: pane),
            let source = document.sourcePage
        {
            clearSourceViewportPending(in: pane, source: source)
        }
    }

    private func updatePane(
        _ pane: ReaderPaneID,
        _ update: (inout ReaderPaneState) -> Void
    ) {
        guard var state = paneStates[pane] else { return }
        update(&state)
        paneStates[pane] = state
    }

    private func clearDocumentTask(in pane: ReaderPaneID) {
        updatePane(pane) { $0.documentTask = nil }
    }

    private func documentGeneration(for pane: ReaderPaneID) -> UUID {
        paneStates[pane]?.documentGeneration ?? UUID()
    }

    private func setDocumentGeneration(_ generation: UUID, in pane: ReaderPaneID) {
        updatePane(pane) { $0.documentGeneration = generation }
    }

    private func documentTask(in pane: ReaderPaneID) -> Task<Void, Never>? {
        paneStates[pane]?.documentTask
    }

    private func setDocumentTask(_ task: Task<Void, Never>?, in pane: ReaderPaneID) {
        updatePane(pane) { $0.documentTask = task }
    }

    private func sourceSession(for pane: ReaderPaneID) -> SourceFileSession? {
        paneStates[pane]?.sourceSession
    }

    private func setSourceSession(_ session: SourceFileSession?, in pane: ReaderPaneID) {
        updatePane(pane) { $0.sourceSession = session }
    }

    static func migratingSourceLanguageOverrides(
        _ overrides: [String: SourceLanguage],
        from sourceURL: URL,
        to targetURL: URL
    ) -> [String: SourceLanguage] {
        let sourcePath = sourceURL.standardizedFileURL.path
        let targetPath = targetURL.standardizedFileURL.path
        let sourcePrefix = sourcePath + "/"
        var migrated = overrides

        for (path, language) in overrides where path == sourcePath || path.hasPrefix(sourcePrefix) {
            migrated.removeValue(forKey: path)
            let suffix = String(path.dropFirst(sourcePath.count))
            migrated[targetPath + suffix] = language
        }
        return migrated
    }

    private func cancelSourceViewportLoading(in pane: ReaderPaneID) {
        let registrations = paneStates[pane].map { Array($0.sourceViewportTasks.values) } ?? []
        guard !registrations.isEmpty else { return }
        registrations.forEach { $0.task.cancel() }
        updatePane(pane) { $0.sourceViewportTasks = [:] }
        if
            case .loaded(_, let document) = documentState(for: pane),
            let source = document.sourcePage
        {
            clearSourceViewportPending(in: pane, source: source)
        }
    }

    private func clearSourceViewportTask(
        _ direction: SourceViewportDirection,
        id: UUID,
        in pane: ReaderPaneID
    ) {
        updatePane(pane) { state in
            guard state.sourceViewportTasks[direction]?.id == id else { return }
            state.sourceViewportTasks.removeValue(forKey: direction)
        }
    }

    private func clearSourceLineJumpTask(id: UUID, in pane: ReaderPaneID) {
        updatePane(pane) { state in
            guard state.sourceLineJumpTask?.id == id else { return }
            state.sourceLineJumpTask = nil
        }
    }

    private func clearSourceViewportPending(in pane: ReaderPaneID, source: RenderedSourcePage) {
        enqueueSourceViewportUpdate(SourceViewportUpdate(
            action: .clearPending,
            page: source.page,
            language: source.language,
            selectedRange: nil,
            targetLine: nil
        ), in: pane)
    }

    private func enqueueSourceViewportUpdate(_ update: SourceViewportUpdate, in pane: ReaderPaneID) {
        updatePane(pane) { state in
            state.sourceViewportUpdates.append(update)
            if state.sourceViewportUpdates.count > 4 {
                state.sourceViewportUpdates.removeFirst(state.sourceViewportUpdates.count - 4)
            }
        }
    }

    private func resetSourcePresentation(in pane: ReaderPaneID) {
        cancelSourceViewportLoading(in: pane)
        updatePane(pane) { state in
            state.sourceLineJumpTask?.task.cancel()
            state.sourceLineJumpTask = nil
            state.sourceViewportUpdates = []
            state.sourceVisiblePageIndex = nil
            state.sourceLineJumpState = SourceLineJumpState()
            state.sourceLineJumpFocusRequest = nil
        }
    }

    private func setLoaded(
        _ rendered: RenderedDocument,
        at url: URL,
        anchor: String?,
        in pane: ReaderPaneID
    ) {
        updatePane(pane) { state in
            state.documentState = .loaded(url, rendered)
            state.operationFailure = nil
            state.operationRetry = nil
            if let anchor {
                state.selectedOutlineID = rendered.outline.first(where: { $0.anchor == anchor })?.id
                state.scrollRequest = ScrollRequest(anchor: anchor)
            }
        }
    }

    private func setFailed(
        _ error: Error,
        operation: ReaderFailureOperation,
        at url: URL,
        in pane: ReaderPaneID
    ) {
        let failure = ReaderFailure(error: error, operation: operation)
        updatePane(pane) { state in
            state.documentState = .failed(url, failure)
            state.operationFailure = nil
            state.operationRetry = nil
        }
    }

    private func setOperationFailure(
        _ error: Error,
        operation: ReaderFailureOperation,
        at _: URL,
        retry: ReaderPaneRetry? = nil,
        in pane: ReaderPaneID
    ) {
        updatePane(pane) { state in
            state.operationFailure = ReaderFailure(error: error, operation: operation)
            state.operationRetry = retry
        }
    }

    private func setSelectedOutlineID(_ id: UUID?, in pane: ReaderPaneID) {
        updatePane(pane) { $0.selectedOutlineID = id }
    }

    private func restoreMovedSourceViewportIfNeeded(in pane: ReaderPaneID) {
        guard
            let state = paneStates[pane],
            let pageIndex = state.sourceVisiblePageIndex,
            let session = state.sourceSession,
            let accessSession = workspaceAccessSession,
            case .loaded(let url, let document) = state.documentState,
            let source = document.sourcePage,
            pageIndex != source.page.index
        else { return }

        let token = UUID()
        let workspaceToken = workspaceGeneration
        let selectedRange = state.documentSearchState.match.flatMap { match in
            match.pageIndex == pageIndex ? match.range : nil
        }
        updatePane(pane) { $0.documentGeneration = token }
        let style = resolvedTheme
        let task = Task { [weak self, accessSession] in
            defer { _ = accessSession }
            do {
                let rendered = try await CancellableWorker.run(priority: .userInitiated) {
                    let page = try session.page(at: pageIndex)
                    return try SourceDocumentRenderer(style: style, documentURL: url).render(
                        page: page,
                        language: source.language,
                        inferredLanguage: source.inferredLanguage,
                        fileSize: session.fileSize,
                        modifiedAt: session.modifiedAt,
                        selectedRange: selectedRange
                    )
                }
                guard
                    let self,
                    self.workspaceGeneration == workspaceToken,
                    self.documentGeneration(for: pane) == token
                else { return }
                self.setLoaded(rendered, at: url, anchor: nil, in: pane)
                self.updatePane(pane) { $0.sourceVisiblePageIndex = pageIndex }
                self.clearDocumentTask(in: pane)
            } catch is CancellationError {
                return
            } catch {
                guard
                    let self,
                    self.workspaceGeneration == workspaceToken,
                    self.documentGeneration(for: pane) == token
                else { return }
                self.setOperationFailure(
                    error,
                    operation: .sourcePaging,
                    at: url,
                    retry: .sourceViewportRestore,
                    in: pane
                )
                self.clearDocumentTask(in: pane)
            }
        }
        setDocumentTask(task, in: pane)
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

    private func openRecentWorkspace(_ workspace: RecentWorkspace, reportFailure: Bool) {
        guard let resolvedWorkspace = applicationState.resolvedRecentWorkspace(workspace) else {
            applicationState.removeRecentWorkspace(id: workspace.id)
            if reportFailure {
                fileOperationError = ReaderFileOperationError.workspaceUnavailable.localizedDescription
            }
            return
        }
        openWorkspace(
            resolvedWorkspace.url,
            bookmarkData: resolvedWorkspace.bookmarkData,
            fileTreeSelectionTarget: .firstRootNode
        )
    }

    private func rememberWorkspace(_ url: URL, existingBookmarkData: Data?) {
        do {
            try applicationState.rememberWorkspace(
                url,
                existingBookmarkData: existingBookmarkData
            )
        } catch {
            fileOperationError = ReaderFileOperationError
                .bookmarkCreationFailed(error.localizedDescription)
                .localizedDescription
        }
    }
}

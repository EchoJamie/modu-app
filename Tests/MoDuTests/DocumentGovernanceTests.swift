import AppKit
import Foundation
import Testing
@testable import MoDu
@testable import MoDuCLIInstaller

@Suite("Document governance")
struct DocumentGovernanceTests {
    @Test("Complete deterministic self-check suite")
    @MainActor
    func completeSelfCheck() {
        #expect(SelfCheck.run() == 0)
    }

    @Test("Settings window does not retain an implicit action-button focus")
    @MainActor
    func settingsWindowInitialFocus() {
        let button = NSButton(title: "Install", target: nil, action: nil)
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        contentView.addSubview(button)
        let window = NSWindow(
            contentRect: contentView.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        window.initialFirstResponder = button

        #expect(window.makeFirstResponder(button))
        #expect(window.firstResponder === button)
        #expect(SettingsWindowFocusPolicy.clearInitialFocus(in: window))
        #expect(window.initialFirstResponder == nil)
        #expect(window.firstResponder === window)
    }

    @Test("Preview classification is pure and requires regular-file metadata")
    func previewClassification() throws {
        #expect(
            PreviewDocumentKind.resolve(fileName: "main.SWIFT", isRegularFile: true)
                == .source(.swift)
        )
        #expect(
            PreviewDocumentKind.resolve(fileName: "Dockerfile.dev", isRegularFile: true)
                == .source(.dockerfile)
        )
        #expect(
            PreviewDocumentKind.resolve(fileName: "preview.PNG", isRegularFile: true)
                == .image
        )
        #expect(PreviewDocumentKind.resolve(fileName: "docs", isRegularFile: false) == nil)

        try withTemporaryRoot { root in
            let extensionlessFile = root.appendingPathComponent("README")
            let extensionlessDirectory = root.appendingPathComponent("docs", isDirectory: true)
            try "plain text\n".write(to: extensionlessFile, atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(
                at: extensionlessDirectory,
                withIntermediateDirectories: true
            )
            #expect(FileSystemService.previewKind(at: extensionlessFile) == .source(.plaintext))
            #expect(FileSystemService.previewKind(at: extensionlessDirectory) == nil)
        }
    }

    @Test("Rendered content keeps mode and payload valid by construction")
    func renderedContentModel() {
        let page = SourcePage(
            index: 0,
            text: "let value = 1\n",
            startOffset: 0,
            endOffset: 14,
            startLine: 1,
            endLine: 1,
            leadingContinuation: false,
            trailingContinuation: false,
            hasPrevious: false,
            hasNext: false
        )
        let source = RenderedSourcePage(
            page: page,
            language: .swift,
            inferredLanguage: .swift,
            selectedRange: nil
        )
        let rendered = RenderedDocument(
            content: .source(html: "<html></html>", page: source),
            outline: [],
            fileSize: 14,
            modifiedAt: nil
        )

        #expect(rendered.renderingMode == .sourceCode)
        #expect(rendered.sourcePage?.page.index == 0)
    }

    @Test("Application language preference restores explicit and system modes")
    func applicationLanguagePreference() throws {
        let suiteName = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppLanguage.restored(from: defaults) == .system)
        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        #expect(AppLanguage.restored(from: defaults) == .english)
        #expect(AppLanguage.english.resolvedLocalization == "en")
        defaults.set(
            AppLanguage.simplifiedChinese.rawValue,
            forKey: AppLanguage.storageKey
        )
        #expect(AppLanguage.restored(from: defaults) == .simplifiedChinese)
        #expect(AppLanguage.simplifiedChinese.resolvedLocalization == "zh-Hans")
        defaults.set("unsupported", forKey: AppLanguage.storageKey)
        #expect(AppLanguage.restored(from: defaults) == .system)
    }

    @Test("Large structured documents degrade to unbounded paged source")
    func structuredDocumentLoadPolicy() {
        let limit = Int64(LocalDocumentResourcePolicy.maximumStructuredDocumentBytes)
        #expect(LocalDocumentResourcePolicy.structuredDocumentLoad(forByteCount: limit) == .rendered)
        #expect(
            LocalDocumentResourcePolicy.structuredDocumentLoad(forByteCount: limit + 1)
                == .pagedSource
        )
    }

    @Test("Structured text reads enforce the byte limit at the file handle boundary")
    func boundedStructuredTextRead() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("modu-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("document.md")
        try Data("1234".utf8).write(to: fileURL)

        let (content, size, _) = try await FileSystemService.readText(
            at: fileURL,
            inside: root,
            maximumBytes: 4
        )
        #expect(content == "1234")
        #expect(size == 4)

        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("5".utf8))
        try handle.close()
        var rejected = false
        do {
            _ = try await FileSystemService.readText(
                at: fileURL,
                inside: root,
                maximumBytes: 4
            )
        } catch FileSystemError.structuredDocumentTooLarge {
            rejected = true
        }
        #expect(rejected)
    }

    @Test("External open requests distinguish workspaces and files")
    func externalWorkspaceOpenRequests() throws {
        try withTemporaryRoot { root in
            let documentURL = root.appendingPathComponent("README.md")
            try "# Command line\n".write(
                to: documentURL,
                atomically: true,
                encoding: .utf8
            )

            let directoryRequest = try #require(
                WorkspaceOpenRequest.resolve(urls: [root])
            )
            #expect(directoryRequest.workspaceURL == root.standardizedFileURL)
            #expect(directoryRequest.documentURL == nil)

            let fileRequest = try #require(
                WorkspaceOpenRequest.resolve(urls: [root, documentURL])
            )
            #expect(fileRequest.workspaceURL == root.standardizedFileURL)
            #expect(fileRequest.documentURL == documentURL.standardizedFileURL)

            let fileOnlyRequest = try #require(
                WorkspaceOpenRequest.resolve(urls: [documentURL])
            )
            #expect(fileOnlyRequest.workspaceURL == root.standardizedFileURL)
            #expect(fileOnlyRequest.documentURL == documentURL.standardizedFileURL)

            let outsideRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("modu-tests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: outsideRoot,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: outsideRoot) }
            let outsideDocument = outsideRoot.appendingPathComponent("outside.md")
            try "outside\n".write(
                to: outsideDocument,
                atomically: true,
                encoding: .utf8
            )

            let boundedRequest = try #require(
                WorkspaceOpenRequest.resolve(urls: [root, outsideDocument])
            )
            #expect(boundedRequest.workspaceURL == root.standardizedFileURL)
            #expect(boundedRequest.documentURL == nil)
            #expect(
                WorkspaceOpenRequest.resolve(
                    urls: [root.appendingPathComponent("missing")]
                ) == nil
            )
        }
    }

    @Test("Command-line tool installation is durable and protects existing items")
    @MainActor
    func commandLineToolInstallation() throws {
        try withTemporaryRoot { root in
            #expect(CommandLineToolInstaller.systemInstallationURL.path == "/usr/local/bin/modu")
            #expect(
                CLIInstallerCommand.authorizationPrompt(for: .install, isChinese: false)
                    == "Administrator permission is required to install the modu command at /usr/local/bin."
            )
            #expect(
                CLIInstallerCommand.authorizationPrompt(for: .replace, isChinese: true)
                    == "将 modu 命令安装到 /usr/local/bin 需要管理员权限。"
            )
            #expect(
                CLIInstallerCommand.authorizationPrompt(for: .uninstall, isChinese: false)
                    == "Administrator permission is required to remove the modu command from /usr/local/bin."
            )
            #expect(
                CLIInstallerCommand.authorizationPrompt(for: .uninstall, isChinese: true)
                    == "从 /usr/local/bin 卸载 modu 命令需要管理员权限。"
            )

            let appURL = root
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("MoDu Preview's.app", isDirectory: true)
            let launcherURL = appURL
                .appendingPathComponent("Contents/Resources/CLI", isDirectory: true)
                .appendingPathComponent("modu")
            let installationDirectory = root.appendingPathComponent("bin", isDirectory: true)
            try FileManager.default.createDirectory(
                at: launcherURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: installationDirectory,
                withIntermediateDirectories: true
            )
            try "#!/bin/zsh\n".write(to: launcherURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: launcherURL.path
            )

            let targetURL = installationDirectory.appendingPathComponent("modu")
            let performOperation: CommandLineToolOperationPerformer = { operation, completion in
                let helperOperation: CLIInstallerOperation
                switch operation {
                case .install:
                    let targetExists = FileManager.default.fileExists(atPath: targetURL.path)
                        || (try? FileManager.default.destinationOfSymbolicLink(
                            atPath: targetURL.path
                        )) != nil
                    helperOperation = targetExists ? .replace : .install
                case .uninstall:
                    helperOperation = .uninstall
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [
                    "-c",
                    CLIInstallerCommand.privilegedShellCommand(
                        for: helperOperation,
                        sourceURL: launcherURL,
                        targetURL: targetURL
                    )
                ]
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw CommandLineToolInstallerError.helperLaunchFailed(
                        "Shell exited with \(process.terminationStatus)"
                    )
                }
                completion(.success(()))
            }
            let installer = CommandLineToolInstaller(
                applicationURL: appURL,
                bundledToolURL: launcherURL,
                installationURL: targetURL,
                performOperation: performOperation
            )

            try installer.install()
            #expect(installer.installedURL == targetURL.standardizedFileURL)
            #expect(
                try FileManager.default.destinationOfSymbolicLink(atPath: targetURL.path)
                    == launcherURL.path
            )

            let restoredInstaller = CommandLineToolInstaller(
                applicationURL: appURL,
                bundledToolURL: launcherURL,
                installationURL: targetURL,
                performOperation: performOperation
            )
            #expect(restoredInstaller.installedURL == targetURL.standardizedFileURL)

            try FileManager.default.removeItem(at: targetURL)
            try "existing\n".write(to: targetURL, atomically: true, encoding: .utf8)
            try installer.install()
            #expect(
                try FileManager.default.destinationOfSymbolicLink(atPath: targetURL.path)
                    == launcherURL.path
            )

            try installer.uninstall()
            #expect(installer.installedURL == nil)
            #expect(!FileManager.default.fileExists(atPath: targetURL.path))

            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
            #expect(throws: CommandLineToolInstallerError.targetIsDirectory) {
                try installer.install()
            }
        }
    }

    @Test("Local HTML resources round-trip through the bounded workspace scheme")
    func boundedLocalHTMLResource() throws {
        try withTemporaryRoot { root in
            let directory = root.appendingPathComponent("prototype", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let resourceURL = directory.appendingPathComponent("app.js")
            try Data("1234".utf8).write(to: resourceURL)
            let schemeURL = try #require(
                LocalResourceSchemeHandler.resourceURL(for: resourceURL, inside: root)
            )
            #expect(schemeURL.scheme == LocalDocumentResourcePolicy.resourceScheme)
            #expect(
                LocalResourceSchemeHandler.fileURL(for: schemeURL, inside: root)
                    == resourceURL.resolvingSymlinksInPath().standardizedFileURL
            )
            #expect(
                try FileSystemService.readData(at: resourceURL, inside: root, maximumBytes: 4)
                    == Data("1234".utf8)
            )
            #expect(throws: URLError.self) {
                try FileSystemService.readData(at: resourceURL, inside: root, maximumBytes: 3)
            }
        }
    }

    @Test("Initial interactive HTML navigation stays in the current web view")
    func initialInteractiveHTMLNavigation() throws {
        try withTemporaryRoot { root in
            let currentDocument = root.appendingPathComponent("current.html")
            let otherDocument = root.appendingPathComponent("other.html")

            #expect(
                MarkdownWebView.Coordinator.isExpectedInitialInteractiveNavigation(
                    isAwaitingInitialNavigation: true,
                    isMainFrame: true,
                    isOtherNavigation: true,
                    candidateURL: currentDocument,
                    currentDocumentURL: currentDocument
                )
            )
            #expect(
                !MarkdownWebView.Coordinator.isExpectedInitialInteractiveNavigation(
                    isAwaitingInitialNavigation: false,
                    isMainFrame: true,
                    isOtherNavigation: true,
                    candidateURL: currentDocument,
                    currentDocumentURL: currentDocument
                )
            )
            #expect(
                !MarkdownWebView.Coordinator.isExpectedInitialInteractiveNavigation(
                    isAwaitingInitialNavigation: true,
                    isMainFrame: false,
                    isOtherNavigation: true,
                    candidateURL: currentDocument,
                    currentDocumentURL: currentDocument
                )
            )
            #expect(
                !MarkdownWebView.Coordinator.isExpectedInitialInteractiveNavigation(
                    isAwaitingInitialNavigation: true,
                    isMainFrame: true,
                    isOtherNavigation: false,
                    candidateURL: currentDocument,
                    currentDocumentURL: currentDocument
                )
            )
            #expect(
                !MarkdownWebView.Coordinator.isExpectedInitialInteractiveNavigation(
                    isAwaitingInitialNavigation: true,
                    isMainFrame: true,
                    isOtherNavigation: true,
                    candidateURL: otherDocument,
                    currentDocumentURL: currentDocument
                )
            )
        }
    }

    @Test("Sandboxed srcdoc stays available only as a subframe")
    func sandboxedSrcdocNavigation() throws {
        let srcdocURL = try #require(URL(string: "about:srcdoc"))
        let srcdocAnchorURL = try #require(URL(string: "about:srcdoc#section"))

        #expect(
            MarkdownWebView.Coordinator.isAllowedInternalNavigation(
                url: srcdocURL,
                isMainFrame: false
            )
        )
        #expect(
            MarkdownWebView.Coordinator.isAllowedInternalNavigation(
                url: srcdocAnchorURL,
                isMainFrame: false
            )
        )
        #expect(
            !MarkdownWebView.Coordinator.isAllowedInternalNavigation(
                url: srcdocURL,
                isMainFrame: true
            )
        )
    }

    @Test("CR paging and cross-boundary search remain stable")
    func sourcePagingAndSearch() throws {
        try withTemporaryRoot { root in
            let bareCRURL = root.appendingPathComponent("bare-cr.txt")
            try String(repeating: "line\r", count: SourceFileSession.maximumPageLines + 1)
                .write(to: bareCRURL, atomically: true, encoding: .utf8)
            let bareCRSession = try SourceFileSession(fileURL: bareCRURL, rootURL: root)
            let firstPage = try bareCRSession.page(at: 0)
            #expect(firstPage.endLine == SourceFileSession.maximumPageLines)
            #expect(!firstPage.text.contains("\r"))

            let boundaryURL = root.appendingPathComponent("boundary.txt")
            let source = String(repeating: "x", count: SourceFileSession.maximumPageBytes - 3)
                + "BOUNDARY-tail"
            try source.write(to: boundaryURL, atomically: true, encoding: .utf8)
            let boundarySession = try SourceFileSession(fileURL: boundaryURL, rootURL: root)
            let match = try boundarySession.find(
                "BOUNDARY",
                caseSensitive: true,
                direction: .next,
                currentPageIndex: 0,
                currentMatch: nil
            ).match
            #expect(match?.pageIndex == 0)
            #expect(match?.range.location == SourceFileSession.maximumPageBytes - 3)
            #expect(match?.range.length == 3)
        }
    }

    @Test("Directory rename migrates all language overrides")
    @MainActor
    func languageOverrideMigration() throws {
        try withTemporaryRoot { root in
            let oldRoot = root.appendingPathComponent("old", isDirectory: true)
            let newRoot = root.appendingPathComponent("new", isDirectory: true)
            let unrelated = root.appendingPathComponent("unrelated.txt")
            let migrated = ReaderViewModel.migratingSourceLanguageOverrides(
                [
                    oldRoot.appendingPathComponent("Sources/Main.txt").path: .swift,
                    oldRoot.appendingPathComponent("Config/app.conf").path: .toml,
                    unrelated.path: .python
                ],
                from: oldRoot,
                to: newRoot
            )

            #expect(migrated[newRoot.appendingPathComponent("Sources/Main.txt").path] == .swift)
            #expect(migrated[newRoot.appendingPathComponent("Config/app.conf").path] == .toml)
            #expect(migrated[unrelated.path] == .python)
            #expect(!migrated.keys.contains { $0.hasPrefix(oldRoot.path + "/") })
        }
    }

    @Test("Failures preserve operation scope and recovery action")
    func typedFailures() {
        let loadFailure = ReaderFailure(
            error: SourceFileError.notRegularFile,
            operation: .documentLoad
        )
        let searchFailure = ReaderFailure(
            error: SourceFileError.notRegularFile,
            operation: .documentSearch
        )

        #expect(loadFailure.category == .sourceFile)
        #expect(loadFailure.recoveryAction == .reloadDocument)
        #expect(searchFailure.operation == .documentSearch)
        #expect(searchFailure.recoveryAction == .retryOperation)
    }

    @Test("Pane migration cancels every task and normalizes transient state")
    @MainActor
    func paneMigrationLifecycle() {
        let documentTask = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        let previousTask = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        let nextTask = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        let lineTask = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        let oldGeneration = UUID()
        var state = ReaderPaneState()
        state.documentTask = documentTask
        state.documentGeneration = oldGeneration
        state.sourceViewportTasks = [
            .previous: PaneTaskRegistration(id: UUID(), task: previousTask),
            .next: PaneTaskRegistration(id: UUID(), task: nextTask)
        ]
        state.sourceLineJumpTask = PaneTaskRegistration(id: UUID(), task: lineTask)
        state.documentSearchState.isPresented = true
        state.documentSearchState.isSearching = true
        state.sourceLineJumpState.isPresented = true
        state.sourceLineJumpState.isResolving = true

        state.prepareForMove()

        #expect(documentTask.isCancelled)
        #expect(previousTask.isCancelled)
        #expect(nextTask.isCancelled)
        #expect(lineTask.isCancelled)
        #expect(state.documentTask == nil)
        #expect(state.sourceViewportTasks.isEmpty)
        #expect(state.sourceLineJumpTask == nil)
        #expect(state.documentGeneration != oldGeneration)
        #expect(!state.documentSearchState.isSearching)
        #expect(!state.sourceLineJumpState.isResolving)
        #expect(state.documentSearchFocusRequest != nil)
        #expect(state.sourceLineJumpFocusRequest != nil)
    }

    @Test("Reader view model closes both pane directions without leaking transient work")
    @MainActor
    func readerViewModelClosePaneLifecycle() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("modu-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let referenceURL = root.appendingPathComponent("reference.swift")
        try "let value = 1\n".write(to: referenceURL, atomically: true, encoding: .utf8)
        let barrier = DocumentLoadBarrier()
        let model = ReaderViewModel(
            restorePersistedState: false,
            documentLoadCompletionBarrier: { _, generation in
                await barrier.wait(for: generation)
            }
        )
        model.installWorkspaceForTesting(root)
        model.toggleSplitReading()
        model.loadDocument(at: referenceURL, in: .reference)
        #expect(await waitUntil { await barrier.generations().count == 1 })
        let firstGeneration = try #require(await barrier.generations().first)

        model.closePane(.primary)
        #expect(await waitUntil { await barrier.generations().count == 2 })
        let generations = await barrier.generations()
        let resumedGeneration = try #require(generations.last)
        #expect(resumedGeneration != firstGeneration)
        #expect(model.activePane == .primary)
        #expect(model.selectedURL == referenceURL)
        #expect(model.referenceURL == nil)
        let moved = model.paneStateForTesting(.primary)
        #expect(moved?.documentGeneration == resumedGeneration)
        #expect(moved?.documentTask != nil)

        await barrier.release(resumedGeneration)
        #expect(await waitUntil {
            if case .loaded(let url, _) = model.documentState { return url == referenceURL }
            return false
        })
        let loadedDocumentID: UUID
        if case .loaded(_, let document) = model.documentState {
            loadedDocumentID = document.id
        } else {
            Issue.record("迁移后的新加载任务未完成")
            return
        }

        await barrier.release(firstGeneration)
        for _ in 0..<20 { await Task.yield() }
        if case .loaded(_, let document) = model.documentState {
            #expect(document.id == loadedDocumentID)
        } else {
            Issue.record("旧 generation 回写覆盖了新文档")
        }

        let replacementReferenceTask = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        var replacementReference = ReaderPaneState()
        replacementReference.selectedURL = referenceURL
        replacementReference.documentState = .loading(referenceURL)
        replacementReference.documentTask = replacementReferenceTask
        model.installPaneStateForTesting(replacementReference, in: .reference)
        model.activatePane(.reference)
        model.closePane(.reference)

        #expect(replacementReferenceTask.isCancelled)
        #expect(model.activePane == .primary)
        #expect(model.selectedURL == referenceURL)
        #expect(model.referenceURL == nil)
    }

    @Test("Source session keeps the validated in-workspace target after symlink retargeting")
    func sourceSessionSymlinkIdentity() throws {
        try withTemporaryRoot { root in
            let target = root.appendingPathComponent("inside.txt")
            let link = root.appendingPathComponent("link.txt")
            try "inside\n".write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let session = try SourceFileSession(fileURL: link, rootURL: root)

            let outside = FileManager.default.temporaryDirectory
                .appendingPathComponent("modu-outside-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: outside) }
            try "outside\n".write(to: outside, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

            #expect(try session.page(at: 0).text == "inside\n")
            #expect(throws: FileSystemError.self) {
                try FileSystemService.validatedURL(link, inside: root)
            }
        }
    }

    private func withTemporaryRoot<T>(_ body: (URL) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("modu-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try body(root)
    }

    @MainActor
    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }
}

private actor DocumentLoadBarrier {
    private var order: [UUID] = []
    private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    func wait(for generation: UUID) async {
        order.append(generation)
        await withCheckedContinuation { continuation in
            continuations[generation] = continuation
        }
    }

    func generations() -> [UUID] {
        order
    }

    func release(_ generation: UUID) {
        continuations.removeValue(forKey: generation)?.resume()
    }
}

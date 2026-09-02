import AppKit
import Darwin
import SwiftUI

private final class ReaderWindowSession {
    weak var window: NSWindow?
    weak var model: ReaderViewModel?

    init(window: NSWindow, model: ReaderViewModel) {
        self.window = window
        self.model = model
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var webViewSelfCheck: WebViewSelfCheck?
    private var readerWindows: [UUID: ReaderWindowSession] = [:]
    private var activeReaderWindowID: UUID?
    private var pendingWorkspaceOpenRequest: WorkspaceOpenRequest?
    private var pendingNewWindowOpenRequests: [WorkspaceOpenRequest] = []
    private var openReaderWindowAction: (() -> Void)?
    private var bufferedExternalURLs: [URL] = []
    private var bufferedExternalTargetWindowID: UUID?
    private var externalURLFlushTask: Task<Void, Never>?
    private var handledCommandLineRequestIDs: Set<UUID> = []
    private var debugArgumentsHandled = false

    #if DEBUG
    func applicationWillFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-check") {
            Darwin.exit(SelfCheck.run())
        }
    }
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--webview-self-check") {
            let check = WebViewSelfCheck()
            webViewSelfCheck = check
            check.run()
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        enqueueExternalURLs(urls)
        application.activate(ignoringOtherApps: true)
    }

    func receiveExternalURL(_ url: URL, inReaderWindow id: UUID) {
        if readerWindows[id]?.model != nil {
            bufferedExternalTargetWindowID = id
        }
        enqueueExternalURLs([url])
    }

    func registerReaderWindowOpener(_ action: @escaping () -> Void) {
        openReaderWindowAction = action
    }

    func registerReaderWindow(
        id: UUID,
        window: NSWindow,
        model: ReaderViewModel
    ) {
        removeReleasedReaderWindows()
        let isNewRegistration = readerWindows[id] == nil
        readerWindows[id] = ReaderWindowSession(window: window, model: model)

        if isNewRegistration, !pendingNewWindowOpenRequests.isEmpty {
            let request = pendingNewWindowOpenRequests.removeFirst()
            activeReaderWindowID = id
            model.openWorkspace(request)
            return
        }

        if window.isKeyWindow || (activeReaderWindowID == nil && readerWindows.count == 1) {
            readerWindowDidBecomeKey(id: id)
        }
    }

    func readerWindowDidBecomeKey(id: UUID) {
        removeReleasedReaderWindows()
        guard readerWindows[id]?.model != nil else { return }
        activeReaderWindowID = id
        deliverPendingWorkspaceOpenRequestIfPossible()
    }

    func unregisterReaderWindow(id: UUID) {
        readerWindows.removeValue(forKey: id)
        if activeReaderWindowID == id {
            activeReaderWindowID = nil
        }
        removeReleasedReaderWindows()
    }

    func openDebugArgumentsIfNeeded(using model: ReaderViewModel) {
        guard !debugArgumentsHandled else { return }
        debugArgumentsHandled = true
        model.openDebugArgumentsIfNeeded()
    }

    func routeWorkspaceOpenRequest(_ request: WorkspaceOpenRequest) {
        removeReleasedReaderWindows()
        guard let model = activeReaderModel() else {
            pendingWorkspaceOpenRequest = Self.mergedWorkspaceOpenRequest(
                pendingWorkspaceOpenRequest,
                request
            )
            return
        }
        pendingWorkspaceOpenRequest = nil
        if
            request.documentURL == nil,
            model.rootURL?.standardizedFileURL == request.workspaceURL
        {
            return
        }
        model.openWorkspace(request)
    }

    func routeWorkspaceOpenRequestInNewWindow(_ request: WorkspaceOpenRequest) {
        removeReleasedReaderWindows()
        guard !readerWindows.isEmpty, let openReaderWindowAction else {
            routeWorkspaceOpenRequest(request)
            return
        }

        pendingNewWindowOpenRequests.append(request)
        openReaderWindowAction()
    }

    private func enqueueExternalURLs(_ urls: [URL]) {
        for url in urls where !bufferedExternalURLs.contains(url) {
            bufferedExternalURLs.append(url)
        }

        externalURLFlushTask?.cancel()
        externalURLFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.flushExternalURLs()
        }
    }

    private func flushExternalURLs() {
        let urls = bufferedExternalURLs
        let targetWindowID = bufferedExternalTargetWindowID
        bufferedExternalURLs = []
        bufferedExternalTargetWindowID = nil
        externalURLFlushTask = nil

        processExternalURLs(
            urls,
            targetWindowID: targetWindowID
        )
    }

    func processExternalURLs(
        _ urls: [URL],
        targetWindowID: UUID? = nil
    ) {
        let containsCommandLineMarker = urls.contains(
            where: WorkspaceOpenRequest.isCommandLineWindowMarker
        )
        if containsCommandLineMarker {
            let commandLineRequests = WorkspaceOpenRequest.commandLineWindowRequests(
                from: urls
            )
            for commandLineRequest in commandLineRequests {
                guard rememberCommandLineRequest(commandLineRequest.id) else { continue }
                if commandLineRequest.opensNewWindow {
                    routeWorkspaceOpenRequestInNewWindow(
                        commandLineRequest.workspaceRequest
                    )
                } else {
                    routeWorkspaceOpenRequest(commandLineRequest.workspaceRequest)
                }
            }
            return
        }

        guard let request = WorkspaceOpenRequest.resolve(urls: urls) else { return }
        if let targetWindowID, readerWindows[targetWindowID]?.model != nil {
            activeReaderWindowID = targetWindowID
        }
        routeWorkspaceOpenRequest(request)
    }

    private func rememberCommandLineRequest(_ id: UUID) -> Bool {
        guard handledCommandLineRequestIDs.insert(id).inserted else { return false }
        if handledCommandLineRequestIDs.count > 64 {
            handledCommandLineRequestIDs = [id]
        }
        return true
    }

    private static func mergedWorkspaceOpenRequest(
        _ current: WorkspaceOpenRequest?,
        _ incoming: WorkspaceOpenRequest
    ) -> WorkspaceOpenRequest {
        guard
            let current,
            current.workspaceURL == incoming.workspaceURL
        else { return incoming }

        return WorkspaceOpenRequest(
            id: incoming.id,
            workspaceURL: incoming.workspaceURL,
            documentURL: incoming.documentURL ?? current.documentURL
        )
    }

    private func activeReaderModel() -> ReaderViewModel? {
        if
            let activeReaderWindowID,
            let model = readerWindows[activeReaderWindowID]?.model
        {
            return model
        }

        guard let keyWindow = NSApp.keyWindow else { return nil }
        guard let match = readerWindows.first(where: { $0.value.window === keyWindow }) else {
            return nil
        }
        activeReaderWindowID = match.key
        return match.value.model
    }

    private func deliverPendingWorkspaceOpenRequestIfPossible() {
        guard
            let request = pendingWorkspaceOpenRequest,
            let model = activeReaderModel()
        else { return }
        pendingWorkspaceOpenRequest = nil
        model.openWorkspace(request)
    }

    private func removeReleasedReaderWindows() {
        let releasedIDs = readerWindows.compactMap { id, session in
            session.window == nil || session.model == nil ? id : nil
        }
        for id in releasedIDs {
            readerWindows.removeValue(forKey: id)
            if activeReaderWindowID == id {
                activeReaderWindowID = nil
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MoDuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var applicationState = ApplicationState()

    var body: some Scene {
        WindowGroup(L10n.string(.appName), id: MoDuWindow.readerSceneID) {
            ReaderWindowView(applicationState: applicationState)
                .environmentObject(appDelegate)
                .frame(minWidth: 1160, minHeight: 620)
        }
        .defaultSize(width: 1440, height: 860)
        .commands {
            MoDuReaderCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(applicationState)
                .preferredColorScheme(applicationState.appAppearance.preferredColorScheme)
        }
    }
}

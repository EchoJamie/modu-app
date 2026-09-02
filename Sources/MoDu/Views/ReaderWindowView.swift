import AppKit
import SwiftUI

struct ReaderWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appDelegate: AppDelegate
    @StateObject private var model: ReaderViewModel
    @State private var windowID = UUID()

    init(applicationState: ApplicationState) {
        _model = StateObject(
            wrappedValue: ReaderViewModel(applicationState: applicationState)
        )
    }

    var body: some View {
        RootView()
            .environmentObject(model)
            .preferredColorScheme(model.appAppearance.preferredColorScheme)
            .focusedSceneObject(model)
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .onOpenURL { url in
                appDelegate.receiveExternalURL(url, inReaderWindow: windowID)
            }
            .background(
                ReaderWindowRegistrationView(
                    id: windowID,
                    appDelegate: appDelegate,
                    model: model
                )
            )
            .onAppear {
                appDelegate.registerReaderWindowOpener {
                    openWindow(id: MoDuWindow.readerSceneID)
                }
                appDelegate.openDebugArgumentsIfNeeded(using: model)
            }
    }
}

private struct ReaderWindowRegistrationView: NSViewRepresentable {
    let id: UUID
    let appDelegate: AppDelegate
    let model: ReaderViewModel

    func makeNSView(context: Context) -> ReaderWindowRegistrationNSView {
        let view = ReaderWindowRegistrationNSView()
        view.configure(id: id, appDelegate: appDelegate, model: model)
        return view
    }

    func updateNSView(_ nsView: ReaderWindowRegistrationNSView, context: Context) {
        nsView.configure(id: id, appDelegate: appDelegate, model: model)
    }

    static func dismantleNSView(
        _ nsView: ReaderWindowRegistrationNSView,
        coordinator: Void
    ) {
        nsView.unregister()
    }
}

@MainActor
private final class ReaderWindowRegistrationNSView: NSView {
    private var id: UUID?
    private weak var appDelegate: AppDelegate?
    private weak var model: ReaderViewModel?
    private weak var registeredWindow: NSWindow?

    func configure(
        id: UUID,
        appDelegate: AppDelegate,
        model: ReaderViewModel
    ) {
        self.id = id
        self.appDelegate = appDelegate
        self.model = model
        updateRegistration()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRegistration()
    }

    func unregister() {
        stopObservingWindow()
        guard let id else { return }
        appDelegate?.unregisterReaderWindow(id: id)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard notification.object as? NSWindow === registeredWindow, let id else { return }
        appDelegate?.readerWindowDidBecomeKey(id: id)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === registeredWindow else { return }
        unregister()
    }

    private func updateRegistration() {
        guard registeredWindow !== window else { return }
        stopObservingWindow()
        guard
            let window,
            let id,
            let appDelegate,
            let model
        else { return }

        registeredWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        appDelegate.registerReaderWindow(id: id, window: window, model: model)
    }

    private func stopObservingWindow() {
        guard let registeredWindow else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: registeredWindow
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: registeredWindow
        )
        self.registeredWindow = nil
    }
}

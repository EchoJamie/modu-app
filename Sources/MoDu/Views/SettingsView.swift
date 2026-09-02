import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(
                        L10n.string(.settingsGeneralTitle),
                        systemImage: "gearshape"
                    )
                }

            CommandLineSettingsView()
                .tabItem {
                    Label(
                        L10n.string(.settingsCLITitle),
                        systemImage: "terminal"
                    )
                }
        }
        .frame(width: 560, height: 180)
        .background(SettingsWindowFocusResetter())
    }
}

struct SettingsWindowFocusResetter: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowFocusResetView {
        SettingsWindowFocusResetView()
    }

    func updateNSView(_ nsView: SettingsWindowFocusResetView, context: Context) {}
}

final class SettingsWindowFocusResetView: NSView {
    private weak var observedWindow: NSWindow?
    private var shouldResetOnNextActivation = true

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let observedWindow {
            NotificationCenter.default.removeObserver(self, name: nil, object: observedWindow)
        }
        observedWindow = window

        guard let window else { return }
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
        scheduleFocusReset()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        scheduleFocusReset()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        shouldResetOnNextActivation = true
    }

    private func scheduleFocusReset() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(resetWindowFocus),
            object: nil
        )
        perform(#selector(resetWindowFocus), with: nil, afterDelay: 0)
    }

    @objc private func resetWindowFocus() {
        guard shouldResetOnNextActivation, let window else { return }
        if SettingsWindowFocusPolicy.clearInitialFocus(in: window) {
            shouldResetOnNextActivation = false
        }
    }
}

enum SettingsWindowFocusPolicy {
    @discardableResult
    static func clearInitialFocus(in window: NSWindow) -> Bool {
        window.initialFirstResponder = nil
        return window.makeFirstResponder(nil)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var model: ReaderViewModel

    var body: some View {
        Form {
            Section {
                Picker(L10n.string(.settingsLanguage), selection: languageSelection) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.name).tag(language)
                    }
                }

                Picker(L10n.string(.settingsAppearance), selection: appearanceSelection) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(appearance.name, systemImage: appearance.symbol)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }

    private var languageSelection: Binding<AppLanguage> {
        Binding(
            get: { model.appLanguage },
            set: { model.selectAppLanguage($0) }
        )
    }

    private var appearanceSelection: Binding<AppAppearance> {
        Binding(
            get: { model.appAppearance },
            set: { model.selectAppAppearance($0) }
        )
    }
}

private struct CommandLineSettingsView: View {
    @StateObject private var commandLineToolInstaller = CommandLineToolInstaller()

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.string(.settingsCLITitle))
                                .font(.headline)
                            Text(L10n.string(.settingsCLIDescription))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "terminal")
                            .font(.title2)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            if commandLineToolInstaller.isPerformingOperation {
                                HStack(spacing: 7) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(L10n.string(.settingsCLIAuthorizing))
                                }
                            } else {
                                Text(commandLineToolInstaller.isInstalled
                                    ? L10n.string(.settingsCLIInstalled)
                                    : L10n.string(.settingsCLINotInstalled))
                            }
                            if let installedURL = commandLineToolInstaller.installedURL {
                                Text(installedURL.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        Spacer()

                        Group {
                            if commandLineToolInstaller.isInstalled {
                                Button(
                                    L10n.string(.settingsCLIUninstall),
                                    role: .destructive
                                ) {
                                    commandLineToolInstaller.uninstallFromSettings()
                                }
                            } else {
                                Button(L10n.string(.settingsCLIInstall)) {
                                    commandLineToolInstaller.installFromSettings()
                                }
                            }
                        }
                        .disabled(commandLineToolInstaller.isPerformingOperation)
                    }

                    if let errorMessage = commandLineToolInstaller.errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            commandLineToolInstaller.refreshInstallationStatus()
        }
    }
}

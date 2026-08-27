import AppKit
import Darwin
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var webViewSelfCheck: WebViewSelfCheck?

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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MoDuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ReaderViewModel()

    var body: some Scene {
        WindowGroup(L10n.string(.appName)) {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(model.appAppearance.preferredColorScheme)
                .frame(minWidth: 1160, minHeight: 620)
        }
        .defaultSize(width: 1440, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.string(.commandOpenFolder)) {
                    model.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: .command)

                if !model.recentWorkspaces.isEmpty {
                    Menu(L10n.string(.commandOpenRecent)) {
                        ForEach(model.recentWorkspaces) { workspace in
                            Button(workspace.name) {
                                model.openRecentWorkspace(workspace)
                            }
                            .help(workspace.displayPath)
                            .disabled(workspace.id == model.rootURL?.standardizedFileURL.path)
                        }

                        Divider()

                        Button(L10n.string(.commandClearMenu)) {
                            model.clearRecentWorkspaces()
                        }
                    }
                }
            }

            CommandMenu(L10n.string(.commandReading)) {
                Button(L10n.string(.commandReloadDocumentOutline)) {
                    model.reloadActiveDocument()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.canReloadActiveDocument)

                Button(L10n.string(.commandReloadDirectory)) {
                    model.rescanWorkspace()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(model.rootURL == nil)

                Button(L10n.string(.commandFindInDocument)) {
                    model.requestDocumentSearchFocus()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!model.canFindInActiveDocument)

                Button(L10n.string(.commandGoToLine)) {
                    model.requestSourceLineJumpFocus()
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!model.canJumpToLineInActiveDocument)

                Divider()

                Menu(L10n.string(.commandTheme)) {
                    ForEach(MarkdownStyle.allCases) { style in
                        Toggle(style.name, isOn: themeSelection(style))
                            .help(style.subtitle)
                    }
                }

                Menu(L10n.string(.commandDisplayMode)) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Toggle(appearance.name, isOn: appearanceSelection(appearance))
                    }
                }

                Divider()

                Button(L10n.string(model.hasSecondPane
                    ? .commandCloseActivePane
                    : .commandOpenSecondPane)) {
                    model.toggleSplitReading()
                }
                .keyboardShortcut("\\", modifiers: .command)

                Divider()

                Button(L10n.string(model.outlineIsVisible ? .outlineHide : .outlineShow)) {
                    model.outlineIsVisible.toggle()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }
    }

    private func appearanceSelection(_ appearance: AppAppearance) -> Binding<Bool> {
        Binding(
            get: { model.appAppearance == appearance },
            set: { isSelected in
                guard isSelected else { return }
                model.selectAppAppearance(appearance)
            }
        )
    }

    private func themeSelection(_ style: MarkdownStyle) -> Binding<Bool> {
        Binding(
            get: { model.markdownStyle == style },
            set: { isSelected in
                guard isSelected else { return }
                model.selectMarkdownStyle(style)
            }
        )
    }
}

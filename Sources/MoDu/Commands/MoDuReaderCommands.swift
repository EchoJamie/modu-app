import SwiftUI

enum MoDuWindow {
    static let readerSceneID = "reader"
}

struct MoDuReaderCommands: Commands {
    @ObservedObject var applicationState: ApplicationState
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var model: ReaderViewModel?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.string(.commandNewWindow)) {
                openWindow(id: MoDuWindow.readerSceneID)
            }
            .keyboardShortcut(applicationState.shortcut(for: .newWindow).keyboardShortcut)

            Divider()

            Button(L10n.string(.commandOpenFolder)) {
                model?.chooseFolder()
            }
            .keyboardShortcut(applicationState.shortcut(for: .openFolder).keyboardShortcut)
            .disabled(model == nil)

            if let model, !model.recentWorkspaces.isEmpty {
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
                    .disabled(!model.canClearRecentWorkspaces)
                }
            }
        }

        CommandMenu(L10n.string(.commandReading)) {
            Button(L10n.string(.commandReloadDocumentOutline)) {
                model?.reloadActiveDocument()
            }
            .keyboardShortcut(applicationState.shortcut(for: .reloadDocument).keyboardShortcut)
            .disabled(model?.canReloadActiveDocument != true)

            Button(L10n.string(.commandReloadDirectory)) {
                model?.rescanWorkspace()
            }
            .keyboardShortcut(applicationState.shortcut(for: .reloadDirectory).keyboardShortcut)
            .disabled(model?.rootURL == nil)

            Button(L10n.string(.commandFindInDocument)) {
                model?.requestDocumentSearchFocus()
            }
            .keyboardShortcut(applicationState.shortcut(for: .findInDocument).keyboardShortcut)
            .disabled(model?.canFindInActiveDocument != true)

            Button(L10n.string(.commandGoToLine)) {
                model?.requestSourceLineJumpFocus()
            }
            .keyboardShortcut(applicationState.shortcut(for: .goToLine).keyboardShortcut)
            .disabled(model?.canJumpToLineInActiveDocument != true)

            Divider()

            Menu(L10n.string(.commandTheme)) {
                ForEach(MarkdownStyle.allCases) { style in
                    Toggle(style.name, isOn: themeSelection(style))
                        .help(style.subtitle)
                        .disabled(model == nil)
                }
            }

            Divider()

            Button(L10n.string(model?.hasSecondPane == true
                ? .commandCloseActivePane
                : .commandOpenSecondPane)) {
                model?.toggleSplitReading()
            }
            .keyboardShortcut(applicationState.shortcut(for: .toggleSplitReading).keyboardShortcut)
            .disabled(model == nil)

            Divider()

            Button(L10n.string(model?.sidebarIsVisible == false ? .sidebarShow : .sidebarHide)) {
                model?.toggleSidebar()
            }
            .keyboardShortcut(applicationState.shortcut(for: .toggleSidebar).keyboardShortcut)
            .disabled(model == nil)

            Button(L10n.string(model?.outlineIsVisible == false
                ? .outlineShow
                : .outlineHide)) {
                model?.outlineIsVisible.toggle()
            }
            .keyboardShortcut(applicationState.shortcut(for: .toggleOutline).keyboardShortcut)
            .disabled(model == nil)
        }
    }

    private func themeSelection(_ style: MarkdownStyle) -> Binding<Bool> {
        Binding(
            get: { model?.markdownStyle == style },
            set: { isSelected in
                guard isSelected else { return }
                model?.selectMarkdownStyle(style)
            }
        )
    }
}

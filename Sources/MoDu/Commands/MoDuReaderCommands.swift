import SwiftUI

enum MoDuWindow {
    static let readerSceneID = "reader"
}

struct MoDuReaderCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var model: ReaderViewModel?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.string(.commandNewWindow)) {
                openWindow(id: MoDuWindow.readerSceneID)
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button(L10n.string(.commandOpenFolder)) {
                model?.chooseFolder()
            }
            .keyboardShortcut("o", modifiers: .command)
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
                }
            }
        }

        CommandMenu(L10n.string(.commandReading)) {
            Button(L10n.string(.commandReloadDocumentOutline)) {
                model?.reloadActiveDocument()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model?.canReloadActiveDocument != true)

            Button(L10n.string(.commandReloadDirectory)) {
                model?.rescanWorkspace()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(model?.rootURL == nil)

            Button(L10n.string(.commandFindInDocument)) {
                model?.requestDocumentSearchFocus()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(model?.canFindInActiveDocument != true)

            Button(L10n.string(.commandGoToLine)) {
                model?.requestSourceLineJumpFocus()
            }
            .keyboardShortcut("l", modifiers: .command)
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
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(model == nil)

            Divider()

            Button(L10n.string(model?.outlineIsVisible == false
                ? .outlineShow
                : .outlineHide)) {
                model?.outlineIsVisible.toggle()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
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

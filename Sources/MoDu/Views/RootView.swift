import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: ReaderViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var outlinePanelWidth = OutlinePanelLayout.restoredWidth()

    private var theme: ResolvedReaderTheme { model.resolvedTheme }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 268, max: 360)
        } detail: {
            ResizableOutlineLayout(
                outlineIsVisible: model.outlineIsVisible,
                minimumContentWidth: model.hasSecondPane ? 640 : 320,
                preferredOutlineWidth: $outlinePanelWidth,
                minimumOutlineWidth: OutlinePanelLayout.minimumWidth,
                maximumOutlineWidth: OutlinePanelLayout.maximumWidth,
                dividerColor: theme.divider,
                onOutlineWidthCommit: persistOutlinePanelWidth
            ) {
                readerPanes
            } outline: {
                OutlineView(
                    items: model.outlineItems(for: model.activePane),
                    pane: model.activePane
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.reloadActiveDocument()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!model.canReloadActiveDocument)
                .help(L10n.string(.toolbarReloadHelp))

                Button {
                    model.toggleSplitReading()
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .symbolVariant(model.hasSecondPane ? .fill : .none)
                }
                .help(L10n.string(model.hasSecondPane
                    ? .toolbarCloseSplitHelp
                    : .toolbarOpenSplitHelp))
                .accessibilityLabel(L10n.string(model.hasSecondPane
                    ? .commandCloseActivePane
                    : .commandOpenSecondPane))

                themeMenu
                displayModeMenu

                Button {
                    model.outlineIsVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .symbolVariant(model.outlineIsVisible ? .fill : .none)
                }
                .help(L10n.string(model.outlineIsVisible ? .outlineHide : .outlineShow))
            }
        }
        .tint(theme.accent)
        .background(theme.canvas)
        .onAppear {
            model.updateSystemColorScheme(colorScheme)
            model.openDebugArgumentsIfNeeded()
        }
        .onChange(of: colorScheme) { newColorScheme in
            model.updateSystemColorScheme(newColorScheme)
        }
    }

    @ViewBuilder
    private var readerPanes: some View {
        if model.hasSecondPane {
            HSplitView {
                DocumentView(pane: .primary)
                    .frame(minWidth: 280, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

                DocumentView(pane: .reference)
                    .frame(minWidth: 280, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 640)
        } else {
            DocumentView(pane: .primary)
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func persistOutlinePanelWidth(_ width: CGFloat) {
        let clampedWidth = OutlinePanelLayout.clamped(width)
        UserDefaults.standard.set(
            Double(clampedWidth),
            forKey: OutlinePanelLayout.storageKey
        )
    }

    private var displayModeMenu: some View {
        Menu {
            ForEach(AppAppearance.allCases) { appearance in
                Button {
                    model.selectAppAppearance(appearance)
                } label: {
                    Label(
                        appearance.name,
                        systemImage: model.appAppearance == appearance
                            ? "checkmark.circle.fill"
                            : appearance.symbol
                    )
                }
            }
        } label: {
            Image(systemName: model.appAppearance.symbol)
        }
        .help(L10n.format(.toolbarDisplayModeHelp, model.appAppearance.name))
    }

    private var themeMenu: some View {
        Menu {
            ForEach(MarkdownStyle.allCases) { style in
                Button {
                    model.selectMarkdownStyle(style)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(style.name)
                            Text(style.subtitle)
                        }
                    } icon: {
                        Image(systemName: model.markdownStyle == style
                            ? "checkmark.circle.fill"
                            : style.symbol)
                    }
                }
            }
        } label: {
            Image(systemName: model.markdownStyle.symbol)
        }
        .help(L10n.format(.toolbarThemeHelp, model.markdownStyle.name))
    }
}

private enum OutlinePanelLayout {
    static let minimumWidth: CGFloat = 260
    static let defaultWidth: CGFloat = 310
    static let maximumWidth: CGFloat = 560
    static let storageKey = "outlinePanelWidth.v1"

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumWidth), maximumWidth)
    }

    static func restoredWidth() -> CGFloat {
        let storedWidth = UserDefaults.standard.double(forKey: storageKey)
        guard storedWidth > 0 else { return defaultWidth }
        return clamped(CGFloat(storedWidth))
    }
}

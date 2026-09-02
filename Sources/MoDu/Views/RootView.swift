import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: ReaderViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var outlinePanelWidth = OutlinePanelLayout.restoredWidth()

    private var theme: ResolvedReaderTheme { model.resolvedTheme }

    var body: some View {
        GeometryReader { geometry in
            let panelMaximumWidth = SidePanelLayout.maximumWidth(
                forWindowWidth: geometry.size.width
            )

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(
                        min: SidePanelLayout.sidebarMinimumWidth,
                        ideal: SidePanelLayout.sidebarIdealWidth,
                        max: panelMaximumWidth
                    )
            } detail: {
                ResizableOutlineLayout(
                    outlineIsVisible: model.outlineIsVisible,
                    minimumContentWidth: model.hasSecondPane ? 640 : 320,
                    preferredOutlineWidth: $outlinePanelWidth,
                    minimumOutlineWidth: OutlinePanelLayout.minimumWidth,
                    maximumOutlineWidth: panelMaximumWidth,
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
                    .focusable(false)
                    .help(L10n.string(.toolbarReloadHelp))

                    Button {
                        model.toggleSplitReading()
                    } label: {
                        Image(systemName: "rectangle.split.2x1")
                            .symbolVariant(model.hasSecondPane ? .fill : .none)
                    }
                    .focusable(false)
                    .help(L10n.string(model.hasSecondPane
                        ? .toolbarCloseSplitHelp
                        : .toolbarOpenSplitHelp))
                    .accessibilityLabel(L10n.string(model.hasSecondPane
                        ? .commandCloseActivePane
                        : .commandOpenSecondPane))

                    themeMenu

                    Button {
                        model.outlineIsVisible.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                            .symbolVariant(model.outlineIsVisible ? .fill : .none)
                    }
                    .focusable(false)
                    .help(L10n.string(model.outlineIsVisible ? .outlineHide : .outlineShow))
                }
            }
            .tint(theme.accent)
            .background(theme.canvas)
            .onAppear {
                model.updateSystemColorScheme(colorScheme)
            }
            .onChange(of: colorScheme) { newColorScheme in
                model.updateSystemColorScheme(newColorScheme)
            }
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
        let clampedWidth = OutlinePanelLayout.clampedToMinimum(width)
        UserDefaults.standard.set(
            Double(clampedWidth),
            forKey: OutlinePanelLayout.storageKey
        )
    }

    private var themeMenu: some View {
        Menu {
            ForEach(MarkdownStyle.allCases) { style in
                Toggle(isOn: themeSelection(style)) {
                    Label {
                        VStack(alignment: .leading) {
                            Text(style.name)
                            Text(style.subtitle)
                        }
                    } icon: {
                        Image(systemName: style.symbol)
                    }
                }
            }
        } label: {
            Image(systemName: model.markdownStyle.symbol)
        }
        .focusable(false)
        .help(L10n.format(.toolbarThemeHelp, model.markdownStyle.name))
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

private enum OutlinePanelLayout {
    static let minimumWidth: CGFloat = 260
    static let defaultWidth: CGFloat = 310
    static let storageKey = "outlinePanelWidth.v1"

    static func clampedToMinimum(_ width: CGFloat) -> CGFloat {
        max(width, minimumWidth)
    }

    static func restoredWidth() -> CGFloat {
        let storedWidth = UserDefaults.standard.double(forKey: storageKey)
        guard storedWidth > 0 else { return defaultWidth }
        return clampedToMinimum(CGFloat(storedWidth))
    }
}

enum SidePanelLayout {
    static let sidebarMinimumWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 268
    static let maximumWindowFraction: CGFloat = 1 / 3

    static func maximumWidth(forWindowWidth width: CGFloat) -> CGFloat {
        max(
            max(sidebarMinimumWidth, OutlinePanelLayout.minimumWidth),
            width * maximumWindowFraction
        )
    }
}

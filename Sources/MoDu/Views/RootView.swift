import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: ReaderViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var sidebarPanelWidth = SidePanelLayout.restoredSidebarWidth()
    @State private var outlinePanelWidth = OutlinePanelLayout.restoredWidth()

    private var theme: ResolvedReaderTheme { model.resolvedTheme }

    var body: some View {
        GeometryReader { geometry in
            let panelMaximumWidth = SidePanelLayout.maximumWidth(
                forWindowWidth: geometry.size.width
            )

            ResizableSidePanelLayout(
                panelIsVisible: model.sidebarIsVisible,
                edge: .leading,
                minimumContentWidth: (model.hasSecondPane ? 640 : 320)
                    + (model.outlineIsVisible ? OutlinePanelLayout.minimumWidth : 0),
                preferredPanelWidth: $sidebarPanelWidth,
                minimumPanelWidth: SidePanelLayout.sidebarMinimumWidth,
                maximumPanelWidth: panelMaximumWidth,
                dividerColor: theme.divider,
                onPanelWidthCommit: persistSidebarPanelWidth
            ) {
                VStack(spacing: 0) {
                    readerTitlebar
                    Divider().overlay(theme.divider.opacity(0.75))

                    ResizableSidePanelLayout(
                        panelIsVisible: model.outlineIsVisible,
                        edge: .trailing,
                        minimumContentWidth: model.hasSecondPane ? 640 : 320,
                        preferredPanelWidth: $outlinePanelWidth,
                        minimumPanelWidth: OutlinePanelLayout.minimumWidth,
                        maximumPanelWidth: panelMaximumWidth,
                        dividerColor: theme.divider,
                        onPanelWidthCommit: persistOutlinePanelWidth
                    ) {
                        readerPanes
                    } panel: {
                        OutlineView(
                            items: model.outlineItems(for: model.activePane),
                            pane: model.activePane
                        )
                    }
                }
            } panel: {
                VStack(spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        sidebarToggle
                    }
                    // The native traffic lights remain in the leading titlebar area.
                    .padding(.leading, 80)
                    .padding(.trailing, 10)
                    .frame(height: 38)
                    .background(WindowTitlebarDragArea())
                    .background(theme.chrome)

                    Divider().overlay(theme.divider.opacity(0.75))
                    SidebarView()
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
        .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebarToggle: some View {
        Button {
            model.toggleSidebar()
        } label: {
            Image(systemName: "sidebar.left")
                .symbolVariant(model.sidebarIsVisible ? .fill : .none)
                .frame(width: 28, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.secondary)
        .focusable(false)
        .help(L10n.string(model.sidebarIsVisible ? .sidebarHide : .sidebarShow))
        .accessibilityLabel(L10n.string(model.sidebarIsVisible ? .sidebarHide : .sidebarShow))
    }

    private var readerTitlebar: some View {
        HStack(spacing: 10) {
            if !model.sidebarIsVisible {
                sidebarToggle
                    .padding(.leading, 80)
            }

            if model.hasSecondPane {
                Text(L10n.string(.appName))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                    .padding(.leading, 12)
                Spacer(minLength: 0)
            } else {
                DocumentHeaderView(pane: .primary)
            }

            HStack(spacing: 8) {
                Button {
                    model.reloadActiveDocument()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 26)
                }
                .disabled(!model.canReloadActiveDocument)
                .help(L10n.string(.toolbarReloadHelp))

                Button {
                    model.toggleSplitReading()
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .symbolVariant(model.hasSecondPane ? .fill : .none)
                        .frame(width: 28, height: 26)
                }
                .help(L10n.string(model.hasSecondPane
                    ? .toolbarCloseSplitHelp
                    : .toolbarOpenSplitHelp))
                .accessibilityLabel(L10n.string(model.hasSecondPane
                    ? .commandCloseActivePane
                    : .commandOpenSecondPane))

                themeMenu
                    .frame(width: 28, height: 26)

                Button {
                    model.outlineIsVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .symbolVariant(model.outlineIsVisible ? .fill : .none)
                        .frame(width: 28, height: 26)
                }
                .help(L10n.string(model.outlineIsVisible ? .outlineHide : .outlineShow))
                .accessibilityLabel(L10n.string(model.outlineIsVisible ? .outlineHide : .outlineShow))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondary)
            .focusable(false)
            .padding(.trailing, 10)
        }
        .frame(height: 38)
        .background(WindowTitlebarDragArea())
        .background(theme.chrome)
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

    private func persistSidebarPanelWidth(_ width: CGFloat) {
        UserDefaults.standard.set(Double(width), forKey: SidePanelLayout.sidebarWidthStorageKey)
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
    static let sidebarWidthStorageKey = "sidebarPanelWidth.v1"

    static func restoredSidebarWidth() -> CGFloat {
        let width = UserDefaults.standard.double(forKey: sidebarWidthStorageKey)
        return width > 0 ? max(CGFloat(width), sidebarMinimumWidth) : sidebarIdealWidth
    }

    static func maximumWidth(forWindowWidth width: CGFloat) -> CGFloat {
        max(
            max(sidebarMinimumWidth, OutlinePanelLayout.minimumWidth),
            width * maximumWindowFraction
        )
    }
}

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: ReaderViewModel
    @State private var workspaceSwitcherIsPresented = false

    private var theme: ResolvedReaderTheme { model.resolvedTheme }

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader

            Divider()
                .overlay(theme.divider.opacity(0.75))

            if model.rootURL == nil {
                emptySidebar
            } else {
                ZStack {
                    FileTreeView()
                        .allowsHitTesting(!model.rootIsLoading)

                    if model.rootIsLoading {
                        VStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.string(.sidebarLoading))
                                .font(.caption)
                                .foregroundStyle(theme.secondary)
                        }
                        .padding(18)
                        .background(theme.chrome.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
                .overlay(theme.divider.opacity(0.75))

            HStack(spacing: 7) {
                Image(systemName: "text.quote")
                    .font(.system(size: 11))
                Text(L10n.string(.sidebarTagline))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, 13)
            .frame(height: 36)
        }
        .background(theme.chrome)
        .overlay(alignment: .top) {
            if workspaceSwitcherIsPresented {
                ZStack(alignment: .top) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { workspaceSwitcherIsPresented = false }

                    workspaceSwitcher
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay(alignment: .bottom) {
                            Divider().overlay(theme.divider.opacity(0.75))
                        }
                        .shadow(color: .black.opacity(theme.isDark ? 0.28 : 0.12), radius: 8, y: 5)
                }
                .padding(.top, 53)
            }
        }
        .clipped()
        .onChange(of: model.rootURL) { _ in
            workspaceSwitcherIsPresented = false
        }
        .alert(
            L10n.string(.sidebarOperationFailed),
            isPresented: Binding(
                get: { model.fileOperationError != nil },
                set: { isPresented in
                    if !isPresented {
                        model.dismissFileOperationError()
                    }
                }
            )
        ) {
            Button(L10n.string(.commonOK)) {
                model.dismissFileOperationError()
            }
        } message: {
            Text(model.fileOperationError ?? L10n.string(.commonUnknownError))
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 6) {
            Button {
                workspaceSwitcherIsPresented.toggle()
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(theme.accent.opacity(
                                theme.isDark ? 0.22 : 0.14
                            ))
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    }
                    .frame(width: 29, height: 29)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.rootName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.foreground)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(L10n.string(
                            model.rootURL == nil
                                ? .sidebarChooseWorkspace
                                : .sidebarCurrentWorkspaceSwitch
                        ))
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.secondary)
                    }

                    Spacer(minLength: 2)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(theme.secondary)
                        .rotationEffect(.degrees(workspaceSwitcherIsPresented ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(L10n.string(.sidebarSwitchHelp))

            if model.rootURL != nil {
                Button {
                    model.rescanWorkspace()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(theme.secondary)
                .help(L10n.string(.sidebarReloadHelp))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private var workspaceSwitcher: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string(.sidebarRecent))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.secondary)

            let switchableWorkspaces = model.recentWorkspaces.filter {
                $0.id != model.rootURL?.standardizedFileURL.path
            }
            if switchableWorkspaces.isEmpty {
                Text(L10n.string(.sidebarNoOtherRecent))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.secondary)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(switchableWorkspaces) { workspace in
                            workspaceSwitchRow(workspace)
                        }
                    }
                }
                .frame(height: min(CGFloat(switchableWorkspaces.count) * 46 - 3, 240))
            }

            Divider().overlay(theme.divider.opacity(0.75))

            ViewThatFits(in: .horizontal) {
                HStack {
                    openOtherWorkspaceButton
                    Spacer(minLength: 12)
                    clearRecentWorkspacesButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    openOtherWorkspaceButton
                    clearRecentWorkspacesButton
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome)
    }

    private var openOtherWorkspaceButton: some View {
        Button {
            workspaceSwitcherIsPresented = false
            DispatchQueue.main.async {
                model.chooseFolder()
            }
        } label: {
            Label(L10n.string(.sidebarOpenOther), systemImage: "folder.badge.plus")
        }
        .focusable(false)
    }

    @ViewBuilder
    private var clearRecentWorkspacesButton: some View {
        if !model.recentWorkspaces.isEmpty {
            Button(L10n.string(.sidebarClearRecent)) {
                model.clearRecentWorkspaces()
            }
            .disabled(!model.canClearRecentWorkspaces)
            .focusable(false)
            .foregroundStyle(theme.secondary)
        }
    }

    private func workspaceSwitchRow(_ workspace: RecentWorkspace) -> some View {
        RecentWorkspaceRow(workspace: workspace, theme: theme) {
            workspaceSwitcherIsPresented = false
            model.openRecentWorkspace(workspace)
        } onRemove: {
            model.removeRecentWorkspace(workspace)
        }
    }

    private var emptySidebar: some View {
        VStack(spacing: 13) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.secondary.opacity(0.7))
            Text(L10n.string(.sidebarEmpty))
                .font(.system(size: 12))
                .foregroundStyle(theme.secondary)
            Button(L10n.string(.sidebarOpenFolder)) {
                model.chooseFolder()
            }
            .buttonStyle(.borderedProminent)
            .focusable(false)
            .tint(theme.accent)
            .controlSize(.small)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct RecentWorkspaceRow: View {
    let workspace: RecentWorkspace
    let theme: ResolvedReaderTheme
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false
    @State private var removeIsHovered = false

    private var removeLabel: String {
        L10n.format(.sidebarRemoveRecent, workspace.name)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 9) {
                    Image(systemName: "folder")
                        .foregroundStyle(theme.accent)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(theme.foreground)
                            .lineLimit(1)
                        Text(workspace.displayPath)
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.leading, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 43)
                .contentShape(Rectangle())
            }
            .help(workspace.displayPath)

            // Reserve the trailing slot so showing the remove action never shifts text.
            ZStack {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(removeIsHovered ? theme.foreground : theme.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            removeIsHovered ? theme.foreground.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .help(removeLabel)
                .accessibilityLabel(removeLabel)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .accessibilityHidden(!isHovered)
                .onHover { removeIsHovered = $0 }
            }
            .frame(width: 24, height: 43)
            .padding(.trailing, 8)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(theme.canvas.opacity(theme.isDark ? 0.5 : 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if !hovering { removeIsHovered = false }
        }
    }
}

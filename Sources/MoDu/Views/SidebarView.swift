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
                            Text("正在读取目录…")
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
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 11))
                Text("本地管理 · 远程图片按需加载")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, 13)
            .frame(height: 36)
        }
        .background(theme.chrome)
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { model.fileOperationError != nil },
                set: { isPresented in
                    if !isPresented {
                        model.dismissFileOperationError()
                    }
                }
            )
        ) {
            Button("好") {
                model.dismissFileOperationError()
            }
        } message: {
            Text(model.fileOperationError ?? "未知错误")
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
                        Text(model.rootURL == nil ? "点击选择工作目录" : "工作目录 · 点击切换")
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
            .help("切换工作目录")
            .popover(isPresented: $workspaceSwitcherIsPresented, arrowEdge: .bottom) {
                workspaceSwitcher
            }

            if model.rootURL != nil {
                Button {
                    model.rescanWorkspace()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondary)
                .help("重新加载目录（仅文件列表）")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private var workspaceSwitcher: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("切换工作目录")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.foreground)

            if let rootURL = model.rootURL {
                HStack(spacing: 9) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(theme.accent)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rootURL.lastPathComponent)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.foreground)
                        Text(rootURL.path)
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
                .padding(9)
                .background(theme.accent.opacity(theme.isDark ? 0.16 : 0.09))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Divider().overlay(theme.divider.opacity(0.75))

            Text("最近使用")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.secondary)

            let switchableWorkspaces = model.recentWorkspaces.filter {
                $0.id != model.rootURL?.standardizedFileURL.path
            }
            if switchableWorkspaces.isEmpty {
                Text("暂无其他最近目录")
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
                .frame(maxHeight: 240)
            }

            Divider().overlay(theme.divider.opacity(0.75))

            HStack {
                Button {
                    workspaceSwitcherIsPresented = false
                    DispatchQueue.main.async {
                        model.chooseFolder()
                    }
                } label: {
                    Label("打开其他目录…", systemImage: "folder.badge.plus")
                }

                Spacer()

                if !model.recentWorkspaces.isEmpty {
                    Button("清除记录") {
                        model.clearRecentWorkspaces()
                    }
                        .foregroundStyle(theme.secondary)
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 340)
        .background(theme.chrome)
    }

    private func workspaceSwitchRow(_ workspace: RecentWorkspace) -> some View {
        Button {
            workspaceSwitcherIsPresented = false
            model.openRecentWorkspace(workspace)
        } label: {
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(theme.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 43)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(theme.canvas.opacity(theme.isDark ? 0.5 : 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(workspace.displayPath)
    }

    private var emptySidebar: some View {
        VStack(spacing: 13) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.secondary.opacity(0.7))
            Text("目录中的文件会显示在这里")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondary)
            Button("打开目录") {
                model.chooseFolder()
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .controlSize(.small)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

import SwiftUI

struct DocumentView: View {
    @EnvironmentObject private var model: ReaderViewModel
    let pane: ReaderPaneID

    private var theme: ResolvedReaderTheme { model.resolvedTheme }

    var body: some View {
        VStack(spacing: 0) {
            if shouldShowDocumentBar {
                documentBar
                Divider().overlay(theme.divider.opacity(0.75))
            }
            documentContent
        }
        .background(theme.canvas)
        .overlay(alignment: .top) {
            if model.activePane == pane {
                Rectangle()
                    .fill(theme.accent)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            model.activatePane(pane)
        })
    }

    private var shouldShowDocumentBar: Bool {
        if model.hasSecondPane {
            return true
        }
        if case .welcome = model.documentState(for: pane) {
            return false
        }
        return true
    }

    private var documentBar: some View {
        HStack(spacing: 8) {
            Image(systemName: documentIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(model.activePane == pane
                    ? theme.accent
                    : theme.secondary)

            Text(model.currentTitle(for: pane))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if case .loaded(_, let rendered) = model.documentState(for: pane) {
                Text(Self.fileSizeFormatter.string(fromByteCount: rendered.fileSize))
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(theme.secondary)
            }

            if model.hasSecondPane {
                Button {
                    model.closePane(pane)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondary)
                .help("关闭此栏")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture {
            model.activatePane(pane)
        }
        .background(theme.chrome.opacity(theme.isDark ? 0.82 : 0.72))
    }

    @ViewBuilder
    private var documentContent: some View {
        switch model.documentState(for: pane) {
        case .welcome:
            WelcomeView()
        case .loading(let url):
            VStack(spacing: 12) {
                ProgressView()
                Text("正在读取 \(url.lastPathComponent)…")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let url, let rendered):
            if let rootURL = model.rootURL {
                MarkdownWebView(
                    document: rendered,
                    documentURL: url,
                    rootURL: rootURL,
                    style: theme,
                    scrollRequest: model.scrollRequest(for: pane),
                    onOpenMarkdown: { targetURL, anchor in
                        model.openMarkdownLink(targetURL, anchor: anchor, in: pane)
                    },
                    onActiveHeading: { anchor in
                        model.updateActiveOutline(anchor: anchor, in: pane)
                    },
                    onFocus: {
                        model.activatePane(pane)
                    }
                )
            }
        case .unsupported(let url):
            StatusView(
                symbol: "doc.questionmark",
                title: "暂不支持预览",
                message: "\(url.lastPathComponent) 不是支持的 Markdown 或 HTML 文件。"
            )
        case .failed(_, let message):
            StatusView(
                symbol: "exclamationmark.triangle",
                title: "读取失败",
                message: message
            )
        }
    }

    private var documentIcon: String {
        switch model.documentState(for: pane) {
        case .welcome: "doc.text"
        case .loading: "hourglass"
        case .loaded: "doc.richtext"
        case .unsupported: "doc.questionmark"
        case .failed: "exclamationmark.triangle"
        }
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter
    }()
}

private struct WelcomeView: View {
    @EnvironmentObject private var model: ReaderViewModel

    private var theme: ResolvedReaderTheme { model.resolvedTheme }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "book.pages")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(theme.accent)

            VStack(spacing: 7) {
                Text("选择一篇 Markdown 或 HTML 文档")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                Text("本地管理，按需加载文档中的远程图片")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondary)
            }

            HStack(spacing: 8) {
                badge("本地渲染", symbol: "doc.text")
                badge("目录内重命名", symbol: "pencil")
                badge("双栏阅读", symbol: "rectangle.split.2x1")
            }

            if model.rootURL == nil {
                Button("打开目录") {
                    model.chooseFolder()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func badge(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(theme.chrome)
            .clipShape(Capsule())
    }
}

private struct StatusView: View {
    @EnvironmentObject private var model: ReaderViewModel
    let symbol: String
    let title: String
    let message: String

    private var theme: ResolvedReaderTheme { model.resolvedTheme }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(theme.secondary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.foreground)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

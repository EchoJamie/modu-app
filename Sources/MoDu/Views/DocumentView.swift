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
                .help(L10n.string(.documentClosePane))
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
                Text(L10n.format(.documentLoading, url.lastPathComponent))
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
                title: L10n.string(.documentUnsupportedTitle),
                message: L10n.format(.documentUnsupportedMessage, url.lastPathComponent)
            )
        case .failed(_, let message):
            StatusView(
                symbol: "exclamationmark.triangle",
                title: L10n.string(.documentFailedTitle),
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
                Text(L10n.string(.welcomeTitle))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                Text(L10n.string(.welcomeSubtitle))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondary)
            }

            HStack(spacing: 8) {
                badge(L10n.string(.welcomeLocalRendering), symbol: "doc.text")
                badge(L10n.string(.welcomeRename), symbol: "pencil")
                badge(L10n.string(.welcomeSplitReading), symbol: "rectangle.split.2x1")
            }

            if model.rootURL == nil {
                Button(L10n.string(.sidebarOpenFolder)) {
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

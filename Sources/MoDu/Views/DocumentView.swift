import SwiftUI

struct DocumentView: View {
    @EnvironmentObject private var model: ReaderViewModel
    let pane: ReaderPaneID
    @FocusState private var documentSearchIsFocused: Bool
    @FocusState private var sourceLineJumpIsFocused: Bool

    private var theme: ResolvedReaderTheme { model.resolvedTheme }

    var body: some View {
        VStack(spacing: 0) {
            if shouldShowDocumentBar {
                documentBar
                Divider().overlay(theme.divider.opacity(0.75))
            }
            if model.documentSearchState(for: pane).isPresented {
                documentSearchControls
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
        .overlay {
            if model.sourceLineJumpState(for: pane).isPresented {
                sourceLineJumpInput
            }
        }
        .overlay(alignment: .bottom) {
            if let failure = model.operationFailure(for: pane) {
                operationFailureBanner(failure)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            model.activatePane(pane)
        })
        .onChange(of: model.documentSearchFocusRequest(for: pane)) { request in
            guard request != nil else { return }
            documentSearchIsFocused = true
        }
        .onChange(of: model.sourceLineJumpFocusRequest(for: pane)) { request in
            guard request != nil else { return }
            sourceLineJumpIsFocused = true
        }
        .onExitCommand {
            if model.sourceLineJumpState(for: pane).isPresented {
                sourceLineJumpIsFocused = false
                model.dismissSourceLineJump(in: pane)
                return
            }
            guard model.documentSearchState(for: pane).isPresented else { return }
            documentSearchIsFocused = false
            model.dismissDocumentSearch(in: pane)
        }
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

            if let source = renderedSourcePage {
                sourceHeaderControls(source)
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
                .focusable(false)
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

    private var renderedSourcePage: RenderedSourcePage? {
        guard case .loaded(_, let rendered) = model.documentState(for: pane) else { return nil }
        return rendered.sourcePage
    }

    private func sourceHeaderControls(_ source: RenderedSourcePage) -> some View {
        HStack(spacing: 7) {
            Menu {
                ForEach(SourceLanguage.allCases) { language in
                    Button {
                        model.selectSourceLanguage(language, in: pane)
                    } label: {
                        if source.language == language {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            } label: {
                Label(source.language.displayName, systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .focusable(false)
            .help(L10n.string(.sourceLanguageHelp))
        }
    }

    private var sourceLineJumpInput: some View {
        let state = model.sourceLineJumpState(for: pane)
        return TextField(
            L10n.string(.sourceLineJumpPlaceholder),
            text: Binding(
                get: { model.sourceLineJumpState(for: pane).input },
                set: { model.updateSourceLineJumpInput($0, in: pane) }
            )
        )
        .textFieldStyle(.plain)
        .font(.system(size: 14, weight: .medium, design: .monospaced))
        .multilineTextAlignment(.center)
        .frame(width: 150, height: 32)
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(state.didFail ? Color.red : theme.accent.opacity(0.7), lineWidth: 1)
        }
        .help(state.failure?.message ?? "")
        .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.16), radius: 16, y: 8)
        .focused($sourceLineJumpIsFocused)
        .onSubmit {
            model.jumpToSourceLine(in: pane)
        }
        .onAppear {
            sourceLineJumpIsFocused = true
        }
        .onChange(of: sourceLineJumpIsFocused) { isFocused in
            guard
                !isFocused,
                model.sourceLineJumpState(for: pane).isPresented
            else { return }
            model.dismissSourceLineJump(in: pane)
        }
        .zIndex(10)
    }

    private var documentSearchControls: some View {
        let search = model.documentSearchState(for: pane)
        return HStack(spacing: 7) {
            Button {
                documentSearchIsFocused = false
                model.dismissDocumentSearch(in: pane)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L10n.string(.documentFindClose))

            TextField(
                L10n.string(.documentFindPlaceholder),
                text: Binding(
                    get: { model.documentSearchState(for: pane).query },
                    set: { model.updateDocumentSearchQuery($0, in: pane) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11.5))
            .frame(minWidth: 90, maxWidth: .infinity)
            .focused($documentSearchIsFocused)
            .onSubmit {
                model.findInDocument(.next, in: pane)
            }

            Button {
                model.toggleDocumentSearchCaseSensitivity(in: pane)
            } label: {
                Text("Aa")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 5)
                    .frame(height: 22)
                    .background(search.isCaseSensitive ? theme.accent.opacity(0.2) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L10n.string(.documentFindCaseSensitive))

            if search.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else if let match = search.match {
                Text(L10n.format(.documentFindLine, match.line))
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(theme.secondary)
                    .fixedSize()
            } else if search.didFail {
                Text(search.failure?.message ?? L10n.string(.documentFindNotFound))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            Button {
                model.findInDocument(.previous, in: pane)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(search.query.isEmpty || search.isSearching)
            .help(L10n.string(.documentFindPrevious))

            Button {
                model.findInDocument(.next, in: pane)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(search.query.isEmpty || search.isSearching)
            .help(L10n.string(.documentFindNext))
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(theme.chrome.opacity(theme.isDark ? 0.72 : 0.58))
        .onAppear {
            documentSearchIsFocused = true
        }
    }

    private func operationFailureBanner(_ failure: ReaderFailure) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(failure.message)
                .font(.system(size: 11.5))
                .lineLimit(2)
            if failure.recoveryAction == .retryOperation {
                Button(L10n.string(.documentRetryOperation)) {
                    model.retryOperation(in: pane)
                }
                .buttonStyle(.borderless)
                .focusable(false)
            }
            Button {
                model.dismissOperationFailure(in: pane)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .padding(12)
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
                    findRequest: model.documentSearchRequest(for: pane),
                    sourceViewportUpdates: model.sourceViewportUpdates(for: pane),
                    onOpenDocument: { targetURL, anchor in
                        model.openDocumentLink(targetURL, anchor: anchor, in: pane)
                    },
                    onActiveHeading: { anchor in
                        model.updateActiveOutline(anchor: anchor, in: pane)
                    },
                    onFindResult: { requestID, found in
                        model.updateDocumentSearchResult(
                            requestID: requestID,
                            found: found,
                            in: pane
                        )
                    },
                    onSourceBoundary: { direction, edgePageIndex in
                        model.loadAdjacentSourceSegment(
                            direction,
                            edgePageIndex: edgePageIndex,
                            in: pane
                        )
                    },
                    onSourceVisiblePage: { pageIndex in
                        model.updateVisibleSourcePage(pageIndex, in: pane)
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
        case .failed(_, let failure):
            StatusView(
                symbol: "exclamationmark.triangle",
                title: L10n.string(.documentFailedTitle),
                message: failure.message
            )
        }
    }

    private var documentIcon: String {
        switch model.documentState(for: pane) {
        case .welcome: "doc.text"
        case .loading: "hourglass"
        case .loaded(_, let rendered): switch rendered.renderingMode {
            case .sourceCode: "chevron.left.forwardslash.chevron.right"
            case .image: "photo"
            case .styledDocument, .interactiveHTML: "doc.richtext"
            }
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
                .focusable(false)
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

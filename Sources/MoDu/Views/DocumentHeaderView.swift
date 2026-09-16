import SwiftUI

struct DocumentHeaderView: View {
    @EnvironmentObject private var model: ReaderViewModel
    let pane: ReaderPaneID

    private var theme: ResolvedReaderTheme { model.resolvedTheme }

    var body: some View {
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

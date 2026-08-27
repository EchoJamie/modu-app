import Foundation

final class SourceDocumentRenderer {
    static let highlighterScriptURL = LocalDocumentResourcePolicy.highlighterScriptURL
    static let highlighterAddonURLs = LocalDocumentResourcePolicy.highlighterAddonURLs

    static let stylesheet = """
    html, body { min-height: 100%; background: var(--code-bg); }
    body { margin: 0; }
    #write.source-document { box-sizing: border-box; width: 100%; min-height: 100vh; max-width: none; margin: 0; padding: 0; background: var(--code-bg); overflow-wrap: normal; }
    .source-segments { width: max-content; min-width: 100%; min-height: 100vh; background: var(--code-bg); }
    .source-segment { display: grid; grid-template-columns: max-content minmax(0, 1fr); align-items: stretch; width: max-content; min-width: 100%; border: 0; background: var(--code-bg); overflow: hidden; }
    .source-segment:only-child { min-height: 100vh; }
    .source-segment pre { min-height: 100%; margin: 0; border: 0; border-radius: 0; background: transparent; font-size: 13px; line-height: 1.62; }
    .source-line-numbers { position: sticky; left: 0; z-index: 1; padding: 22px 12px 22px 14px; border-right: 1px solid var(--soft-border) !important; color: var(--muted); text-align: right; user-select: none; -webkit-user-select: none; }
    .source-code { min-width: 100%; padding: 22px !important; overflow: visible; }
    .source-code code { display: block; min-width: max-content; color: var(--code-text); white-space: pre; }
    .source-continuation { color: var(--accent); opacity: .72; }
    .hljs-comment, .hljs-quote { color: var(--muted); font-style: italic; }
    .hljs-keyword, .hljs-selector-tag, .hljs-section, .hljs-link { color: var(--accent); font-weight: 650; }
    .hljs-title.class_, .hljs-class .hljs-title, .hljs-type, .hljs-name { color: color-mix(in srgb, #9656bd 72%, var(--heading)); font-weight: 620; }
    .hljs-title.function_, .hljs-function .hljs-title, .hljs-built_in, .hljs-builtin-name { color: color-mix(in srgb, #278764 72%, var(--heading)); }
    .hljs-string, .hljs-regexp, .hljs-template-tag, .hljs-template-variable { color: color-mix(in srgb, #b56a2b 72%, var(--heading)); }
    .hljs-number, .hljs-literal, .hljs-symbol, .hljs-bullet { color: color-mix(in srgb, #ad4e73 70%, var(--heading)); }
    .hljs-meta, .hljs-attribute { color: color-mix(in srgb, #a67612 70%, var(--heading)); }
    .hljs-variable, .hljs-params { color: color-mix(in srgb, var(--code-text) 82%, var(--accent)); }
    .hljs-addition { color: color-mix(in srgb, #278764 76%, var(--heading)); }
    .hljs-deletion { color: #c94a4a; }
    .hljs-emphasis { font-style: italic; }
    .hljs-strong { font-weight: 700; }
    mark.modu-source-match { padding: 0; border-radius: 2px; background: color-mix(in srgb, var(--accent) 38%, #ffd84d); color: inherit; outline: 1px solid color-mix(in srgb, var(--accent) 72%, transparent); }
    """

    private let style: ResolvedReaderTheme
    private let documentURL: URL

    init(style: ResolvedReaderTheme, documentURL: URL) {
        self.style = style
        self.documentURL = documentURL
    }

    func render(
        page: SourcePage,
        language: SourceLanguage,
        inferredLanguage: SourceLanguage,
        fileSize: Int64,
        modifiedAt: Date?,
        selectedRange: NSRange? = nil
    ) throws -> RenderedDocument {
        try Task.checkCancellation()
        let lineNumbers = Self.lineNumbers(for: page)
        let scriptTags = ([Self.highlighterScriptURL] + Self.highlighterAddonURLs)
            .map { "  <script src=\"\($0)\"></script>" }
            .joined(separator: "\n")
        let html = """
        <!doctype html>
        <html lang="\(L10n.htmlLanguageCode)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta http-equiv="Content-Security-Policy" content="\(DocumentSecurityPolicy.sourceValue())">
          <title>\(escape(documentURL.lastPathComponent))</title>
          <style id="modu-theme">\(style.stylesheet)\n\(Self.stylesheet)</style>
        \(scriptTags)
        </head>
        <body>
          <main id="write" class="source-document">
            <div id="source-segments" class="source-segments">
              <section class="source-segment" data-page-index="\(page.index)" data-start-line="\(page.startLine)" data-end-line="\(page.endLine)" data-has-previous="\(page.hasPrevious)" data-has-next="\(page.hasNext)">
                <pre class="source-line-numbers" aria-hidden="true">\(lineNumbers)</pre>
                <pre class="source-code"><code id="source-code-\(page.index)" class="language-\(language.highlightIdentifier)">\(escape(page.text))</code></pre>
              </section>
            </div>
          </main>
        </body>
        </html>
        """

        return RenderedDocument(
            content: .source(
                html: html,
                page: RenderedSourcePage(
                    page: page,
                    language: language,
                    inferredLanguage: inferredLanguage,
                    selectedRange: selectedRange
                )
            ),
            outline: [],
            fileSize: fileSize,
            modifiedAt: modifiedAt
        )
    }

    static func lineNumbers(for page: SourcePage) -> String {
        let visibleLineCount = page.text.isEmpty
            ? 1
            : page.text.reduce(into: page.text.hasSuffix("\n") ? 0 : 1) { count, character in
                if character == "\n" { count += 1 }
            }
        guard visibleLineCount > 0 else { return "" }
        return (0..<visibleLineCount).map { offset in
            let line = page.startLine + offset
            if offset == 0, page.leadingContinuation { return "↳\(line)" }
            return String(line)
        }.joined(separator: "\n")
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

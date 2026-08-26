import Foundation
import Markdown

final class MarkdownRenderer {
    static let resourceScheme = "modu-resource"
    static let markdownScheme = "modu-markdown"
    static let bundledAssetScheme = "modu-asset"
    static let mermaidVersion = "11.16.1"

    static var mermaidScriptURL: String {
        "\(bundledAssetScheme)://mermaid/mermaid-\(mermaidVersion).min.js"
    }

    static func shouldUseWideTable(columnCount: Int, contentLength: Int) -> Bool {
        columnCount >= 5 ||
            (columnCount >= 4 && contentLength >= 160) ||
            (columnCount >= 3 && contentLength >= 360)
    }

    private static let localImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp"
    ]
    private static let maximumMermaidSourceSize = 50_000
    private static let maximumMermaidDiagramCount = 64
    private static let maximumMermaidTotalSourceSize = 500_000

    private static let mermaidStylesheet = """
    .mermaid-diagram {
      position: relative;
      left: 50%;
      width: min(1600px, calc(100vw - 72px));
      margin: 1.55em 0;
      padding: 18px 20px;
      overflow: hidden;
      transform: translateX(-50%);
      border: 1px solid var(--soft-border);
      border-radius: 10px;
      background: color-mix(in srgb, var(--code-bg) 72%, var(--page-bg));
      box-shadow: 0 1px 2px color-mix(in srgb, var(--text) 7%, transparent);
    }
    .mermaid-output { overflow-x: auto; }
    .mermaid-output:empty { display: none; }
    .mermaid-output svg { display: block; max-width: 100% !important; height: auto; margin: 0 auto; }
    .mermaid-status {
      display: flex;
      align-items: center;
      gap: .55em;
      margin: 0;
      color: var(--muted);
      font-size: .9em;
    }
    .mermaid-status::before {
      width: .72em;
      height: .72em;
      flex: 0 0 auto;
      border: 2px solid var(--border);
      border-top-color: var(--accent);
      border-radius: 50%;
      content: "";
    }
    .mermaid-diagram.is-rendering .mermaid-status::before { animation: modu-mermaid-spin .85s linear infinite; }
    .mermaid-diagram.is-ready .mermaid-status,
    .mermaid-diagram.is-ready .mermaid-error-detail,
    .mermaid-diagram.is-ready .mermaid-source-details { display: none; }
    .mermaid-diagram.is-error { border-color: color-mix(in srgb, #c83b3b 45%, var(--border)); }
    .mermaid-diagram.is-error .mermaid-status { color: var(--text); font-weight: 600; }
    .mermaid-diagram.is-error .mermaid-status::before {
      display: grid;
      width: 1.35em;
      height: 1.35em;
      place-items: center;
      border: 0;
      border-radius: 50%;
      background: color-mix(in srgb, #c83b3b 16%, transparent);
      color: #b52d2d;
      content: "!";
      font: 700 .78em/1 -apple-system, BlinkMacSystemFont, sans-serif;
    }
    .mermaid-error-detail { margin: .55em 0 0 1.9em; color: var(--muted); font-size: .82em; }
    .mermaid-error-detail:empty { display: none; }
    .mermaid-source-details { margin-top: .8em; color: var(--muted); font-size: .86em; }
    .mermaid-source-details summary { width: fit-content; cursor: pointer; color: var(--accent); }
    .mermaid-source {
      margin: .7em 0 0;
      padding: 14px 16px;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
      font-size: 12px;
    }
    @keyframes modu-mermaid-spin { to { transform: rotate(360deg); } }
    @media (prefers-reduced-motion: reduce) {
      .mermaid-diagram.is-rendering .mermaid-status::before { animation: none; }
    }
    """

    private let style: ResolvedReaderTheme
    private let documentURL: URL
    private let rootURL: URL
    private var body = ""
    private var outline: [OutlineItem] = []
    private var usedAnchors: [String: Int] = [:]
    private var mermaidDiagramCount = 0
    private var mermaidTotalSourceSize = 0
    private var hasRenderableMermaidDiagram = false

    init(style: ResolvedReaderTheme, documentURL: URL, rootURL: URL) {
        self.style = style
        self.documentURL = documentURL
        self.rootURL = rootURL
    }

    func render(_ source: String, fileSize: Int64, modifiedAt: Date?) throws -> RenderedMarkdown {
        try Task.checkCancellation()
        let extracted = MarkdownFrontMatter.extract(from: source)
        if let metadata = extracted.metadata {
            renderFrontMatter(metadata)
        }
        let document = Document(parsing: extracted.markdown)
        try Task.checkCancellation()
        for child in document.children {
            try Task.checkCancellation()
            try renderBlock(child)
        }

        let scriptSource = hasRenderableMermaidDiagram ? "\(Self.bundledAssetScheme):" : "'none'"
        let contentSecurityPolicy = DocumentSecurityPolicy.value(scriptSource: scriptSource)
        let mermaidScript = hasRenderableMermaidDiagram
            ? "<script src=\"\(Self.mermaidScriptURL)\"></script>"
            : ""

        let html = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
          <title>\(escapeText(documentURL.lastPathComponent))</title>
          <style id="modu-theme">\(style.stylesheet)</style>
          <style id="modu-mermaid-style">\(Self.mermaidStylesheet)</style>
        </head>
        <body>
          <main id="write">
        \(body)
          </main>
          \(mermaidScript)
        </body>
        </html>
        """

        return RenderedMarkdown(
            html: html,
            outline: outline,
            fileSize: fileSize,
            modifiedAt: modifiedAt
        )
    }

    private func renderFrontMatter(_ metadata: MarkdownFrontMatter) {
        let previewEntries = Array(metadata.entries.prefix(MarkdownFrontMatter.previewEntryLimit))
        let remainingEntries = Array(metadata.entries.dropFirst(MarkdownFrontMatter.previewEntryLimit))
        let collapsibleClass = metadata.isCollapsible ? " is-collapsible" : ""

        body += """
        <section class="front-matter\(collapsibleClass)" aria-label="文档元数据">
          <div class="front-matter-heading">
            <span class="front-matter-mark" aria-hidden="true"></span>
            <span class="front-matter-title">文档信息</span>
            <span class="front-matter-count">\(metadata.entries.count) 项</span>
          </div>
          <dl class="front-matter-list front-matter-preview">
        """
        renderFrontMatterEntries(previewEntries)
        body += "</dl>\n"

        if metadata.isCollapsible {
            let expandLabel = remainingEntries.isEmpty
                ? "展开完整内容"
                : "展开其余 \(remainingEntries.count) 项"
            body += """
              <details class="front-matter-more">
                <summary>
                  <span class="front-matter-expand">\(expandLabel)</span>
                  <span class="front-matter-collapse">收起文档信息</span>
                </summary>
            """
            if !remainingEntries.isEmpty {
                body += "<dl class=\"front-matter-list front-matter-remainder\">\n"
                renderFrontMatterEntries(remainingEntries)
                body += "</dl>\n"
            }
            body += "</details>\n"
        }

        body += "</section>\n"
    }

    private func renderFrontMatterEntries(_ entries: [MarkdownFrontMatter.Entry]) {
        for entry in entries {
            body += """
              <div class="front-matter-row">
                <dt>\(escapeText(entry.key))</dt>
                <dd>\(escapeText(entry.value))</dd>
              </div>
            """
        }
    }

    private func renderBlock(_ markup: Markup) throws {
        try Task.checkCancellation()

        switch markup {
        case let heading as Heading:
            let title = plainText(heading).trimmingCharacters(in: .whitespacesAndNewlines)
            let anchor = uniqueAnchor(for: title)
            body += "<h\(heading.level) id=\"\(escapeAttribute(anchor))\">"
            try renderInlineChildren(of: heading)
            body += "</h\(heading.level)>\n"
            if !title.isEmpty {
                outline.append(OutlineItem(title: title, level: heading.level, anchor: anchor))
            }
        case let paragraph as Paragraph:
            body += "<p>"
            try renderInlineChildren(of: paragraph)
            body += "</p>\n"
        case let codeBlock as CodeBlock:
            let language = normalizedLanguage(codeBlock.language)
            if language == "mermaid" {
                renderMermaid(codeBlock.code)
            } else {
                let languageAttribute = language.map { " data-language=\"\(escapeAttribute($0))\"" } ?? ""
                let classAttribute = language.map { " class=\"language-\(escapeAttribute($0))\"" } ?? ""
                body += "<pre\(languageAttribute)><code\(classAttribute)>\(escapeText(codeBlock.code))</code></pre>\n"
            }
        case let quote as BlockQuote:
            body += "<blockquote>\n"
            for child in quote.children { try renderBlock(child) }
            body += "</blockquote>\n"
        case let table as Table:
            try renderTable(table)
        case let list as UnorderedList:
            body += "<ul>\n"
            for child in list.children { try renderBlock(child) }
            body += "</ul>\n"
        case let list as OrderedList:
            let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
            body += "<ol\(start)>\n"
            for child in list.children { try renderBlock(child) }
            body += "</ol>\n"
        case let item as ListItem:
            try renderListItem(item)
        case is ThematicBreak:
            body += "<hr>\n"
        case let html as HTMLBlock:
            body += "<pre class=\"raw-html\"><code>\(escapeText(html.rawHTML))</code></pre>\n"
        default:
            for child in markup.children { try renderBlock(child) }
        }
    }

    private func renderMermaid(_ source: String) {
        mermaidDiagramCount += 1
        mermaidTotalSourceSize += source.utf8.count
        let escapedSource = escapeText(source)
        let sourceDetails = """
        <details class="mermaid-source-details">
          <summary>查看 Mermaid 源代码</summary>
          <pre class="mermaid-source"><code>\(escapedSource)</code></pre>
        </details>
        """

        guard
            source.utf8.count <= Self.maximumMermaidSourceSize,
            mermaidDiagramCount <= Self.maximumMermaidDiagramCount,
            mermaidTotalSourceSize <= Self.maximumMermaidTotalSourceSize
        else {
            body += """
            <figure class="mermaid-diagram is-error" data-mermaid-index="\(mermaidDiagramCount)">
              <div class="mermaid-output" role="img" aria-label="Mermaid 图表"></div>
              <p class="mermaid-status" role="status">图表数量或内容超过安全限制，已保留源代码而未执行渲染。</p>
              <p class="mermaid-error-detail">单图最多 \(Self.maximumMermaidSourceSize) 字节；每篇最多 \(Self.maximumMermaidDiagramCount) 张、合计 \(Self.maximumMermaidTotalSourceSize) 字节。</p>
              \(sourceDetails)
            </figure>
            """
            return
        }

        hasRenderableMermaidDiagram = true
        body += """
        <figure class="mermaid-diagram is-rendering" data-mermaid-index="\(mermaidDiagramCount)" data-mermaid-renderable="true" aria-busy="true">
          <div class="mermaid-output" role="img" aria-label="Mermaid 图表"></div>
          <p class="mermaid-status" role="status">正在渲染 Mermaid 图表…</p>
          <p class="mermaid-error-detail"></p>
          \(sourceDetails)
        </figure>
        """
    }

    private func renderListItem(_ item: ListItem) throws {
        let taskClass = item.checkbox == nil ? "" : " class=\"task-list-item\""
        body += "<li\(taskClass)>"
        if let checkbox = item.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            body += "<input type=\"checkbox\" disabled\(checked)>"
        }

        for child in item.children {
            if let paragraph = child as? Paragraph {
                try renderInlineChildren(of: paragraph)
            } else {
                try renderBlock(child)
            }
        }
        body += "</li>\n"
    }

    private func renderTable(_ table: Table) throws {
        let columnCount = table.columnAlignments.count
        let wideClass = Self.shouldUseWideTable(
            columnCount: columnCount,
            contentLength: plainText(table).count
        ) ? " is-wide" : ""
        body += "<div class=\"table-wrap\(wideClass)\"><table data-column-count=\"\(columnCount)\">\n<thead><tr>\n"
        try renderTableCells(
            of: table.head,
            element: "th",
            alignments: table.columnAlignments
        )
        body += "</tr></thead>\n"

        if !table.body.isEmpty {
            body += "<tbody>\n"
            for row in table.body.rows {
                body += "<tr>\n"
                try renderTableCells(
                    of: row,
                    element: "td",
                    alignments: table.columnAlignments
                )
                body += "</tr>\n"
            }
            body += "</tbody>\n"
        }
        body += "</table></div>\n"
    }

    private func renderTableCells(
        of row: Markup,
        element: String,
        alignments: [Table.ColumnAlignment?]
    ) throws {
        for (index, cell) in row.children.enumerated() {
            let alignment: String
            if alignments.indices.contains(index) {
                switch alignments[index] {
                case .center?: alignment = " class=\"align-center\""
                case .right?: alignment = " class=\"align-right\""
                default: alignment = ""
                }
            } else {
                alignment = ""
            }

            body += "<\(element)\(alignment)>"
            try renderInlineChildren(of: cell)
            body += "</\(element)>\n"
        }
    }

    private func renderInlineChildren(of markup: Markup) throws {
        for child in markup.children {
            try Task.checkCancellation()
            try renderInline(child)
        }
    }

    private func renderInline(_ markup: Markup) throws {
        switch markup {
        case let text as Markdown.Text:
            body += escapeText(text.string)
        case let strong as Strong:
            body += "<strong>"
            try renderInlineChildren(of: strong)
            body += "</strong>"
        case let emphasis as Emphasis:
            body += "<em>"
            try renderInlineChildren(of: emphasis)
            body += "</em>"
        case let strike as Strikethrough:
            body += "<del>"
            try renderInlineChildren(of: strike)
            body += "</del>"
        case let inlineCode as InlineCode:
            body += "<code>\(escapeText(inlineCode.code))</code>"
        case let link as Link:
            try renderLink(link)
        case let image as Markdown.Image:
            renderImage(image)
        case is SoftBreak:
            body += "\n"
        case is LineBreak:
            body += "<br>\n"
        case let html as InlineHTML:
            body += escapeText(html.rawHTML)
        case let symbol as SymbolLink:
            if let destination = symbol.destination {
                body += "<code>\(escapeText(destination))</code>"
            }
        default:
            try renderInlineChildren(of: markup)
        }
    }

    private func renderLink(_ link: Link) throws {
        guard let destination = link.destination, let href = resolvedLink(destination) else {
            try renderInlineChildren(of: link)
            return
        }
        body += "<a href=\"\(escapeAttribute(href))\">"
        try renderInlineChildren(of: link)
        body += "</a>"
    }

    private func renderImage(_ image: Markdown.Image) {
        let alt = plainText(image).trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let source = image.source,
            let src = resolvedImage(source)
        else {
            let label = alt.isEmpty ? "图片未加载" : "图片：\(alt)"
            body += "<span class=\"image-placeholder\">\(escapeText(label))</span>"
            return
        }

        let title = image.title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
        body += "<img src=\"\(escapeAttribute(src))\" alt=\"\(escapeAttribute(alt))\" loading=\"lazy\" referrerpolicy=\"no-referrer\"\(title)>"
    }

    private func resolvedLink(_ destination: String) -> String? {
        let decoded = destination.removingPercentEncoding ?? destination
        if decoded.hasPrefix("#") {
            return "#\(anchorSlug(from: String(decoded.dropFirst())))"
        }

        if let url = URL(string: decoded), let scheme = url.scheme?.lowercased() {
            return ["http", "https", "mailto"].contains(scheme) ? url.absoluteString : nil
        }

        let parts = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let candidate = resolvedLocalURL(String(parts[0])) else { return nil }
        guard FileNode.previewableExtensions.contains(candidate.pathExtension.lowercased()) else { return nil }
        guard let relativePath = relativePath(for: candidate) else { return nil }

        var components = URLComponents()
        components.scheme = Self.markdownScheme
        components.host = "local"
        components.queryItems = [URLQueryItem(name: "path", value: relativePath)]
        if parts.count == 2, !parts[1].isEmpty {
            components.fragment = anchorSlug(from: String(parts[1]))
        }
        return components.string
    }

    private func resolvedImage(_ source: String) -> String? {
        let decoded = source.removingPercentEncoding ?? source
        if
            let remoteURL = URL(string: decoded),
            let scheme = remoteURL.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            remoteURL.host?.isEmpty == false
        {
            return remoteURL.absoluteString
        }

        guard URL(string: decoded)?.scheme == nil, let candidate = resolvedLocalURL(decoded) else {
            return nil
        }
        guard Self.localImageExtensions.contains(candidate.pathExtension.lowercased()) else { return nil }
        guard let relativePath = relativePath(for: candidate) else { return nil }

        var components = URLComponents()
        components.scheme = Self.resourceScheme
        components.host = "local"
        components.queryItems = [URLQueryItem(name: "path", value: relativePath)]
        return components.string
    }

    private func resolvedLocalURL(_ destination: String) -> URL? {
        guard !destination.hasPrefix("//"), URL(string: destination)?.scheme == nil else { return nil }
        let pathOnly = destination.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? destination
        let candidate: URL
        if pathOnly.hasPrefix("/") {
            candidate = rootURL.appendingPathComponent(String(pathOnly.dropFirst()))
        } else {
            candidate = documentURL.deletingLastPathComponent().appendingPathComponent(pathOnly)
        }
        let standardized = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard (try? FileSystemService.validate(standardized, inside: rootURL)) != nil else { return nil }
        return standardized
    }

    private func relativePath(for fileURL: URL) -> String? {
        let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let filePath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return nil }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func uniqueAnchor(for title: String) -> String {
        let base = anchorSlug(from: title)
        let occurrence = usedAnchors[base, default: 0]
        usedAnchors[base] = occurrence + 1
        return occurrence == 0 ? base : "\(base)-\(occurrence)"
    }

    private func anchorSlug(from text: String) -> String {
        var result = ""
        var lastWasSeparator = false
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "-" {
                if !result.isEmpty && !lastWasSeparator {
                    result.append("-")
                    lastWasSeparator = true
                }
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "section" : result
    }

    private func normalizedLanguage(_ language: String?) -> String? {
        guard let language else { return nil }
        let safe = language.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return safe.isEmpty ? nil : safe
    }

    private func plainText(_ markup: Markup) -> String {
        if let text = markup as? Markdown.Text { return text.string }
        if let code = markup as? InlineCode { return code.code }
        if let image = markup as? Markdown.Image {
            return image.children.map(plainText).joined()
        }
        return markup.children.map(plainText).joined()
    }

    private func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

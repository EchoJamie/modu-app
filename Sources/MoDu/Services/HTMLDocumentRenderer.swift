import Foundation

final class HTMLDocumentRenderer {
    private let style: ResolvedReaderTheme
    private let documentURL: URL
    private let rootURL: URL
    private var usedAnchors: [String: Int] = [:]

    init(style: ResolvedReaderTheme, documentURL: URL, rootURL: URL) {
        self.style = style
        self.documentURL = documentURL
        self.rootURL = rootURL
    }

    func render(_ source: String, fileSize: Int64, modifiedAt: Date?) throws -> RenderedMarkdown {
        try Task.checkCancellation()

        let sourceBody = try firstCapture(
            in: source,
            pattern: #"(?is)<body\b[^>]*>(.*?)</body\s*>"#
        ) ?? source
        try Task.checkCancellation()
        let authorStyles = try captures(
            in: source,
            pattern: #"(?is)<style\b[^>]*>(.*?)</style\s*>"#
        )
        try Task.checkCancellation()
        var body = try removingUnsafeElements(from: sourceBody)
        try Task.checkCancellation()
        body = try rewritingQuotedAttribute("src", in: body) { [self] value in
            resolvedImage(value)
        }
        try Task.checkCancellation()
        body = try rewritingQuotedAttribute("href", in: body) { [self] value in
            resolvedLink(value)
        }
        try Task.checkCancellation()

        let headingResult = try addingHeadingAnchors(to: body)
        body = headingResult.body
        try Task.checkCancellation()
        let contentSecurityPolicy = DocumentSecurityPolicy.value()

        let html = """
        <!doctype html>
        <html lang="\(L10n.htmlLanguageCode)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta name="referrer" content="no-referrer">
          <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
          <title>\(escapeText(documentURL.lastPathComponent))</title>
          <style id="modu-theme">\(style.stylesheet)</style>
        \(authorStyles.map { "  <style>\($0)</style>" }.joined(separator: "\n"))
        </head>
        <body>
          <main id="write" class="modu-html-document">
        \(body)
          </main>
        </body>
        </html>
        """

        return RenderedMarkdown(
            html: html,
            outline: headingResult.outline,
            fileSize: fileSize,
            modifiedAt: modifiedAt
        )
    }

    private func removingUnsafeElements(from source: String) throws -> String {
        var result = source
        let pairedPatterns = [
            #"(?is)<script\b[^>]*>.*?</script\s*>"#,
            #"(?is)<iframe\b[^>]*>.*?</iframe\s*>"#,
            #"(?is)<object\b[^>]*>.*?</object\s*>"#
        ]
        let singlePatterns = [
            #"(?is)<script\b[^>]*/\s*>"#,
            #"(?is)<meta\b[^>]*>"#,
            #"(?is)<base\b[^>]*>"#,
            #"(?is)<link\b[^>]*>"#
        ]
        for pattern in pairedPatterns + singlePatterns {
            try Task.checkCancellation()
            let expression = try NSRegularExpression(pattern: pattern)
            result = expression.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        return result
    }

    private func rewritingQuotedAttribute(
        _ attribute: String,
        in source: String,
        transform: (String) -> String?
    ) throws -> String {
        let expression = try NSRegularExpression(
            pattern: #"(?is)(\b"# + NSRegularExpression.escapedPattern(for: attribute) + #"\s*=\s*)(["'])(.*?)\2"#
        )
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        var result = source

        for match in matches.reversed() {
            try Task.checkCancellation()
            guard
                let valueRange = Range(match.range(at: 3), in: result),
                let replacement = transform(String(result[valueRange]))
            else { continue }
            result.replaceSubrange(valueRange, with: escapeAttribute(replacement))
        }
        return result
    }

    private func addingHeadingAnchors(to source: String) throws -> (body: String, outline: [OutlineItem]) {
        let expression = try NSRegularExpression(
            pattern: #"(?is)<h([1-6])([^>]*)>(.*?)</h\1\s*>"#
        )
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        var replacements: [(range: NSRange, value: String)] = []
        var outline: [OutlineItem] = []

        for match in matches {
            try Task.checkCancellation()
            guard
                let levelRange = Range(match.range(at: 1), in: source),
                let attributesRange = Range(match.range(at: 2), in: source),
                let contentRange = Range(match.range(at: 3), in: source),
                let level = Int(source[levelRange])
            else { continue }

            let attributes = String(source[attributesRange])
            let content = String(source[contentRange])
            let title = try plainText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let existingAnchor = try headingID(in: attributes)
            let anchor = existingAnchor ?? uniqueAnchor(for: title)
            let idAttribute = existingAnchor == nil ? " id=\"\(escapeAttribute(anchor))\"" : ""
            replacements.append((
                range: match.range,
                value: "<h\(level)\(attributes)\(idAttribute)>\(content)</h\(level)>"
            ))
            outline.append(OutlineItem(title: title, level: level, anchor: anchor))
        }

        var result = source
        for replacement in replacements.reversed() {
            try Task.checkCancellation()
            guard let range = Range(replacement.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement.value)
        }
        return (result, outline)
    }

    private func headingID(in attributes: String) throws -> String? {
        let quoted = try NSRegularExpression(pattern: #"(?is)\bid\s*=\s*(["'])(.*?)\1"#)
        let fullRange = NSRange(attributes.startIndex..., in: attributes)
        if
            let match = quoted.firstMatch(in: attributes, range: fullRange),
            let range = Range(match.range(at: 2), in: attributes)
        {
            let value = String(attributes[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        let unquoted = try NSRegularExpression(pattern: #"(?is)\bid\s*=\s*([^\s>]+)"#)
        if
            let match = unquoted.firstMatch(in: attributes, range: fullRange),
            let range = Range(match.range(at: 1), in: attributes)
        {
            let value = String(attributes[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private func plainText(from html: String) throws -> String {
        let tags = try NSRegularExpression(pattern: #"(?is)<[^>]+>"#)
        let stripped = tags.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html),
            withTemplate: ""
        )
        return stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func resolvedLink(_ destination: String) -> String? {
        let decoded = destination.removingPercentEncoding ?? destination
        if decoded.hasPrefix("#") { return decoded }

        if let url = URL(string: decoded), let scheme = url.scheme?.lowercased() {
            return ["http", "https", "mailto"].contains(scheme) ? url.absoluteString : nil
        }
        guard let candidate = resolvedLocalURL(decoded) else { return nil }
        guard FileNode.previewableExtensions.contains(candidate.pathExtension.lowercased()) else { return nil }
        guard let relativePath = relativePath(for: candidate) else { return nil }

        let parts = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        var components = URLComponents()
        components.scheme = MarkdownRenderer.markdownScheme
        components.host = "local"
        components.queryItems = [URLQueryItem(name: "path", value: relativePath)]
        if parts.count == 2, !parts[1].isEmpty {
            components.fragment = String(parts[1])
        }
        return components.string
    }

    private func resolvedImage(_ source: String) -> String? {
        let decoded = source.removingPercentEncoding ?? source
        if decoded.lowercased().hasPrefix("data:image/") { return decoded }
        if decoded.hasPrefix("//") { return "https:\(decoded)" }
        if
            let remoteURL = URL(string: decoded),
            let scheme = remoteURL.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            remoteURL.host?.isEmpty == false
        {
            return remoteURL.absoluteString
        }

        guard let candidate = resolvedLocalURL(decoded) else { return nil }
        guard LocalResourceSchemeHandler.supports(candidate.pathExtension) else { return nil }
        guard let relativePath = relativePath(for: candidate) else { return nil }

        var components = URLComponents()
        components.scheme = MarkdownRenderer.resourceScheme
        components.host = "local"
        components.queryItems = [URLQueryItem(name: "path", value: relativePath)]
        return components.string
    }

    private func resolvedLocalURL(_ destination: String) -> URL? {
        guard !destination.hasPrefix("//"), URL(string: destination)?.scheme == nil else { return nil }
        let pathOnly = destination.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? destination
        guard !pathOnly.isEmpty else { return nil }
        let candidate = pathOnly.hasPrefix("/")
            ? rootURL.appendingPathComponent(String(pathOnly.dropFirst()))
            : documentURL.deletingLastPathComponent().appendingPathComponent(pathOnly)
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

    private func firstCapture(in source: String, pattern: String) throws -> String? {
        let expression = try NSRegularExpression(pattern: pattern)
        guard
            let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
            let range = Range(match.range(at: 1), in: source)
        else { return nil }
        return String(source[range])
    }

    private func captures(in source: String, pattern: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
    }

    private func uniqueAnchor(for title: String) -> String {
        var base = ""
        var needsSeparator = false
        for scalar in title.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if needsSeparator, !base.isEmpty { base.append("-") }
                base.unicodeScalars.append(scalar)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }
        if base.isEmpty { base = "section" }

        let occurrence = usedAnchors[base, default: 0]
        usedAnchors[base] = occurrence + 1
        return occurrence == 0 ? base : "\(base)-\(occurrence)"
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

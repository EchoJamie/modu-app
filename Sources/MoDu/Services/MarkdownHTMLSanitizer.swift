import Foundation

/// Rebuilds supported HTML tokens instead of passing author markup to WebKit.
/// Works on individual inline tokens as well as blocks, preserving paired tags
/// that the Markdown parser splits across multiple nodes.
enum MarkdownHTMLSanitizer {
    private static let tags = Set("a abbr b blockquote br caption code col colgroup dd del details div dl dt em figcaption figure h1 h2 h3 h4 h5 h6 hr i img ins kbd li mark ol p pre q rp rt ruby s samp small span strike strong sub summary sup table tbody td th thead time tr u ul var wbr".split(separator: " ").map(String.init))
    private static let attributes = Set("title class id style lang dir align width height colspan rowspan scope start reversed type open datetime alt".split(separator: " ").map(String.init))
    private static let token = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->|</?[A-Za-z][A-Za-z0-9]*(?:\s+[A-Za-z_:][A-Za-z0-9_:.-]*(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*\s*/?>"#)
    private static let attribute = try! NSRegularExpression(pattern: #"\s+([A-Za-z_:][A-Za-z0-9_:.-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#)

    static func render(_ source: String, link: (String) -> String?, image: (String) -> String?) -> String {
        let ns = source as NSString
        var result = ""
        var offset = 0
        for match in token.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            // Preserve text entities but never leave an unparsed opening bracket.
            result += ns.substring(with: NSRange(location: offset, length: match.range.location - offset))
                .replacingOccurrences(of: "<", with: "&lt;")
            let raw = ns.substring(with: match.range)
            offset = NSMaxRange(match.range)
            if raw.hasPrefix("<!--") { continue }
            let closing = raw.hasPrefix("</")
            let name = String(raw.dropFirst(closing ? 2 : 1).prefix { $0.isASCII && $0.isLetter || $0.isNumber }).lowercased()
            guard tags.contains(name) else {
                result += escape(raw)
                continue
            }
            if closing {
                result += "</\(name)>"
                continue
            }
            result += "<\(name)"
            var seen = Set<String>()
            let rawNS = raw as NSString
            for attr in attribute.matches(in: raw, range: NSRange(location: 0, length: rawNS.length)) {
                let key = rawNS.substring(with: attr.range(at: 1)).lowercased()
                guard seen.insert(key).inserted else { continue }
                let valueRange = (2...4).map { attr.range(at: $0) }.first { $0.location != NSNotFound }
                let value = decode(valueRange.map { rawNS.substring(with: $0) } ?? "")
                if key == "href", name == "a" {
                    if let resolved = link(value) { result += " href=\"\(escape(resolved))\"" }
                } else if key == "src", name == "img" {
                    if let resolved = image(value) { result += " src=\"\(escape(resolved))\"" }
                } else if attributes.contains(key) || key.hasPrefix("aria-") {
                    result += " \(key)=\"\(escape(value))\""
                }
            }
            if name == "img" { result += " loading=\"lazy\" referrerpolicy=\"no-referrer\"" }
            result += ">"
        }
        result += ns.substring(from: offset).replacingOccurrences(of: "<", with: "&lt;")
        return result
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Decode URL-relevant references before applying the existing URL policy.
    /// Unknown named references remain literal and are escaped on output.
    private static func decode(_ text: String) -> String {
        let expression = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#X[0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);?"#)
        let ns = text as NSString
        var output = text
        let named = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "colon": ":", "Tab": "\t", "NewLine": "\n", "nbsp": "\u{00a0}"]
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let reference = ns.substring(with: match.range(at: 1))
            var replacement = named[reference]
            if reference.hasPrefix("#") {
                let hex = reference.lowercased().hasPrefix("#x")
                if let number = UInt32(reference.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
                   let scalar = UnicodeScalar(number) { replacement = String(scalar) }
            }
            if let replacement, let range = Range(match.range, in: output) {
                output.replaceSubrange(range, with: replacement)
            }
        }
        return output
    }
}

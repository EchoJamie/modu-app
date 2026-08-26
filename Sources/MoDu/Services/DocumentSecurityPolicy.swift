import Foundation

enum DocumentSecurityPolicy {
    static func value(scriptSource: String = "'none'") -> String {
        "default-src 'none'; " +
            "img-src data: \(MarkdownRenderer.resourceScheme): http: https:; " +
            "style-src 'unsafe-inline'; " +
            "script-src \(scriptSource); " +
            "connect-src 'none'; media-src 'none'; object-src 'none'; " +
            "frame-src 'none'; worker-src 'none'; font-src 'none'; " +
            "base-uri 'none'; form-action 'none'"
    }
}

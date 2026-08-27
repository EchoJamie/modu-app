import Foundation

enum DocumentSecurityPolicy {
    static func value(scriptSource: String = "'none'") -> String {
        "default-src 'none'; " +
            "img-src data: \(LocalDocumentResourcePolicy.resourceScheme): http: https:; " +
            "style-src 'unsafe-inline'; " +
            "script-src \(scriptSource); " +
            "connect-src 'none'; media-src 'none'; object-src 'none'; " +
            "frame-src 'none'; worker-src 'none'; font-src 'none'; " +
            "base-uri 'none'; form-action 'none'"
    }

    static func sourceValue() -> String {
        "default-src 'none'; img-src 'none'; style-src 'unsafe-inline'; " +
            "script-src \(LocalDocumentResourcePolicy.bundledAssetScheme):; " +
            "connect-src 'none'; media-src 'none'; object-src 'none'; " +
            "frame-src 'none'; worker-src 'none'; font-src 'none'; " +
            "base-uri 'none'; form-action 'none'"
    }

    static func imageValue() -> String {
        [
            "default-src 'none'",
            "img-src \(LocalDocumentResourcePolicy.resourceScheme):",
            "style-src 'unsafe-inline'",
            "script-src 'none'",
            "connect-src 'none'",
            "media-src 'none'",
            "object-src 'none'",
            "frame-src 'none'",
            "worker-src 'none'",
            "font-src 'none'",
            "base-uri 'none'",
            "form-action 'none'"
        ].joined(separator: "; ")
    }
}

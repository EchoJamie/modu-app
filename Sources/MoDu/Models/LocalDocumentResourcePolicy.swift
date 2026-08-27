import Foundation
import UniformTypeIdentifiers

enum LocalDocumentResourcePolicy {
    enum StructuredDocumentLoad: Equatable, Sendable {
        case rendered
        case pagedSource
    }

    enum ImageUse: Sendable {
        case markdownEmbedded
        case interactiveHTML
        case standalonePreview
        case webResource
    }

    static let resourceScheme = "modu-resource"
    static let documentLinkScheme = "modu-markdown"
    static let bundledAssetScheme = "modu-asset"
    static let maximumResourceBytes = 40 * 1_024 * 1_024
    static let maximumStructuredDocumentBytes = 16 * 1_024 * 1_024

    static func structuredDocumentLoad(forByteCount byteCount: Int64) -> StructuredDocumentLoad {
        byteCount > Int64(maximumStructuredDocumentBytes) ? .pagedSource : .rendered
    }

    static let mermaidVersion = "11.16.1"
    static let highlighterVersion = "11.12.0"
    static var mermaidScriptURL: String {
        "\(bundledAssetScheme)://mermaid/mermaid-\(mermaidVersion).min.js"
    }

    static var highlighterScriptURL: String {
        "\(bundledAssetScheme)://highlighter/highlight-\(highlighterVersion).min.js"
    }

    static var highlighterAddonURLs: [String] {
        ["dockerfile", "groovy", "gradle", "properties", "toml"].map {
            "\(bundledAssetScheme)://highlighter/\($0)-\(highlighterVersion).min.js"
        }
    }

    private static let imageMIMETypes: [String: String] = [
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "heic": "image/heic",
        "heif": "image/heif",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "bmp": "image/bmp",
        "ico": "image/x-icon",
        "avif": "image/avif",
        "svg": "image/svg+xml"
    ]

    private static let markdownEmbeddedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp"
    ]

    static func imageExtensions(for use: ImageUse) -> Set<String> {
        switch use {
        case .markdownEmbedded:
            markdownEmbeddedImageExtensions
        case .interactiveHTML, .standalonePreview, .webResource:
            Set(imageMIMETypes.keys)
        }
    }

    static func supportsImageExtension(_ fileExtension: String, for use: ImageUse) -> Bool {
        imageExtensions(for: use).contains(fileExtension.lowercased())
    }

    static func mimeType(forImageExtension fileExtension: String) -> String? {
        imageMIMETypes[fileExtension.lowercased()]
    }

    static func mimeType(forWebResourceExtension fileExtension: String) -> String {
        mimeType(forImageExtension: fileExtension)
            ?? UTType(filenameExtension: fileExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }
}

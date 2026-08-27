import Foundation
import ImageIO

enum ImageDocumentError: LocalizedError {
    case invalidImage
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            L10n.string(.imagePreviewInvalid)
        case .tooLarge:
            L10n.format(
                .imagePreviewTooLarge,
                LocalDocumentResourcePolicy.maximumResourceBytes / 1_024 / 1_024
            )
        }
    }
}

final class ImageDocumentRenderer {
    static let stylesheet = """
    html, body { width: 100%; min-height: 100%; margin: 0; background: var(--canvas); }
    body { overflow: auto; }
    #write.image-document { box-sizing: border-box; display: flex; align-items: center; justify-content: center; width: 100%; min-height: 100vh; max-width: none; margin: 0; padding: 24px; background: var(--canvas); }
    .image-document img { display: block; width: auto; height: auto; max-width: 100%; max-height: calc(100vh - 48px); object-fit: contain; }
    """

    private let style: ResolvedReaderTheme
    private let documentURL: URL
    private let rootURL: URL

    init(style: ResolvedReaderTheme, documentURL: URL, rootURL: URL) {
        self.style = style
        self.documentURL = documentURL
        self.rootURL = rootURL
    }

    func render() throws -> RenderedDocument {
        try Task.checkCancellation()
        let readableURL = try FileSystemService.validatedURL(documentURL, inside: rootURL)
        guard LocalDocumentResourcePolicy.supportsImageExtension(
            documentURL.pathExtension,
            for: .standalonePreview
        ) else {
            throw ImageDocumentError.invalidImage
        }

        let values = try readableURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        guard values.isRegularFile == true else { throw ImageDocumentError.invalidImage }
        let fileSize = values.fileSize ?? 0
        guard fileSize <= LocalDocumentResourcePolicy.maximumResourceBytes else {
            throw ImageDocumentError.tooLarge
        }
        try validateImageContent(at: readableURL)
        guard let resourceURL = resourceURL(for: readableURL) else {
            throw ImageDocumentError.invalidImage
        }

        let html = """
        <!doctype html>
        <html lang="\(L10n.htmlLanguageCode)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta http-equiv="Content-Security-Policy" content="\(DocumentSecurityPolicy.imageValue())">
          <title>\(escape(documentURL.lastPathComponent))</title>
          <style id="modu-theme">\(style.stylesheet)\n\(Self.stylesheet)</style>
        </head>
        <body>
          <main id="write" class="image-document">
            <img src="\(escape(resourceURL))" alt="\(escape(documentURL.lastPathComponent))">
          </main>
        </body>
        </html>
        """

        return RenderedDocument(
            content: .image(html),
            outline: [],
            fileSize: Int64(fileSize),
            modifiedAt: values.contentModificationDate
        )
    }

    private func resourceURL(for readableURL: URL) -> String? {
        let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let filePath = readableURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return nil }
        let relativePath = String(filePath.dropFirst(rootPath.count + 1))
        var components = URLComponents()
        components.scheme = LocalDocumentResourcePolicy.resourceScheme
        components.host = "local"
        components.queryItems = [URLQueryItem(name: "path", value: relativePath)]
        return components.string
    }

    private func validateImageContent(at readableURL: URL) throws {
        if readableURL.pathExtension.lowercased() == "svg" {
            let data = try Data(contentsOf: readableURL, options: .mappedIfSafe)
            let parser = XMLParser(data: data)
            let validator = SVGRootValidator()
            parser.delegate = validator
            parser.shouldResolveExternalEntities = false
            guard parser.parse(), validator.hasSVGRoot else {
                throw ImageDocumentError.invalidImage
            }
            return
        }

        guard
            let source = CGImageSourceCreateWithURL(readableURL as CFURL, nil),
            CGImageSourceGetCount(source) > 0,
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        else { throw ImageDocumentError.invalidImage }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 32,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil else {
            throw ImageDocumentError.invalidImage
        }
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private final class SVGRootValidator: NSObject, XMLParserDelegate {
    private(set) var hasSVGRoot = false
    private var sawRootElement = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard !sawRootElement else { return }
        sawRootElement = true
        let normalizedName = (qName ?? elementName)
            .split(separator: ":")
            .last?
            .lowercased()
        hasSVGRoot = normalizedName == "svg"
    }
}

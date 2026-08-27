import Foundation
import WebKit

final class BundledAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    private static let maximumAssetSize = 5 * 1_024 * 1_024

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard
            let requestURL = urlSchemeTask.request.url,
            requestURL.scheme == LocalDocumentResourcePolicy.bundledAssetScheme,
            let assetURL = Self.assetURL(for: requestURL)
        else {
            fail(urlSchemeTask, code: .badURL)
            return
        }

        do {
            let values = try assetURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= Self.maximumAssetSize else {
                fail(urlSchemeTask, code: .dataLengthExceedsMaximum)
                return
            }

            let data = try Data(contentsOf: assetURL, options: [.mappedIfSafe])
            let response = URLResponse(
                url: requestURL,
                mimeType: "application/javascript",
                expectedContentLength: data.count,
                textEncodingName: "utf-8"
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    static var mermaidAssetURL: URL? {
        Bundle.main.url(
            forResource: "mermaid.min",
            withExtension: "js",
            subdirectory: "Mermaid"
        ) ?? AppResources.bundle.url(
            forResource: "mermaid.min",
            withExtension: "js",
            subdirectory: "Mermaid"
        )
    }

    static var highlighterAssetURL: URL? {
        assetURL(named: "highlight.min", subdirectory: "Highlighter")
    }

    private static func assetURL(for requestURL: URL) -> URL? {
        if
            requestURL.host == "mermaid",
            requestURL.path == "/mermaid-\(LocalDocumentResourcePolicy.mermaidVersion).min.js"
        {
            return mermaidAssetURL
        }

        guard requestURL.host == "highlighter" else { return nil }
        let expectedAssets: [String: String] = [
            "/highlight-\(LocalDocumentResourcePolicy.highlighterVersion).min.js": "highlight.min",
            "/dockerfile-\(LocalDocumentResourcePolicy.highlighterVersion).min.js": "dockerfile.min",
            "/groovy-\(LocalDocumentResourcePolicy.highlighterVersion).min.js": "groovy.min",
            "/gradle-\(LocalDocumentResourcePolicy.highlighterVersion).min.js": "gradle.min",
            "/properties-\(LocalDocumentResourcePolicy.highlighterVersion).min.js": "properties.min",
            "/toml-\(LocalDocumentResourcePolicy.highlighterVersion).min.js": "toml.min"
        ]
        guard let resource = expectedAssets[requestURL.path] else { return nil }
        return assetURL(named: resource, subdirectory: "Highlighter")
    }

    private static func assetURL(named name: String, subdirectory: String) -> URL? {
        Bundle.main.url(
            forResource: name,
            withExtension: "js",
            subdirectory: subdirectory
        ) ?? AppResources.bundle.url(
            forResource: name,
            withExtension: "js",
            subdirectory: subdirectory
        )
    }

    private func fail(_ task: WKURLSchemeTask, code: URLError.Code) {
        task.didFailWithError(URLError(code))
    }
}

final class LocalResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    var rootURL: URL?

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    static func resourceURL(for fileURL: URL, inside rootURL: URL) -> URL? {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let file = fileURL.resolvingSymlinksInPath().standardizedFileURL
        guard
            file.path.hasPrefix(root.path + "/"),
            (try? FileSystemService.validate(file, inside: root)) != nil
        else { return nil }

        var components = URLComponents()
        components.scheme = LocalDocumentResourcePolicy.resourceScheme
        components.host = "local"
        components.path = "/" + String(file.path.dropFirst(root.path.count + 1))
        return components.url
    }

    static func fileURL(for requestURL: URL, inside rootURL: URL) -> URL? {
        guard
            requestURL.scheme == LocalDocumentResourcePolicy.resourceScheme,
            requestURL.host == "local"
        else { return nil }
        let queryPath = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "path" })?.value
        let path = queryPath ?? String(requestURL.path.drop(while: { $0 == "/" }))
        guard !path.isEmpty else { return nil }
        let candidate = rootURL.appendingPathComponent(path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard (try? FileSystemService.validate(candidate, inside: rootURL)) != nil else { return nil }
        return candidate
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard
            let requestURL = urlSchemeTask.request.url,
            requestURL.scheme == LocalDocumentResourcePolicy.resourceScheme,
            let rootURL,
            let candidate = Self.fileURL(for: requestURL, inside: rootURL)
        else {
            fail(urlSchemeTask, code: .badURL)
            return
        }

        let mimeType = LocalDocumentResourcePolicy.mimeType(
            forWebResourceExtension: candidate.pathExtension
        )

        do {
            let data = try FileSystemService.readData(
                at: candidate,
                inside: rootURL,
                maximumBytes: LocalDocumentResourcePolicy.maximumResourceBytes
            )
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fail(_ task: WKURLSchemeTask, code: URLError.Code) {
        task.didFailWithError(URLError(code))
    }
}

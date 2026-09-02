import Foundation

struct CommandLineWorkspaceOpenRequest: Equatable {
    let id: UUID
    let workspaceRequest: WorkspaceOpenRequest
    let opensNewWindow: Bool
}

struct WorkspaceOpenRequest: Identifiable, Equatable {
    static let commandLineURLScheme = "modu-cli"

    let id: UUID
    let workspaceURL: URL
    let documentURL: URL?

    init(id: UUID = UUID(), workspaceURL: URL, documentURL: URL? = nil) {
        self.id = id
        self.workspaceURL = workspaceURL.standardizedFileURL
        self.documentURL = documentURL?.standardizedFileURL
    }

    static func resolve(urls: [URL]) -> WorkspaceOpenRequest? {
        let candidates = urls.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        let directoryURL = candidates.first { resourceValues(for: $0)?.isDirectory == true }
        let fileURL = candidates.first { resourceValues(for: $0)?.isRegularFile == true }

        if let directoryURL {
            let documentURL = fileURL.flatMap { candidate in
                (try? FileSystemService.validate(candidate, inside: directoryURL)) != nil
                    ? candidate
                    : nil
            }
            return WorkspaceOpenRequest(
                workspaceURL: directoryURL,
                documentURL: documentURL
            )
        }

        guard let fileURL else { return nil }
        return WorkspaceOpenRequest(
            workspaceURL: fileURL.deletingLastPathComponent(),
            documentURL: fileURL
        )
    }

    static func isCommandLineWindowMarker(_ url: URL) -> Bool {
        guard
            url.scheme?.caseInsensitiveCompare(commandLineURLScheme) == .orderedSame,
            url.host?.caseInsensitiveCompare("open") == .orderedSame
        else { return false }

        let requestID = url.pathComponents.last
        return requestID.flatMap(UUID.init(uuidString:)) != nil
    }

    static func commandLineWindowRequests(
        from urls: [URL]
    ) -> [CommandLineWorkspaceOpenRequest] {
        let deliveredPaths = Set(
            urls
                .filter(\.isFileURL)
                .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        )
        var seenRequestIDs: Set<UUID> = []

        return urls.compactMap { marker in
            guard
                isCommandLineWindowMarker(marker),
                let components = URLComponents(url: marker, resolvingAgainstBaseURL: false),
                let requestIDText = marker.pathComponents.last,
                let requestID = UUID(uuidString: requestIDText),
                seenRequestIDs.insert(requestID).inserted,
                let mode = components.queryValue(named: "mode"),
                mode == "new" || mode == "reuse",
                let workspaceValue = components.queryValue(named: "workspace"),
                let workspacePath = decodedCommandLinePath(workspaceValue)
            else { return nil }

            let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let documentURL = components.queryValue(named: "document")
                .flatMap(decodedCommandLinePath)
                .map {
                    URL(fileURLWithPath: $0)
                        .resolvingSymlinksInPath()
                        .standardizedFileURL
                }
            guard deliveredPaths.contains(workspaceURL.path) else { return nil }
            if let documentURL, !deliveredPaths.contains(documentURL.path) {
                return nil
            }

            let requestURLs = [workspaceURL] + (documentURL.map { [$0] } ?? [])
            guard let workspaceRequest = resolve(urls: requestURLs) else { return nil }
            return CommandLineWorkspaceOpenRequest(
                id: requestID,
                workspaceRequest: workspaceRequest,
                opensNewWindow: mode == "new"
            )
        }
    }

    static func commandLineWindowMarkerURL(
        id: UUID = UUID(),
        workspaceURL: URL,
        documentURL: URL? = nil,
        opensNewWindow: Bool
    ) -> URL? {
        var components = URLComponents()
        components.scheme = commandLineURLScheme
        components.host = "open"
        components.path = "/\(id.uuidString.lowercased())"
        components.queryItems = [
            URLQueryItem(name: "mode", value: opensNewWindow ? "new" : "reuse"),
            URLQueryItem(
                name: "workspace",
                value: encodedCommandLinePath(workspaceURL.path)
            )
        ]
        if let documentURL {
            components.queryItems?.append(
                URLQueryItem(
                    name: "document",
                    value: encodedCommandLinePath(documentURL.path)
                )
            )
        }
        return components.url
    }

    private static func encodedCommandLinePath(_ path: String) -> String {
        Data(path.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodedCommandLinePath(_ value: String) -> String? {
        var base64 = value
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "+")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard
            let data = Data(base64Encoded: base64),
            let path = String(data: data, encoding: .utf8),
            path.hasPrefix("/")
        else { return nil }
        return path
    }

    private static func resourceValues(for url: URL) -> URLResourceValues? {
        try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
    }
}

private extension URLComponents {
    func queryValue(named name: String) -> String? {
        queryItems?.first(where: { $0.name == name })?.value
    }
}

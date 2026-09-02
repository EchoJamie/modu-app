import Foundation

struct WorkspaceOpenRequest: Identifiable, Equatable {
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

    private static func resourceValues(for url: URL) -> URLResourceValues? {
        try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
    }
}

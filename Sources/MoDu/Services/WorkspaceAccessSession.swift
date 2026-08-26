import Foundation

final class WorkspaceAccessSession: @unchecked Sendable {
    let rootURL: URL
    private let securityScopedURL: URL
    private let didStartAccessing: Bool

    init(url: URL) {
        securityScopedURL = url
        rootURL = url.standardizedFileURL
        didStartAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccessing {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
    }
}

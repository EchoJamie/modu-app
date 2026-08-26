import Foundation

enum FileNodeKind: Sendable {
    case directory
    case file
}

struct FileEntry: Sendable {
    let url: URL
    let kind: FileNodeKind
}

@MainActor
final class FileNode: ObservableObject, Identifiable {
    let id: String
    let url: URL
    let name: String
    let kind: FileNodeKind

    @Published var children: [FileNode]?
    @Published var isExpanded = false
    @Published var isLoading = false
    var loadingTask: Task<Void, Never>?
    var loadingGeneration = UUID()

    init(entry: FileEntry) {
        id = entry.url.path
        url = entry.url
        name = entry.url.lastPathComponent
        kind = entry.kind
    }

    deinit {
        loadingTask?.cancel()
    }

    var isDirectory: Bool { kind == .directory }

    var isMarkdown: Bool {
        Self.markdownExtensions.contains(url.pathExtension.lowercased())
    }

    var isHTML: Bool {
        Self.htmlExtensions.contains(url.pathExtension.lowercased())
    }

    var isPreviewable: Bool {
        Self.previewableExtensions.contains(url.pathExtension.lowercased())
    }

    var iconName: String {
        if isDirectory { return isExpanded ? "folder.fill.badge.minus" : "folder.fill" }
        if isMarkdown { return "doc.richtext" }
        if isHTML { return "globe" }

        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg":
            return "photo"
        case "swift", "js", "ts", "tsx", "jsx", "py", "go", "rs", "java", "css", "html", "json", "yaml", "yml":
            return "chevron.left.forwardslash.chevron.right"
        case "pdf":
            return "doc.text.image"
        default:
            return "doc"
        }
    }

    nonisolated static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    nonisolated static let htmlExtensions: Set<String> = ["html", "htm"]
    nonisolated static let previewableExtensions = markdownExtensions.union(htmlExtensions)
}

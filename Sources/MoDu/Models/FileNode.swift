import Foundation

enum FileNodeKind: Sendable, Equatable {
    case directory
    case file
}

@MainActor
enum FileTreeMerger {
    static func prepareForRefresh(_ nodes: [FileNode]) {
        for node in nodes {
            node.loadingTask?.cancel()
            node.loadingTask = nil
            node.loadingGeneration = UUID()
            if node.isLoading {
                node.isLoading = false
            }
            if let children = node.children {
                prepareForRefresh(children)
            }
        }
    }

    static func merge(
        entries: [FileEntry],
        reusing existingNodes: [FileNode],
        refreshedEntriesByDirectory: [String: [FileEntry]],
        forcedExpandedPaths: Set<String>
    ) -> [FileNode] {
        var existingByID = Dictionary(uniqueKeysWithValues: existingNodes.map { ($0.id, $0) })
        var mergedNodes: [FileNode] = []
        mergedNodes.reserveCapacity(entries.count)

        for entry in entries {
            let entryID = entry.url.path
            let previousNode = existingByID.removeValue(forKey: entryID)
            let node: FileNode
            if let previousNode, previousNode.kind == entry.kind {
                node = previousNode
            } else {
                if let previousNode {
                    cancelRecursively(previousNode)
                }
                node = FileNode(entry: entry)
            }

            if node.isDirectory {
                let shouldExpand = node.isExpanded || forcedExpandedPaths.contains(entryID)
                if node.isExpanded != shouldExpand {
                    node.isExpanded = shouldExpand
                }
                if shouldExpand, let childEntries = refreshedEntriesByDirectory[entryID] {
                    node.loadingTask?.cancel()
                    node.loadingTask = nil
                    node.loadingGeneration = UUID()
                    let existingChildren = node.children ?? []
                    let mergedChildren = merge(
                        entries: childEntries,
                        reusing: existingChildren,
                        refreshedEntriesByDirectory: refreshedEntriesByDirectory,
                        forcedExpandedPaths: forcedExpandedPaths
                    )
                    if node.children == nil || !hasSameIdentityOrder(existingChildren, mergedChildren) {
                        node.children = mergedChildren
                    }
                    if node.isLoading {
                        node.isLoading = false
                    }
                } else if !shouldExpand {
                    if let children = node.children {
                        children.forEach(cancelRecursively)
                        node.children = nil
                    }
                    if node.isLoading {
                        node.isLoading = false
                    }
                }
            }
            mergedNodes.append(node)
        }

        existingByID.values.forEach(cancelRecursively)
        return mergedNodes
    }

    static func hasSameIdentityOrder(_ lhs: [FileNode], _ rhs: [FileNode]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    private static func cancelRecursively(_ node: FileNode) {
        node.loadingTask?.cancel()
        node.loadingTask = nil
        node.loadingGeneration = UUID()
        node.children?.forEach(cancelRecursively)
    }
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

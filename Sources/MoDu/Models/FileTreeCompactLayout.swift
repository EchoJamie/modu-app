import Foundation

/// A presentation of already-loaded nodes; never starts directory reads.
@MainActor
enum FileTreeCompactLayout {
    static func compactedChild(of node: FileNode, editingNodeID: String?) -> FileNode? {
        guard node.isDirectory, node.isExpanded, !node.isLoading,
              node.id != editingNodeID,
              let children = node.children, children.count == 1,
              let child = children.first, child.isDirectory
        else { return nil }
        return child
    }

    static func visibleRows(in nodes: [FileNode], editingNodeID: String? = nil) -> [[FileNode]] {
        var rows: [[FileNode]] = []
        for node in nodes {
            var chain = [node]
            var terminal = node
            while let child = compactedChild(of: terminal, editingNodeID: editingNodeID) {
                chain.append(child)
                terminal = child
            }
            rows.append(chain)
            if terminal.isExpanded, let children = terminal.children {
                rows.append(contentsOf: visibleRows(in: children, editingNodeID: editingNodeID))
            }
        }
        return rows
    }
}

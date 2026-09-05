import Foundation
import Testing
@testable import MoDu

@Suite("Compact directory presentation")
@MainActor
struct FileTreeCompactLayoutTests {
    @Test("A loaded directory chain occupies one navigation row and preserves every node")
    func loadedChain() {
        let source = directory("/workspace/src")
        let main = directory("/workspace/src/main")
        let java = directory("/workspace/src/main/java")
        let file = FileNode(entry: FileEntry(url: java.url.appendingPathComponent("App.java"), kind: .file))
        expand(source, with: [main])
        expand(main, with: [java])
        expand(java, with: [file])

        let rows = FileTreeCompactLayout.visibleRows(in: [source])
        #expect(rows.map { $0.map(\.name) } == [["src", "main", "java"], ["App.java"]])
        #expect(rows[0][0] === source)
        #expect(rows[0][1] === main)
        #expect(rows[0][2] === java)
        #expect(source.children?.first === main)
        #expect(rows[1].first?.id == file.id)
    }

    @Test("Files and sibling directories stop compaction")
    func branchingContents() {
        let source = directory("/workspace/src")
        let main = directory("/workspace/src/main")
        let tests = directory("/workspace/src/test")
        let file = FileNode(entry: FileEntry(url: source.url.appendingPathComponent("README.md"), kind: .file))
        expand(source, with: [main, tests])
        #expect(FileTreeCompactLayout.visibleRows(in: [source]).map { $0.map(\.name) }
            == [["src"], ["main"], ["test"]])
        source.children = [main, file]
        #expect(FileTreeCompactLayout.visibleRows(in: [source]).map { $0.map(\.name) }
            == [["src"], ["main"], ["README.md"]])
    }

    @Test("Unknown and loading directories are not scanned or compacted speculatively")
    func unloadedContents() {
        let source = directory("/workspace/src")
        #expect(FileTreeCompactLayout.visibleRows(in: [source]).count == 1)
        #expect(source.children == nil)
        #expect(source.loadingTask == nil)
        #expect(!source.isExpanded)

        let main = directory("/workspace/src/main")
        expand(source, with: [main])
        source.isLoading = true
        #expect(FileTreeCompactLayout.visibleRows(in: [source]).map { $0.map(\.name) }
            == [["src"], ["main"]])
        #expect(main.children == nil)
        #expect(main.loadingTask == nil)
    }

    @Test("Collapsing the terminal keeps the loaded prefix and hides descendants")
    func collapsedTerminal() {
        let source = directory("/workspace/src")
        let main = directory("/workspace/src/main")
        expand(source, with: [main])
        #expect(FileTreeCompactLayout.visibleRows(in: [source]).map { $0.map(\.name) }
            == [["src", "main"]])
        source.isExpanded = false
        source.children = nil
        #expect(FileTreeCompactLayout.visibleRows(in: [source]).map { $0.map(\.name) } == [["src"]])
    }

    @Test("Renaming an intermediate directory stops merging at that directory")
    func editingIntermediateDirectory() {
        let source = directory("/workspace/src")
        let main = directory("/workspace/src/main")
        let java = directory("/workspace/src/main/java")
        expand(source, with: [main])
        expand(main, with: [java])
        #expect(FileTreeCompactLayout.visibleRows(in: [source], editingNodeID: main.id)
            .map { $0.map(\.name) } == [["src", "main"], ["java"]])
        #expect(FileTreeCompactLayout.visibleRows(in: [source], editingNodeID: source.id)
            .map { $0.map(\.name) } == [["src"], ["main", "java"]])
    }

    private func directory(_ path: String) -> FileNode {
        FileNode(entry: FileEntry(url: URL(fileURLWithPath: path), kind: .directory))
    }

    private func expand(_ node: FileNode, with children: [FileNode]) {
        node.children = children
        node.isExpanded = true
    }
}

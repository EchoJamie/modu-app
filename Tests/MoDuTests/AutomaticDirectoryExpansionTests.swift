import AppKit
import Foundation
import Testing
@testable import MoDu

@Suite("Automatic single-directory expansion")
@MainActor
struct AutomaticDirectoryExpansionTests {
    @Test("One expand opens a five-level chain and shows the terminal file")
    func opensEntireChain() async throws {
        _ = NSApplication.shared
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultsName = "AutomaticExpansion.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let model = ReaderViewModel(restorePersistedState: false, applicationState: ApplicationState(defaults: defaults))
        model.openWorkspace(root)
        #expect(await waitUntil { !model.rootIsLoading })
        let java = try #require(model.rootNodes.first { $0.name == "java" })
        #expect(java.children == nil)

        model.setExpanded(java, expanded: true)
        let task = try #require(java.loadingTask)
        await task.value

        let rows = FileTreeCompactLayout.visibleRows(in: [java])
        #expect(rows.map { $0.map(\.name) } == [["java", "com", "definesys", "ai", "admin"], ["App.java"]])
        #expect(rows[0].allSatisfy { $0.isExpanded })
        #expect(!java.isLoading)
        #expect(java.loadingTask == nil)
        #expect(model.selectedURL == nil)
    }

    @Test("Files and branching directories stop automatic reads")
    func stopsAtBranchesAndFiles() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let java = root.appendingPathComponent("java")
        let com = java.appendingPathComponent("com")
        let readme = com.appendingPathComponent("README.md")
        try "# Readme".write(to: readme, atomically: true, encoding: .utf8)
        let withFile = try await FileSystemService.directoryChain(at: java, inside: root)
        #expect(withFile.map { $0.url.lastPathComponent } == ["java", "com"])
        try FileManager.default.removeItem(at: readme)
        try FileManager.default.createDirectory(at: com.appendingPathComponent("other"), withIntermediateDirectories: true)
        let withBranch = try await FileSystemService.directoryChain(at: java, inside: root)
        #expect(withBranch.map { $0.url.lastPathComponent } == ["java", "com"])
        #expect(withBranch.last?.entries.count == 2)
    }

    @Test("A symbolic link to an already visited directory stops the chain")
    func stopsAtLinkCycle() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let loop = root.appendingPathComponent("loop")
        try FileManager.default.createDirectory(at: loop, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: loop.appendingPathComponent("again"), withDestinationURL: loop)
        let result = try await FileSystemService.directoryChain(at: loop, inside: root)
        #expect(result.count == 1)
        #expect(result.first?.entries.first?.url.lastPathComponent == "again")
    }

    @Test("Collapse and workspace replacement discard pending automatic expansion")
    func cancelsPendingExpansion() async throws {
        _ = NSApplication.shared
        let root = try fixture()
        let secondRoot = try fixture()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let defaultsName = "AutomaticExpansion.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let model = ReaderViewModel(restorePersistedState: false, applicationState: ApplicationState(defaults: defaults))
        model.openWorkspace(root)
        #expect(await waitUntil { !model.rootIsLoading })
        let java = try #require(model.rootNodes.first { $0.name == "java" })
        model.setExpanded(java, expanded: true)
        let collapsedTask = try #require(java.loadingTask)
        model.setExpanded(java, expanded: false)
        await collapsedTask.value
        #expect(!java.isExpanded && !java.isLoading)
        #expect(java.children == nil)

        model.setExpanded(java, expanded: true)
        let replacedTask = try #require(java.loadingTask)
        model.openWorkspace(secondRoot)
        #expect(replacedTask.isCancelled)
        await replacedTask.value
        #expect(java.children == nil)
        #expect(model.rootURL == secondRoot.standardizedFileURL)
        #expect(await waitUntil { !model.rootIsLoading })
        #expect(model.rootNodes.allSatisfy { $0.url.path.hasPrefix(secondRoot.path + "/") })
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("modu-auto-expand-\(UUID().uuidString)")
        let terminal = root.appendingPathComponent("java/com/definesys/ai/admin")
        try FileManager.default.createDirectory(at: terminal, withIntermediateDirectories: true)
        try "class App {}".write(to: terminal.appendingPathComponent("App.java"), atomically: true, encoding: .utf8)
        return root
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if condition() { return true }
            await Task.yield()
        }
        return false
    }
}

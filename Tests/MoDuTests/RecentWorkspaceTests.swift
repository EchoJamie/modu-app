import AppKit
import Foundation
import Testing
@testable import MoDu

@Suite("Recent workspace cleanup")
struct RecentWorkspaceTests {
    @Test("Single removal persists without switching workspaces or removing the current one")
    @MainActor
    func removesOnlySelectedHistoryEntry() throws {
        _ = NSApplication.shared
        let suiteName = "RecentWorkspaceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let current = directory.appendingPathComponent("current", isDirectory: true)
        let removed = directory.appendingPathComponent("removed", isDirectory: true)
        let retained = directory.appendingPathComponent("retained", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        for url in [current, removed, retained] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        let state = ApplicationState(defaults: defaults)
        let model = ReaderViewModel(restorePersistedState: false, applicationState: state)
        model.openWorkspace(current)
        try state.rememberWorkspace(removed, existingBookmarkData: nil)
        try state.rememberWorkspace(retained, existingBookmarkData: nil)
        let currentEntry = try #require(state.recentWorkspaces.first { $0.id == current.path })
        let removedEntry = try #require(state.recentWorkspaces.first { $0.id == removed.path })

        model.removeRecentWorkspace(removedEntry)
        model.removeRecentWorkspace(currentEntry)

        let expectedIDs = [retained.standardizedFileURL.path, current.standardizedFileURL.path]
        #expect(state.recentWorkspaces.map(\.id) == expectedIDs)
        #expect(model.rootURL == current.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: removed.path))
        #expect(ApplicationState(defaults: defaults).recentWorkspaces.map(\.id) == expectedIDs)
    }

    @Test("Cleanup preserves the current workspace across application restart")
    @MainActor
    func preservesCurrentWorkspace() throws {
        _ = NSApplication.shared
        let suiteName = "RecentWorkspaceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let current = directory.appendingPathComponent("current", isDirectory: true)
        let other = directory.appendingPathComponent("other", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        let state = ApplicationState(defaults: defaults)
        let model = ReaderViewModel(restorePersistedState: false, applicationState: state)
        model.openWorkspace(current)
        // Another window can make a different workspace the most recent entry.
        try state.rememberWorkspace(other, existingBookmarkData: nil)
        #expect(model.canClearRecentWorkspaces)

        model.clearRecentWorkspaces()

        #expect(model.rootURL == current.standardizedFileURL)
        #expect(state.recentWorkspaces.map(\.id) == [current.standardizedFileURL.path])
        #expect(!model.canClearRecentWorkspaces)
        #expect(model.fileOperationError == nil)
        let restoredState = ApplicationState(defaults: defaults)
        let restoredModel = ReaderViewModel(applicationState: restoredState)
        #expect(restoredModel.rootURL == current.standardizedFileURL)
    }

    @Test("Cleanup can restore a current workspace missing from shared history")
    @MainActor
    func retainsMissingCurrentWorkspace() throws {
        let suiteName = "RecentWorkspaceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let state = ApplicationState(defaults: defaults)
        try state.clearRecentWorkspaces(preserving: directory)

        let restored = ApplicationState(defaults: defaults)
        #expect(restored.recentWorkspaces.map(\.id) == [directory.standardizedFileURL.path])
    }

    @Test("Cleanup without an open workspace removes persisted history")
    @MainActor
    func clearsAllWithoutCurrentWorkspace() throws {
        _ = NSApplication.shared
        let suiteName = "RecentWorkspaceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = ApplicationState(defaults: defaults)
        try state.rememberWorkspace(FileManager.default.temporaryDirectory, existingBookmarkData: nil)
        let model = ReaderViewModel(restorePersistedState: false, applicationState: state)
        #expect(model.canClearRecentWorkspaces)

        model.clearRecentWorkspaces()

        #expect(state.recentWorkspaces.isEmpty)
        #expect(!model.canClearRecentWorkspaces)
        #expect(ApplicationState(defaults: defaults).recentWorkspaces.isEmpty)
    }
}

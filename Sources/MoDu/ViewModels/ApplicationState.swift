import AppKit
import Foundation
import SwiftUI

@MainActor
final class ApplicationState: ObservableObject {
    @Published private(set) var appLanguage: AppLanguage
    @Published private(set) var appAppearance: AppAppearance
    @Published private(set) var markdownStyle: MarkdownStyle
    @Published private(set) var recentWorkspaces: [RecentWorkspace] = []

    private let defaults: UserDefaults

    private static let recentWorkspaceBookmarksKey = "recentWorkspaceBookmarks.v1"
    private static let readerThemeKey = "readerTheme.v2"
    private static let maximumRecentWorkspaceCount = 8

    init(
        defaults: UserDefaults = .standard,
        restoreRecentWorkspaces: Bool = true
    ) {
        self.defaults = defaults

        let legacyTheme = defaults.string(forKey: "readerTheme")
        let savedTheme = defaults.string(forKey: Self.readerThemeKey)
            ?? defaults.string(forKey: "markdownStyle")
            ?? legacyTheme
        markdownStyle = MarkdownStyle.migrated(from: savedTheme) ?? .newsprint
        appLanguage = AppLanguage.restored(from: defaults)

        if
            let savedAppearance = defaults.string(forKey: "appAppearance"),
            let restored = AppAppearance(rawValue: savedAppearance)
        {
            appAppearance = restored
        } else if legacyTheme == "dark" || legacyTheme == "graphite" {
            appAppearance = .dark
        } else if legacyTheme != nil {
            appAppearance = .light
        } else {
            appAppearance = .system
        }

        if restoreRecentWorkspaces {
            restoreRecentWorkspaceBookmarks()
        }
    }

    func selectAppLanguage(_ newLanguage: AppLanguage) {
        guard appLanguage != newLanguage else { return }
        defaults.set(newLanguage.rawValue, forKey: AppLanguage.storageKey)
        appLanguage = newLanguage
    }

    func selectAppAppearance(_ newAppearance: AppAppearance) {
        guard appAppearance != newAppearance else { return }
        appAppearance = newAppearance
        defaults.set(newAppearance.rawValue, forKey: "appAppearance")
    }

    func selectMarkdownStyle(_ newStyle: MarkdownStyle) {
        guard markdownStyle != newStyle else { return }
        markdownStyle = newStyle
        defaults.set(newStyle.rawValue, forKey: Self.readerThemeKey)
        defaults.set(newStyle.rawValue, forKey: "markdownStyle")
    }

    func clearRecentWorkspaces() {
        recentWorkspaces = []
        defaults.removeObject(forKey: Self.recentWorkspaceBookmarksKey)
    }

    func resolvedRecentWorkspace(_ workspace: RecentWorkspace) -> RecentWorkspace? {
        resolvedRecentWorkspace(from: workspace.bookmarkData)
    }

    func removeRecentWorkspace(id: String) {
        recentWorkspaces.removeAll { $0.id == id }
        persistRecentWorkspaces()
    }

    func rememberWorkspace(_ url: URL, existingBookmarkData: Data?) throws {
        let bookmarkData = try existingBookmarkData ?? makeBookmark(for: url)
        let workspace = RecentWorkspace(url: url, bookmarkData: bookmarkData)
        recentWorkspaces.removeAll { $0.id == workspace.id }
        recentWorkspaces.insert(workspace, at: 0)
        if recentWorkspaces.count > Self.maximumRecentWorkspaceCount {
            recentWorkspaces.removeLast(
                recentWorkspaces.count - Self.maximumRecentWorkspaceCount
            )
        }
        persistRecentWorkspaces()
    }

    private func restoreRecentWorkspaceBookmarks() {
        let storedValues = defaults.array(forKey: Self.recentWorkspaceBookmarksKey) ?? []
        let storedBookmarks = storedValues.compactMap { $0 as? Data }
        var restored: [RecentWorkspace] = []
        var seenPaths: Set<String> = []

        for bookmarkData in storedBookmarks {
            guard restored.count < Self.maximumRecentWorkspaceCount else { break }
            guard let workspace = resolvedRecentWorkspace(from: bookmarkData) else { continue }
            guard seenPaths.insert(workspace.id).inserted else { continue }
            restored.append(workspace)
        }

        recentWorkspaces = restored
        persistRecentWorkspaces()
    }

    private func resolvedRecentWorkspace(from bookmarkData: Data) -> RecentWorkspace? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing { url.stopAccessingSecurityScopedResource() }
            }

            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { return nil }

            let currentBookmark = isStale ? try makeBookmark(for: url) : bookmarkData
            return RecentWorkspace(url: url, bookmarkData: currentBookmark)
        } catch {
            return nil
        }
    }

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: [.isDirectoryKey],
            relativeTo: nil
        )
    }

    private func persistRecentWorkspaces() {
        defaults.set(
            recentWorkspaces.map(\.bookmarkData),
            forKey: Self.recentWorkspaceBookmarksKey
        )
    }
}

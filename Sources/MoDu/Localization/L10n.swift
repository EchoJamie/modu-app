import Foundation

enum AppResources {
    static let bundle: Bundle = {
        if
            let resourceURL = Bundle.main.resourceURL?
                .appendingPathComponent("MoDu_MoDu.bundle", isDirectory: true),
            let bundle = Bundle(url: resourceURL)
        {
            return bundle
        }
        return Bundle.module
    }()
}

enum L10n {
    enum Key: String, CaseIterable, Sendable {
        case appName = "app.name"
        case commonOK = "common.ok"
        case commonUnknownError = "common.unknownError"
        case commandOpenFolder = "command.openFolder"
        case commandOpenRecent = "command.openRecent"
        case commandClearMenu = "command.clearMenu"
        case commandReading = "command.reading"
        case commandReloadDocumentOutline = "command.reloadDocumentOutline"
        case commandReloadDirectory = "command.reloadDirectory"
        case commandTheme = "command.theme"
        case commandDisplayMode = "command.displayMode"
        case commandOpenSecondPane = "command.openSecondPane"
        case commandCloseActivePane = "command.closeActivePane"
        case outlineHide = "outline.hide"
        case outlineShow = "outline.show"
        case outlineTitle = "outline.title"
        case outlineEmpty = "outline.empty"
        case outlineResizeHelp = "outline.resizeHelp"
        case outlineResizeAccessibility = "outline.resizeAccessibility"
        case appearanceSystem = "appearance.system"
        case appearanceLight = "appearance.light"
        case appearanceDark = "appearance.dark"
        case themeNewsprintName = "theme.newsprint.name"
        case themeNewsprintSubtitle = "theme.newsprint.subtitle"
        case themeMinimalName = "theme.minimal.name"
        case themeMinimalSubtitle = "theme.minimal.subtitle"
        case themeSepiaName = "theme.sepia.name"
        case themeSepiaSubtitle = "theme.sepia.subtitle"
        case themeDarkName = "theme.dark.name"
        case themeDarkSubtitle = "theme.dark.subtitle"
        case themeGitHubName = "theme.github.name"
        case themeGitHubSubtitle = "theme.github.subtitle"
        case errorOutsideWorkspace = "error.outsideWorkspace"
        case errorUnsupportedEncoding = "error.unsupportedEncoding"
        case errorEmptyName = "error.emptyName"
        case errorNameSeparator = "error.nameSeparator"
        case errorRenameOutside = "error.renameOutside"
        case errorTargetExists = "error.targetExists"
        case errorRecentUnavailable = "error.recentUnavailable"
        case errorBookmarkSave = "error.bookmarkSave"
        case errorReloadDirectory = "error.reloadDirectory"
        case workspaceNotOpened = "workspace.notOpened"
        case documentLoadFailed = "document.loadFailed"
        case folderPickerTitle = "folderPicker.title"
        case folderPickerMessage = "folderPicker.message"
        case folderPickerPrompt = "folderPicker.prompt"
        case sidebarLoading = "sidebar.loading"
        case sidebarPrivacyNote = "sidebar.privacyNote"
        case sidebarOperationFailed = "sidebar.operationFailed"
        case sidebarChooseWorkspace = "sidebar.chooseWorkspace"
        case sidebarCurrentWorkspaceSwitch = "sidebar.currentWorkspaceSwitch"
        case sidebarSwitchHelp = "sidebar.switchHelp"
        case sidebarReloadHelp = "sidebar.reloadHelp"
        case sidebarSwitchTitle = "sidebar.switchTitle"
        case sidebarRecent = "sidebar.recent"
        case sidebarNoOtherRecent = "sidebar.noOtherRecent"
        case sidebarOpenOther = "sidebar.openOther"
        case sidebarClearRecent = "sidebar.clearRecent"
        case sidebarEmpty = "sidebar.empty"
        case sidebarOpenFolder = "sidebar.openFolder"
        case documentClosePane = "document.closePane"
        case documentLoading = "document.loading"
        case documentUnsupportedTitle = "document.unsupportedTitle"
        case documentUnsupportedMessage = "document.unsupportedMessage"
        case documentFailedTitle = "document.failedTitle"
        case welcomeTitle = "welcome.title"
        case welcomeSubtitle = "welcome.subtitle"
        case welcomeLocalRendering = "welcome.localRendering"
        case welcomeRename = "welcome.rename"
        case welcomeSplitReading = "welcome.splitReading"
        case toolbarReloadHelp = "toolbar.reloadHelp"
        case toolbarOpenSplitHelp = "toolbar.openSplitHelp"
        case toolbarCloseSplitHelp = "toolbar.closeSplitHelp"
        case toolbarDisplayModeHelp = "toolbar.displayModeHelp"
        case toolbarThemeHelp = "toolbar.themeHelp"
        case fileTreeOpenOtherPane = "fileTree.openOtherPane"
        case fileTreeRename = "fileTree.rename"
        case fileTreeReturnKey = "fileTree.returnKey"
        case fileTreeCopyPath = "fileTree.copyPath"
        case fileTreeNamePlaceholder = "fileTree.namePlaceholder"
        case metadataAria = "metadata.aria"
        case metadataTitle = "metadata.title"
        case metadataCount = "metadata.count"
        case metadataExpandFull = "metadata.expandFull"
        case metadataExpandRemaining = "metadata.expandRemaining"
        case metadataCollapse = "metadata.collapse"
        case mermaidSourceSummary = "mermaid.sourceSummary"
        case mermaidAriaLabel = "mermaid.ariaLabel"
        case mermaidLimitStatus = "mermaid.limitStatus"
        case mermaidLimitDetail = "mermaid.limitDetail"
        case mermaidRendering = "mermaid.rendering"
        case mermaidUnable = "mermaid.unable"
        case mermaidOfflineMissing = "mermaid.offlineMissing"
        case mermaidSyntax = "mermaid.syntax"
        case mermaidFailed = "mermaid.failed"
        case imageNotLoaded = "image.notLoaded"
        case imageWithAlt = "image.withAlt"
        case webViewRecoveryTitle = "webView.recoveryTitle"
        case webViewRecoveryMessage = "webView.recoveryMessage"
    }

    static let supportedLanguages = ["en", "zh-Hans"]

    static var htmlLanguageCode: String {
        currentLanguage.hasPrefix("zh") ? "zh-CN" : "en"
    }

    static var currentLanguage: String {
        Bundle.preferredLocalizations(
            from: supportedLanguages,
            forPreferences: Locale.preferredLanguages
        ).first ?? "en"
    }

    static func string(_ key: Key) -> String {
        string(key, language: currentLanguage)
    }

    static func string(_ key: Key, language: String) -> String {
        translations[language]?[key.rawValue] ?? key.rawValue
    }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: Locale(identifier: currentLanguage),
            arguments: arguments
        )
    }

    private static let translations: [String: [String: String]] = {
        Dictionary(uniqueKeysWithValues: supportedLanguages.map { language in
            let values: [String: String]
            if
                let url = AppResources.bundle.url(
                    forResource: "Localizable",
                    withExtension: "strings",
                    subdirectory: nil,
                    localization: language
                ),
                let data = try? Data(contentsOf: url),
                let decoded = try? PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as? [String: String]
            {
                values = decoded
            } else {
                values = [:]
            }
            return (language, values)
        })
    }()
}

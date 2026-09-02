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
        case commonCancel = "common.cancel"
        case commonOK = "common.ok"
        case commonUnknownError = "common.unknownError"
        case settingsGeneralTitle = "settings.general.title"
        case settingsLanguage = "settings.language"
        case settingsAppearance = "settings.appearance"
        case languageSystem = "language.system"
        case languageEnglish = "language.english"
        case languageSimplifiedChinese = "language.simplifiedChinese"
        case settingsCLITitle = "settings.cli.title"
        case settingsCLIDescription = "settings.cli.description"
        case settingsCLIInstalled = "settings.cli.installed"
        case settingsCLINotInstalled = "settings.cli.notInstalled"
        case settingsCLIAuthorizing = "settings.cli.authorizing"
        case settingsCLIInstall = "settings.cli.install"
        case settingsCLIUninstall = "settings.cli.uninstall"
        case settingsCLIMissingTool = "settings.cli.error.missingTool"
        case settingsCLIMissingInstaller = "settings.cli.error.missingInstaller"
        case settingsCLITemporaryApp = "settings.cli.error.temporaryApp"
        case settingsCLITargetDirectory = "settings.cli.error.targetDirectory"
        case settingsCLIInstallationChanged = "settings.cli.error.installationChanged"
        case settingsCLIHelperLaunchFailed = "settings.cli.error.helperLaunchFailed"
        case settingsCLIOperationFailed = "settings.cli.error.operationFailed"
        case commandNewWindow = "command.newWindow"
        case commandOpenFolder = "command.openFolder"
        case commandOpenRecent = "command.openRecent"
        case commandClearMenu = "command.clearMenu"
        case commandReading = "command.reading"
        case commandReloadDocumentOutline = "command.reloadDocumentOutline"
        case commandReloadDirectory = "command.reloadDirectory"
        case commandTheme = "command.theme"
        case commandOpenSecondPane = "command.openSecondPane"
        case commandCloseActivePane = "command.closeActivePane"
        case commandFindInDocument = "command.findInDocument"
        case commandGoToLine = "command.goToLine"
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
        case errorStructuredDocumentTooLarge = "error.structuredDocumentTooLarge"
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
        case sidebarTagline = "sidebar.tagline"
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
        case documentFindClose = "document.find.close"
        case welcomeTitle = "welcome.title"
        case welcomeSubtitle = "welcome.subtitle"
        case welcomeLocalRendering = "welcome.localRendering"
        case welcomeRename = "welcome.rename"
        case welcomeSplitReading = "welcome.splitReading"
        case toolbarReloadHelp = "toolbar.reloadHelp"
        case toolbarOpenSplitHelp = "toolbar.openSplitHelp"
        case toolbarCloseSplitHelp = "toolbar.closeSplitHelp"
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
        case imagePreviewTooLarge = "image.previewTooLarge"
        case imagePreviewInvalid = "image.previewInvalid"
        case webViewRecoveryTitle = "webView.recoveryTitle"
        case webViewRecoveryMessage = "webView.recoveryMessage"
        case sourceLanguagePlainText = "source.language.plainText"
        case sourceLanguageHelp = "source.language.help"
        case sourceLineJumpPlaceholder = "source.lineJump.placeholder"
        case documentFindCaseSensitive = "document.find.caseSensitive"
        case documentFindPlaceholder = "document.find.placeholder"
        case documentFindLine = "document.find.line"
        case documentFindNotFound = "document.find.notFound"
        case documentFindPrevious = "document.find.previous"
        case documentFindNext = "document.find.next"
        case documentRetryOperation = "document.retryOperation"
        case sourceNotRegularFile = "source.notRegularFile"
        case sourceFileChanged = "source.fileChanged"
        case sourcePageUnavailable = "source.pageUnavailable"
    }

    static let supportedLanguages = ["en", "zh-Hans"]

    static var htmlLanguageCode: String {
        currentLanguage.hasPrefix("zh") ? "zh-CN" : "en"
    }

    static var currentLanguage: String {
        AppLanguage.restored().resolvedLocalization
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

import AppKit
import Darwin
import SwiftUI
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var webViewSelfCheck: WebViewSelfCheck?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-check") {
            Darwin.exit(SelfCheck.run())
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--webview-self-check") {
            let check = WebViewSelfCheck()
            webViewSelfCheck = check
            check.run()
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
private final class WebViewSelfCheck: NSObject, WKNavigationDelegate {
    private enum Phase {
        case mermaid
        case frontMatter
        case html
    }

    private var webView: WKWebView?
    private var window: NSWindow?
    private var temporaryRoot: URL?
    private var isFinished = false
    private var deadline = Date.distantPast
    private var darkRerenderRequested = false
    private var phase: Phase = .mermaid

    func run() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("modu-webview-self-check-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            guard let imageData = Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII="
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try imageData.write(to: root.appendingPathComponent("preview.png"))
            temporaryRoot = root
        } catch {
            finish(success: false, message: "WKWebView 测试目录创建失败：\(error.localizedDescription)")
            return
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(
            BundledAssetSchemeHandler(),
            forURLScheme: MarkdownRenderer.bundledAssetScheme
        )
        configuration.setURLSchemeHandler(
            LocalResourceSchemeHandler(rootURL: root),
            forURLScheme: MarkdownRenderer.resourceScheme
        )

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 180), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        self.window = window

        let markdown = """
        # Mermaid 实机检查

        ```mermaid
        flowchart LR
          A[墨读] --> B[离线 Mermaid]
        ```

        ```mermaid
        this is deliberately not valid Mermaid syntax
        ```

        ```mermaid
        sequenceDiagram
          participant A as 明墨
          participant B as 暗墨
          A->>B: 主题重绘
        ```
        """

        do {
            let rendered = try MarkdownRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: root.appendingPathComponent("mermaid.md"),
                rootURL: root
            ).render(markdown, fileSize: Int64(markdown.utf8.count), modifiedAt: nil)
            deadline = Date().addingTimeInterval(12)
            webView.loadHTMLString(rendered.html, baseURL: nil)
        } catch {
            finish(success: false, message: "WKWebView 测试文档生成失败：\(error.localizedDescription)")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.finish(success: false, message: "WKWebView 离线 Mermaid 渲染超时")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if phase == .frontMatter {
            checkFrontMatterResult()
            return
        }
        if phase == .html {
            pollHTMLResult()
            return
        }
        let script = MarkdownWebView.Coordinator.mermaidRenderingScript(isDark: false)
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.finish(success: false, message: "WKWebView Mermaid 启动失败：\(error.localizedDescription)")
                return
            }
            self?.pollMermaidResult()
        }
    }

    private func pollMermaidResult() {
        guard let webView, !isFinished else { return }
        let probe = """
        (() => ({
          readyCount: document.querySelectorAll('.mermaid-diagram.is-ready svg').length,
          failedCount: document.querySelectorAll('.mermaid-diagram.is-error').length,
          generation: window.__moduMermaidGeneration || 0,
          failedStatus: document.querySelector('.mermaid-diagram.is-error .mermaid-status')?.textContent || '',
          detail: document.querySelector('.mermaid-error-detail')?.textContent || ''
        }))()
        """
        webView.evaluateJavaScript(probe) { [weak self] value, error in
            guard let self, !self.isFinished else { return }
            if let error {
                self.finish(success: false, message: "WKWebView Mermaid 检查失败：\(error.localizedDescription)")
                return
            }
            let result = value as? [String: Any]
            let readyCount = result?["readyCount"] as? Int ?? 0
            let failedCount = result?["failedCount"] as? Int ?? 0
            let generation = result?["generation"] as? Int ?? 0
            if readyCount == 2, failedCount == 1 {
                guard result?["failedStatus"] as? String == L10n.string(.mermaidUnable) else {
                    self.finish(success: false, message: "WKWebView Mermaid 状态文字未跟随应用语言")
                    return
                }
                if self.darkRerenderRequested, generation >= 2 {
                    self.startFrontMatterCheck()
                    return
                }
                self.darkRerenderRequested = true
                let darkScript = MarkdownWebView.Coordinator.mermaidRenderingScript(isDark: true)
                webView.evaluateJavaScript(darkScript) { [weak self] _, error in
                    if let error {
                        self?.finish(success: false, message: "WKWebView Mermaid 暗色重绘失败：\(error.localizedDescription)")
                    } else {
                        self?.pollMermaidResult()
                    }
                }
                return
            }
            guard Date() < self.deadline else {
                let detail = result?["detail"] as? String ?? "未知错误"
                self.finish(
                    success: false,
                    message: "WKWebView Mermaid 验证超时：完成 \(readyCount) 张，失败 \(failedCount) 张；\(detail)"
                )
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.pollMermaidResult()
            }
        }
    }

    private func startFrontMatterCheck() {
        guard let webView, let root = temporaryRoot, !isFinished else { return }
        let markdown = """
        ---
        name: webview-check
        description: 这是一段需要在收起状态限制为两行、展开后恢复完整高度的长元数据内容，用来验证 WebKit 中的折叠交互、首屏空间控制以及完整内容展示不会互相冲突。
        owner: 墨读
        category: reader
        version: 1.0
        license: internal
        ---
        # Metadata 实机检查
        """
        do {
            let rendered = try MarkdownRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: root.appendingPathComponent("SKILL.md"),
                rootURL: root
            ).render(markdown, fileSize: Int64(markdown.utf8.count), modifiedAt: nil)
            phase = .frontMatter
            deadline = Date().addingTimeInterval(8)
            webView.loadHTMLString(rendered.html, baseURL: nil)
        } catch {
            finish(success: false, message: "WKWebView metadata 测试文档生成失败：\(error.localizedDescription)")
        }
    }

    private func checkFrontMatterResult() {
        guard let webView, !isFinished else { return }
        let probe = """
        (() => {
          const details = document.querySelector('.front-matter-more');
          const previewValue = document.querySelector('.front-matter-preview .front-matter-row:nth-child(2) dd');
          const remainder = document.querySelector('.front-matter-remainder');
          const initiallyClosed = Boolean(details && !details.open);
          const collapsedHeight = previewValue?.getBoundingClientRect().height || 0;
          const initiallyClamped = Boolean(previewValue && previewValue.scrollHeight > previewValue.clientHeight);
          if (details) details.open = true;
          const expandedHeight = previewValue?.getBoundingClientRect().height || 0;
          const remainderVisible = Boolean(remainder && remainder.getBoundingClientRect().height > 0);
          const collapseLabelVisible = getComputedStyle(document.querySelector('.front-matter-collapse')).display !== 'none';
          if (details) details.open = false;
          return {
            htmlLanguage: document.documentElement.lang,
            metadataTitle: document.querySelector('.front-matter-title')?.textContent || '',
            expandLabel: document.querySelector('.front-matter-expand')?.textContent || '',
            rowCount: document.querySelectorAll('.front-matter-row').length,
            initiallyClosed,
            initiallyClamped,
            expanded: expandedHeight > collapsedHeight,
            remainderVisible,
            collapseLabelVisible,
            closedAgain: Boolean(details && !details.open)
          };
        })()
        """
        webView.evaluateJavaScript(probe) { [weak self] value, error in
            guard let self, !self.isFinished else { return }
            if let error {
                self.finish(success: false, message: "WKWebView metadata 检查失败：\(error.localizedDescription)")
                return
            }
            let result = value as? [String: Any]
            let passed = result?["htmlLanguage"] as? String == L10n.htmlLanguageCode &&
                result?["metadataTitle"] as? String == L10n.string(.metadataTitle) &&
                result?["expandLabel"] as? String == L10n.format(.metadataExpandRemaining, 2) &&
                result?["rowCount"] as? Int == 6 &&
                result?["initiallyClosed"] as? Bool == true &&
                result?["initiallyClamped"] as? Bool == true &&
                result?["expanded"] as? Bool == true &&
                result?["remainderVisible"] as? Bool == true &&
                result?["collapseLabelVisible"] as? Bool == true &&
                result?["closedAgain"] as? Bool == true
            guard passed else {
                self.finish(success: false, message: "WKWebView metadata 展开/收起状态不符合预期：\(String(describing: result))")
                return
            }
            self.startHTMLCheck()
        }
    }

    private func startHTMLCheck() {
        guard let webView, let root = temporaryRoot, !isFinished else { return }
        let htmlSource = """
        <!doctype html>
        <html>
        <head><style>.card { border-top: 3px solid rgb(1, 2, 3); }</style></head>
        <body>
          <h1>HTML 实机检查</h1>
          <div class="card">静态页面</div>
          <img id="local-image" src="./preview.png" alt="本地图片">
          <script>window.moduUnsafeScriptExecuted = true</script>
        </body>
        </html>
        """
        do {
            let rendered = try HTMLDocumentRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: root.appendingPathComponent("preview.html"),
                rootURL: root
            ).render(htmlSource, fileSize: Int64(htmlSource.utf8.count), modifiedAt: nil)
            phase = .html
            deadline = Date().addingTimeInterval(8)
            webView.loadHTMLString(rendered.html, baseURL: nil)
        } catch {
            finish(success: false, message: "WKWebView HTML 测试文档生成失败：\(error.localizedDescription)")
        }
    }

    private func pollHTMLResult() {
        guard let webView, !isFinished else { return }
        let probe = """
        (() => {
          const image = document.getElementById('local-image');
          const card = document.querySelector('.card');
          return {
            heading: document.querySelector('h1')?.textContent || '',
            imageReady: Boolean(image?.complete && image?.naturalWidth > 0),
            scriptBlocked: window.moduUnsafeScriptExecuted !== true,
            cardBorder: card ? getComputedStyle(card).borderTopWidth : '',
            htmlLanguage: document.documentElement.lang
          };
        })()
        """
        webView.evaluateJavaScript(probe) { [weak self] value, error in
            guard let self, !self.isFinished else { return }
            if let error {
                self.finish(success: false, message: "WKWebView HTML 检查失败：\(error.localizedDescription)")
                return
            }
            let result = value as? [String: Any]
            let heading = result?["heading"] as? String
            let imageReady = result?["imageReady"] as? Bool ?? false
            let scriptBlocked = result?["scriptBlocked"] as? Bool ?? false
            let cardBorder = result?["cardBorder"] as? String
            let htmlLanguage = result?["htmlLanguage"] as? String
            if
                heading == "HTML 实机检查",
                imageReady,
                scriptBlocked,
                cardBorder == "3px",
                htmlLanguage == L10n.htmlLanguageCode
            {
                self.finish(
                    success: true,
                    message: "WKWebView 已验证离线 Mermaid、metadata 折叠交互与安全 HTML 预览"
                )
                return
            }
            guard Date() < self.deadline else {
                self.finish(
                    success: false,
                    message: "WKWebView HTML 验证超时：标题=\(heading ?? "空")，图片=\(imageReady)，脚本阻止=\(scriptBlocked)，样式=\(cardBorder ?? "空")"
                )
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.pollHTMLResult()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(success: false, message: "WKWebView 加载失败：\(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(success: false, message: "WKWebView 启动失败：\(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(success: false, message: "WKWebView 内容进程意外终止")
    }

    private func finish(success: Bool, message: String) {
        guard !isFinished else { return }
        isFinished = true
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
            self.temporaryRoot = nil
        }
        print("\(success ? "✓" : "✗") \(message)")
        Darwin.exit(success ? 0 : 1)
    }
}

@main
struct MoDuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ReaderViewModel()

    var body: some Scene {
        WindowGroup(L10n.string(.appName)) {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(model.appAppearance.preferredColorScheme)
                .frame(minWidth: 1160, minHeight: 620)
        }
        .defaultSize(width: 1440, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.string(.commandOpenFolder)) {
                    model.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: .command)

                if !model.recentWorkspaces.isEmpty {
                    Menu(L10n.string(.commandOpenRecent)) {
                        ForEach(model.recentWorkspaces) { workspace in
                            Button(workspace.name) {
                                model.openRecentWorkspace(workspace)
                            }
                            .help(workspace.displayPath)
                            .disabled(workspace.id == model.rootURL?.standardizedFileURL.path)
                        }

                        Divider()

                        Button(L10n.string(.commandClearMenu)) {
                            model.clearRecentWorkspaces()
                        }
                    }
                }
            }

            CommandMenu(L10n.string(.commandReading)) {
                Button(L10n.string(.commandReloadDocumentOutline)) {
                    model.reloadActiveDocument()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.canReloadActiveDocument)

                Button(L10n.string(.commandReloadDirectory)) {
                    model.rescanWorkspace()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(model.rootURL == nil)

                Divider()

                Menu(L10n.string(.commandTheme)) {
                    ForEach(MarkdownStyle.allCases) { style in
                        Button(style.name) {
                            model.selectMarkdownStyle(style)
                        }
                    }
                }

                Menu(L10n.string(.commandDisplayMode)) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Button(appearance.name) {
                            model.selectAppAppearance(appearance)
                        }
                    }
                }

                Divider()

                Button(L10n.string(model.hasSecondPane
                    ? .commandCloseActivePane
                    : .commandOpenSecondPane)) {
                    model.toggleSplitReading()
                }
                .keyboardShortcut("\\", modifiers: .command)

                Divider()

                Button(L10n.string(model.outlineIsVisible ? .outlineHide : .outlineShow)) {
                    model.outlineIsVisible.toggle()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }
    }
}

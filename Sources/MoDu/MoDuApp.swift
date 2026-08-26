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
        let cssSource = """
        html, body { height: 100%; margin: 0; background: rgb(2, 6, 15); }
        .viewport { position: fixed; inset: 0; display: flex; overflow: hidden; }
        .slide { position: absolute; display: none; width: 640px; height: 360px; }
        .slide.active { display: block; }
        .card { border-top: 3px solid rgb(1, 2, 3); }
        """
        let scriptSource = """
        (() => {
          const slides = Array.from(document.querySelectorAll('.slide'));
          const show = index => slides.forEach((slide, itemIndex) => {
            slide.classList.toggle('active', itemIndex === index);
          });
          document.getElementById('next').addEventListener('click', () => show(1));
          window.moduPrototypeShow = show;
          show(0);
          window.moduPrototypeScriptExecuted = true;
        })();
        """
        let htmlSource = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <link rel="stylesheet" href="../shared/prototype.css">
        </head>
        <body>
          <div id="viewport" class="viewport">
            <section id="slide-one" class="slide">
              <h1>HTML 实机检查</h1>
              <div class="card">静态页面</div>
              <img id="local-image" src="../shared/preview.png" alt="本地图片">
            </section>
            <section id="slide-two" class="slide">
              <h2>第二页</h2>
            </section>
          </div>
          <button id="next" type="button">下一页</button>
          <script src="../shared/prototype.js"></script>
        </body>
        </html>
        """
        do {
            let prototypeDirectory = root.appendingPathComponent("prototype", isDirectory: true)
            let sharedDirectory = root.appendingPathComponent("shared", isDirectory: true)
            try FileManager.default.createDirectory(at: prototypeDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
            let htmlURL = prototypeDirectory.appendingPathComponent("preview.html")
            try cssSource.write(
                to: sharedDirectory.appendingPathComponent("prototype.css"),
                atomically: true,
                encoding: .utf8
            )
            try scriptSource.write(
                to: sharedDirectory.appendingPathComponent("prototype.js"),
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.copyItem(
                at: root.appendingPathComponent("preview.png"),
                to: sharedDirectory.appendingPathComponent("preview.png")
            )
            try htmlSource.write(to: htmlURL, atomically: true, encoding: .utf8)
            phase = .html
            deadline = Date().addingTimeInterval(8)
            webView.loadFileURL(htmlURL, allowingReadAccessTo: root)
        } catch {
            finish(success: false, message: "WKWebView HTML 原型测试文件生成失败：\(error.localizedDescription)")
        }
    }

    private func pollHTMLResult() {
        guard let webView, !isFinished else { return }
        let probe = """
        (() => {
          const image = document.getElementById('local-image');
          const card = document.querySelector('.card');
          const slides = Array.from(document.querySelectorAll('.slide'));
          window.moduPrototypeShow?.(0);
          const initialSlideVisible = slides.length === 2 &&
            slides[0].classList.contains('active') &&
            !slides[1].classList.contains('active');
          document.getElementById('next')?.click();
          return {
            heading: document.querySelector('h1')?.textContent || '',
            imageReady: Boolean(image?.complete && image?.naturalWidth > 0),
            scriptExecuted: window.moduPrototypeScriptExecuted === true,
            cardBorder: card ? getComputedStyle(card).borderTopWidth : '',
            htmlLanguage: document.documentElement.lang,
            initialSlideVisible,
            nextSlideVisible: slides.length === 2 &&
              !slides[0].classList.contains('active') &&
              slides[1].classList.contains('active'),
            fileProtocol: location.protocol
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
            let scriptExecuted = result?["scriptExecuted"] as? Bool ?? false
            let cardBorder = result?["cardBorder"] as? String
            let htmlLanguage = result?["htmlLanguage"] as? String
            let initialSlideVisible = result?["initialSlideVisible"] as? Bool ?? false
            let nextSlideVisible = result?["nextSlideVisible"] as? Bool ?? false
            let fileProtocol = result?["fileProtocol"] as? String
            if
                heading == "HTML 实机检查",
                imageReady,
                scriptExecuted,
                cardBorder == "3px",
                htmlLanguage == "zh-CN",
                initialSlideVisible,
                nextSlideVisible,
                fileProtocol == "file:"
            {
                self.finish(
                    success: true,
                    message: "WKWebView 已验证离线 Mermaid、metadata 折叠交互与完整本地 HTML 原型"
                )
                return
            }
            guard Date() < self.deadline else {
                self.finish(
                    success: false,
                    message: "WKWebView HTML 验证超时：标题=\(heading ?? "空")，图片=\(imageReady)，脚本=\(scriptExecuted)，样式=\(cardBorder ?? "空")，初始页=\(initialSlideVisible)，交互翻页=\(nextSlideVisible)，协议=\(fileProtocol ?? "空")"
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

import AppKit
import Darwin
import WebKit

@MainActor
final class WebViewSelfCheck: NSObject, WKNavigationDelegate {
    private enum Phase {
        case mermaid
        case frontMatter
        case source
        case image
        case html
    }

    private var webView: WKWebView?
    private var window: NSWindow?
    private var temporaryRoot: URL?
    private var isFinished = false
    private var deadline = Date.distantPast
    private var timeoutGeneration = UUID()
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
            forURLScheme: LocalDocumentResourcePolicy.bundledAssetScheme
        )
        configuration.setURLSchemeHandler(
            LocalResourceSchemeHandler(rootURL: root),
            forURLScheme: LocalDocumentResourcePolicy.resourceScheme
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
            resetPhaseTimeout(
                after: 12,
                message: "WKWebView 离线 Mermaid 渲染超时"
            )
            webView.loadHTMLString(rendered.html, baseURL: nil)
        } catch {
            finish(success: false, message: "WKWebView 测试文档生成失败：\(error.localizedDescription)")
            return
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
        if phase == .source {
            checkSourceResult()
            return
        }
        if phase == .image {
            checkImageResult()
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
            resetPhaseTimeout(after: 8, message: "WKWebView metadata 验证超时")
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
            let configuration = WKFindConfiguration()
            configuration.wraps = true
            webView.find("Metadata 实机检查", configuration: configuration) { [weak self] findResult in
                guard findResult.matchFound else {
                    self?.finish(success: false, message: "WKWebView Markdown 文档内查找未找到预期内容")
                    return
                }
                self?.startSourceCheck()
            }
        }
    }

    private func startSourceCheck() {
        guard let webView, let root = temporaryRoot, !isFinished else { return }
        let source = """
        struct Preview {
            let highlighted = true
        }
        """
        let page = SourcePage(
            index: 0,
            text: source,
            startOffset: 0,
            endOffset: UInt64(source.utf8.count),
            startLine: 1,
            endLine: 3,
            leadingContinuation: false,
            trailingContinuation: false,
            hasPrevious: false,
            hasNext: true
        )
        do {
            let rendered = try SourceDocumentRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: root.appendingPathComponent("Preview.swift")
            ).render(
                page: page,
                language: .swift,
                inferredLanguage: .swift,
                fileSize: Int64(source.utf8.count),
                modifiedAt: nil
            )
            phase = .source
            resetPhaseTimeout(after: 8, message: "WKWebView 源码验证超时")
            webView.loadHTMLString(rendered.html, baseURL: nil)
        } catch {
            finish(success: false, message: "WKWebView 源码测试文档生成失败：\(error.localizedDescription)")
        }
    }

    private func checkSourceResult() {
        guard let webView, !isFinished else { return }
        webView.evaluateJavaScript(MarkdownWebView.Coordinator.sourceHighlightingScript(
            selection: nil,
            pageIndex: nil
        )) {
            [weak self] _, error in
            guard let self, !self.isFinished else { return }
            if let error {
                self.finish(success: false, message: "WKWebView 源码高亮启动失败：\(error.localizedDescription)")
                return
            }
            let probe = """
            (() => ({
              highlighted: document.getElementById('source-code-0')?.classList.contains('hljs') === true,
              keyword: document.querySelector('#source-code-0 .hljs-keyword')?.textContent || '',
              language: document.getElementById('source-code-0')?.classList.contains('language-swift') === true
            }))()
            """
            webView.evaluateJavaScript(probe) { [weak self] value, probeError in
                guard let self, !self.isFinished else { return }
                if let probeError {
                    self.finish(success: false, message: "WKWebView 源码高亮检查失败：\(probeError.localizedDescription)")
                    return
                }
                let result = value as? [String: Any]
                guard
                    result?["highlighted"] as? Bool == true,
                    result?["language"] as? Bool == true,
                    !(result?["keyword"] as? String ?? "").isEmpty
                else {
                    self.finish(success: false, message: "WKWebView 源码高亮结果不符合预期：\(String(describing: result))")
                    return
                }
                self.checkSourceContinuousViewport()
            }
        }
    }

    private func checkSourceContinuousViewport() {
        guard let webView, !isFinished else { return }
        webView.evaluateJavaScript(MarkdownWebView.Coordinator.sourceViewportTrackingScript) {
            [weak self] _, error in
            guard let self, !self.isFinished else { return }
            if let error {
                self.finish(success: false, message: "WKWebView 源码连续滚动监听启动失败：\(error.localizedDescription)")
                return
            }
            let text = "let appended = true\nlet lineFive = 5"
            let page = SourcePage(
                index: 1,
                text: text,
                startOffset: 64,
                endOffset: 64 + UInt64(text.utf8.count),
                startLine: 4,
                endLine: 5,
                leadingContinuation: false,
                trailingContinuation: false,
                hasPrevious: true,
                hasNext: true
            )
            let update = SourceViewportUpdate(
                action: .append,
                page: page,
                language: .swift,
                selectedRange: nil,
                targetLine: nil
            )
            guard let script = MarkdownWebView.Coordinator.sourceViewportUpdateScript(update) else {
                self.finish(success: false, message: "WKWebView 源码连续滚动更新生成失败")
                return
            }
            webView.evaluateJavaScript(script) { [weak self] _, updateError in
                guard let self, !self.isFinished else { return }
                if let updateError {
                    self.finish(success: false, message: "WKWebView 源码连续滚动追加失败：\(updateError.localizedDescription)")
                    return
                }
                let probe = """
                (() => ({
                  segmentCount: document.querySelectorAll('.source-segment').length,
                  appendedHighlighted: document.getElementById('source-code-1')?.classList.contains('hljs') === true,
                  lastLine: document.querySelector('.source-segment[data-page-index="1"] .source-line-numbers')?.textContent.trim().split('\\n').at(-1) || '',
                  viewportInstalled: Boolean(window.__moduSourceViewport)
                }))()
                """
                webView.evaluateJavaScript(probe) { [weak self] value, probeError in
                    guard let self, !self.isFinished else { return }
                    if let probeError {
                        self.finish(success: false, message: "WKWebView 源码连续滚动检查失败：\(probeError.localizedDescription)")
                        return
                    }
                    let result = value as? [String: Any]
                    guard
                        result?["segmentCount"] as? Int == 2,
                        result?["appendedHighlighted"] as? Bool == true,
                        result?["lastLine"] as? String == "5",
                        result?["viewportInstalled"] as? Bool == true
                    else {
                        self.finish(success: false, message: "WKWebView 源码连续滚动结果不符合预期：\(String(describing: result))")
                        return
                    }
                    self.appendSourceViewportCheckPage(2)
                }
            }
        }
    }

    private func appendSourceViewportCheckPage(_ pageIndex: Int) {
        guard let webView, !isFinished else { return }
        let startLine = pageIndex * 2 + 2
        let text = "let page\(pageIndex) = \(pageIndex)\nlet page\(pageIndex)End = true"
        let page = SourcePage(
            index: pageIndex,
            text: text,
            startOffset: UInt64(pageIndex * 128),
            endOffset: UInt64(pageIndex * 128 + text.utf8.count),
            startLine: startLine,
            endLine: startLine + 1,
            leadingContinuation: false,
            trailingContinuation: false,
            hasPrevious: true,
            hasNext: pageIndex < 3
        )
        let update = SourceViewportUpdate(
            action: .append,
            page: page,
            language: .swift,
            selectedRange: nil,
            targetLine: nil
        )
        guard let script = MarkdownWebView.Coordinator.sourceViewportUpdateScript(update) else {
            finish(success: false, message: "WKWebView 源码滑动窗口更新生成失败")
            return
        }
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self, !self.isFinished else { return }
            if let error {
                self.finish(success: false, message: "WKWebView 源码滑动窗口追加失败：\(error.localizedDescription)")
                return
            }
            if pageIndex < 3 {
                self.appendSourceViewportCheckPage(pageIndex + 1)
                return
            }
            let probe = """
            (() => {
              const segments = Array.from(document.querySelectorAll('.source-segment'));
              return {
                count: segments.length,
                first: segments[0]?.dataset.pageIndex || '',
                last: segments.at(-1)?.dataset.pageIndex || '',
                allHighlighted: segments.every(segment => segment.querySelector('code')?.classList.contains('hljs'))
              };
            })()
            """
            webView.evaluateJavaScript(probe) { [weak self] value, probeError in
                guard let self, !self.isFinished else { return }
                let result = value as? [String: Any]
                guard
                    probeError == nil,
                    result?["count"] as? Int == 3,
                    result?["first"] as? String == "1",
                    result?["last"] as? String == "3",
                    result?["allHighlighted"] as? Bool == true
                else {
                    self.finish(success: false, message: "WKWebView 源码滑动窗口限制不符合预期：\(String(describing: result))")
                    return
                }
                self.startImageCheck()
            }
        }
    }

    private func startImageCheck() {
        guard let webView, let root = temporaryRoot, !isFinished else { return }
        do {
            let rendered = try ImageDocumentRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: root.appendingPathComponent("preview.png"),
                rootURL: root
            ).render()
            phase = .image
            resetPhaseTimeout(after: 8, message: "WKWebView 图片预览验证超时")
            webView.loadHTMLString(rendered.html, baseURL: nil)
        } catch {
            finish(success: false, message: "WKWebView 图片测试文档生成失败：\(error.localizedDescription)")
        }
    }

    private func checkImageResult() {
        guard let webView, !isFinished else { return }
        let probe = """
        (() => {
          const image = document.querySelector('.image-document img');
          return {
            ready: Boolean(image?.complete && image?.naturalWidth > 0),
            protocol: image?.src ? new URL(image.src).protocol : '',
            scriptCount: document.scripts.length
          };
        })()
        """
        webView.evaluateJavaScript(probe) { [weak self] value, error in
            guard let self, !self.isFinished else { return }
            if let error {
                self.finish(success: false, message: "WKWebView 图片预览检查失败：\(error.localizedDescription)")
                return
            }
            let result = value as? [String: Any]
            if
                result?["ready"] as? Bool == true,
                result?["protocol"] as? String == "modu-resource:",
                result?["scriptCount"] as? Int == 0
            {
                self.startHTMLCheck()
                return
            }
            guard Date() < self.deadline else {
                self.finish(success: false, message: "WKWebView 图片预览验证超时：\(String(describing: result))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.checkImageResult()
            }
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
            guard let baseURL = LocalResourceSchemeHandler.resourceURL(for: htmlURL, inside: root) else {
                finish(success: false, message: "WKWebView HTML 原型资源基址生成失败")
                return
            }
            phase = .html
            resetPhaseTimeout(after: 8, message: "WKWebView HTML 原型验证超时")
            webView.loadHTMLString(htmlSource, baseURL: baseURL)
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
                fileProtocol == "\(LocalDocumentResourcePolicy.resourceScheme):"
            {
                let configuration = WKFindConfiguration()
                configuration.wraps = true
                webView.find("第二页", configuration: configuration) { [weak self] findResult in
                    guard findResult.matchFound else {
                        self?.finish(success: false, message: "WKWebView HTML 文档内查找未找到预期内容")
                        return
                    }
                    self?.finish(
                        success: true,
                        message: "WKWebView 已验证离线 Mermaid、源码连续滚动与高亮、图片预览、通用文档查找、metadata 折叠交互与完整本地 HTML 原型"
                    )
                }
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

    private func resetPhaseTimeout(after seconds: TimeInterval, message: String) {
        deadline = Date().addingTimeInterval(seconds)
        let generation = UUID()
        timeoutGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard
                let self,
                !self.isFinished,
                self.timeoutGeneration == generation
            else { return }
            self.finish(success: false, message: message)
        }
    }

    private func finish(success: Bool, message: String) {
        guard !isFinished else { return }
        isFinished = true
        timeoutGeneration = UUID()
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
            self.temporaryRoot = nil
        }
        print("\(success ? "✓" : "✗") \(message)")
        Darwin.exit(success ? 0 : 1)
    }
}

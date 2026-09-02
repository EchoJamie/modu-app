// Debug-only deterministic checks live outside production service boundaries.
import Foundation
import Darwin

#if DEBUG
@MainActor
enum SelfCheck {
    static func run() -> Int32 {
        var failures: [String] = []

        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if condition() {
                print("✓ \(message)")
            } else {
                print("✗ \(message)")
                failures.append(message)
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("modu-self-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let markdown = """
            ---
            name: sample-skill
            description: >-
              用于验证紧凑、对齐并且可以安全折叠的
              多行文档元数据。
            version: "1.0"
            author: 墨读
            category: reader
            unsafe: <script>alert('metadata')</script>
            ---

            # 标题

            一段 **粗体**、`代码` 和 <不可信内容>。

            ## 表格

            | 项目 | 状态 |
            | --- | --- |
            | 目录树 | 完成 |

            ### 宽表格

            | 一 | 二 | 三 | 四 | 五 | 六 |
            | --- | --- | --- | --- | --- | --- |
            | A | B | C | D | E | 最后一列保留可读宽度 |

            - [x] 只读

            [普通链接](https://example.com) 与 [`代码链接`](https://example.com/code)。

            ```swift
            let ready = true
            ```

            ```mermaid
            flowchart LR
              A[安全输入] --> B[离线渲染]
            ```

            ![远程图片](https://example.com/tracker.png)

            <script src="https://example.com/leak.js"></script>
            """
            let resolvedThemes = MarkdownStyle.allCases.flatMap { style in
                [
                    ResolvedReaderTheme(style: style, isDark: false),
                    ResolvedReaderTheme(style: style, isDark: true)
                ]
            }
            let renderedDocuments = try resolvedThemes.map { style in
                try MarkdownRenderer(
                    style: style,
                    documentURL: root.appendingPathComponent("sample.md"),
                    rootURL: root
                ).render(markdown, fileSize: Int64(markdown.utf8.count), modifiedAt: nil)
            }
            let rendered = renderedDocuments[0]

            let missingLocalizations = L10n.supportedLanguages.flatMap { language in
                L10n.Key.allCases.compactMap { key in
                    let value = L10n.string(key, language: language)
                    return value.isEmpty || value == key.rawValue ? "\(language):\(key.rawValue)" : nil
                }
            }
            check(missingLocalizations.isEmpty, "英文与简体中文本地化键完整")
            check(
                L10n.string(.appName, language: "en") == "MoDu" &&
                    L10n.string(.appName, language: "zh-Hans") == "墨读",
                "应用名称可按语言显示为 MoDu 或墨读"
            )
            check(
                L10n.string(.sidebarTagline, language: "en") == "Answers live between the lines." &&
                    L10n.string(.sidebarTagline, language: "zh-Hans") == "字里行间，自有答案",
                "侧栏品牌文案保留中英文对应意境"
            )
            if
                let languageIndex = CommandLine.arguments.firstIndex(of: "-AppleLanguages"),
                CommandLine.arguments.indices.contains(languageIndex + 1)
            {
                let requestedLanguage = CommandLine.arguments[languageIndex + 1].lowercased()
                let expectedName = requestedLanguage.contains("zh") ? "墨读" : "MoDu"
                check(
                    L10n.string(.appName) == expectedName,
                    "应用名称跟随当前 macOS 应用语言"
                )
            }
            check(renderedDocuments.count == 10 && renderedDocuments.allSatisfy { !$0.html.isEmpty }, "五套主题的明墨与暗墨模式均可渲染")
            check(rendered.html.contains("<html lang=\"\(L10n.htmlLanguageCode)\">"), "Markdown 页面语言跟随应用语言")
            check(rendered.html.contains("class=\"front-matter is-collapsible\""), "文档顶部 YAML 渲染为独立的可折叠元数据区")
            check(rendered.html.contains("<dt>name</dt>") && rendered.html.contains("<dd>sample-skill</dd>"), "元数据按 key/value 语义结构对齐渲染")
            check(rendered.html.contains(L10n.format(.metadataExpandRemaining, 2)) && rendered.html.contains("<details class=\"front-matter-more\">"), "较多元数据默认只展示前四项")
            check(rendered.html.contains("多行文档元数据。"), "YAML 折叠文本合并为紧凑的元数据值")
            check(rendered.html.contains("&lt;script&gt;alert('metadata')&lt;/script&gt;"), "元数据值在进入页面前完成 HTML 转义")
            check(!rendered.html.contains("<p>name: sample-skill</p>") && !rendered.html.contains("<hr>\n<p>name:"), "YAML 分隔符与内容不再混入 Markdown 正文")
            check(rendered.outline.map(\.title) == ["标题", "表格", "宽表格"], "从同一解析结果生成大纲")
            check(rendered.outline.allSatisfy { !$0.anchor.isEmpty }, "为标题生成稳定锚点")
            check(rendered.html.contains("<table data-column-count=") && rendered.html.contains("<td>目录树</td>"), "表格使用真实 HTML 单元格")
            check(rendered.html.contains("class=\"table-wrap\"><table data-column-count=\"2\""), "普通表格保持正文栏宽度")
            check(rendered.html.contains("class=\"table-wrap is-wide\"><table data-column-count=\"6\""), "多列表格启用宽阅读区布局")
            check(MarkdownRenderer.shouldUseWideTable(columnCount: 4, contentLength: 200), "四列长内容表格也启用宽阅读区布局")
            check(!MarkdownRenderer.shouldUseWideTable(columnCount: 4, contentLength: 80), "四列短内容表格不被无条件撑宽")
            check(
                rendered.html.contains("width: min(1800px, calc(100vw - 72px))") &&
                    rendered.html.contains("min-width: 68rem") &&
                    rendered.html.contains("min-width: 18rem"),
                "宽表格优先利用阅读区宽度并保持可读列宽"
            )
            check(!rendered.html.contains("::selection"), "跨行文本选择不再给整块元素绘制选择背景")
            check(rendered.html.contains("type=\"checkbox\" disabled checked"), "渲染任务列表")
            check(rendered.html.contains("<pre data-language=\"swift\"><code"), "代码块保留语言结构")
            check(rendered.html.contains("class=\"mermaid-diagram is-rendering\""), "Mermaid fenced code block 生成独立图表容器")
            check(rendered.html.contains("data-mermaid-renderable=\"true\""), "Mermaid 图表进入离线渲染队列")
            check(rendered.html.contains("flowchart LR") && rendered.html.contains(L10n.string(.mermaidSourceSummary)), "Mermaid 图表保留安全转义的本地回退内容")
            check(rendered.html.contains("width: min(1600px, calc(100vw - 72px))"), "Mermaid 图表优先利用阅读区宽度")
            check(!rendered.html.contains("data-language=\"mermaid\""), "Mermaid fenced code block 不按普通代码块展示")
            check(rendered.html.contains("a code { padding: 0; background: none"), "链接内代码不叠加背景")
            check(rendered.html.contains("<img src=\"https://example.com/tracker.png\" alt=\"远程图片\" loading=\"lazy\" referrerpolicy=\"no-referrer\">"), "HTTP/HTTPS 远程图片进入页面资源")
            check(!rendered.html.contains(L10n.format(.imageWithAlt, "远程图片")), "HTTP/HTTPS 远程图片不再显示占位说明")
            check(!rendered.html.contains("<script src=\"https://example.com/leak.js\""), "原始 HTML 不会直接执行")
            check(rendered.html.contains("&lt;script src="), "原始 HTML 以文本方式展示")
            check(rendered.html.contains("img-src data: modu-resource: http: https:"), "页面内容安全策略仅为图片放开 HTTP/HTTPS")
            check(rendered.html.contains("script-src modu-asset:"), "页面内容安全策略只允许离线应用脚本")
            check(rendered.html.contains("<script src=\"\(LocalDocumentResourcePolicy.mermaidScriptURL)\"></script>"), "页面仅加载固定版本 Mermaid 离线资源")
            check(!rendered.html.contains("cdn.") && !rendered.html.contains("unpkg.com"), "Mermaid 页面不依赖 CDN")
            check(rendered.html.contains("connect-src 'none'"), "页面内容安全策略禁止网络连接")
            check(rendered.html.contains("media-src 'none'"), "页面内容安全策略禁止媒体")
            check(rendered.html.contains("frame-src 'none'"), "页面内容安全策略禁止内嵌页面")
            check(rendered.html.contains("worker-src 'none'"), "页面内容安全策略禁止 Worker")

            let plainMarkdown = """
            ```swift
            let unchanged = true
            ```
            """
            let plainDocument = try MarkdownRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: root.appendingPathComponent("plain.md"),
                rootURL: root
            ).render(plainMarkdown, fileSize: Int64(plainMarkdown.utf8.count), modifiedAt: nil)
            check(plainDocument.html.contains("script-src 'none'"), "无 Mermaid 文档继续完全禁止页面脚本")
            check(!plainDocument.html.contains(LocalDocumentResourcePolicy.mermaidScriptURL), "无 Mermaid 文档不加载 Mermaid 资源")

            let compactMetadata = """
            ---
            name: xxx
            description: xxxxxxxx
            aaaaaa: bbbb
            ---
            # 正文
            """
            let compactMetadataDocument = try MarkdownRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: root.appendingPathComponent("SKILL.md"),
                rootURL: root
            ).render(compactMetadata, fileSize: Int64(compactMetadata.utf8.count), modifiedAt: nil)
            check(compactMetadataDocument.html.contains("class=\"front-matter\""), "简短 SKILL.md 元数据使用紧凑区域")
            check(!compactMetadataDocument.html.contains("<details class=\"front-matter-more\">"), "不需要折叠的短元数据不显示多余控件")

            let middleDelimiter = """
            # 正文

            ---

            后续内容
            """
            let middleDelimiterDocument = try MarkdownRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: root.appendingPathComponent("ordinary.md"),
                rootURL: root
            ).render(middleDelimiter, fileSize: Int64(middleDelimiter.utf8.count), modifiedAt: nil)
            check(!middleDelimiterDocument.html.contains("class=\"front-matter"), "只识别文件最开头的 YAML 元数据块")
            check(middleDelimiterDocument.html.contains("<hr>"), "正文中的分隔线继续按普通 Markdown 渲染")

            let lightMermaidScript = MarkdownWebView.Coordinator.mermaidRenderingScript(isDark: false)
            let darkMermaidScript = MarkdownWebView.Coordinator.mermaidRenderingScript(isDark: true)
            check(lightMermaidScript.contains("securityLevel: 'strict'"), "Mermaid 使用 strict 安全级别")
            check(lightMermaidScript.contains("suppressErrorRendering: true") && lightMermaidScript.contains("setError(diagram"), "Mermaid 错误限制在单个图表容器")
            check(lightMermaidScript.contains("darkMode: false") && darkMermaidScript.contains("darkMode: true"), "主题模式变化会重新配置 Mermaid 色彩")
            check(
                lightMermaidScript.contains("__moduMermaidPending") &&
                    lightMermaidScript.contains("__moduMermaidRunning") &&
                    !lightMermaidScript.contains("__moduMermaidQueue"),
                "连续主题变化只保留最新一轮 Mermaid 重绘请求"
            )

            let htmlSource = """
            <!doctype html>
            <html>
            <head><style>.card { border: 1px solid currentColor; }</style></head>
            <body>
              <h1>HTML 标题</h1>
              <section class="card">可视内容</section>
              <img src="./preview.png" alt="本地预览">
              <a href="./sample.md#表格">打开 Markdown</a>
              <script>window.unsafeExecuted = true</script>
            </body>
            </html>
            """
            try "# HTML link target\n".write(
                to: root.appendingPathComponent("sample.md"),
                atomically: true,
                encoding: .utf8
            )
            let renderedHTML = try HTMLDocumentRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: root.appendingPathComponent("sample.html"),
                rootURL: root
            ).render(htmlSource, fileSize: Int64(htmlSource.utf8.count), modifiedAt: nil)
            check(
                PreviewDocumentKind.resolve(fileName: "sample.html", isRegularFile: true) == .html,
                "HTML 与 HTM 文件进入可预览文档类型"
            )
            check(renderedHTML.renderingMode == .interactiveHTML, "HTML 使用保留原始 CSS 与 JavaScript 的交互网页模式")
            check(renderedHTML.html == htmlSource, "HTML 交互页持有通过大小门禁的同一份源码快照")
            check(renderedHTML.html.contains("unsafeExecuted"), "HTML 交互页保留原始脚本")
            let htmlFallback = renderedHTML.interactiveHTMLFallback ?? ""
            check(htmlFallback.contains("<h1 id=\"html-标题\">HTML 标题</h1>"), "HTML 同时生成加载失败时的静态回退内容")
            check(renderedHTML.outline.map(\.title) == ["HTML 标题"], "HTML 标题生成右侧大纲")
            check(htmlFallback.contains("modu-resource://local?"), "HTML 回退页本地图片改写为安全目录资源")
            check(htmlFallback.contains("img-src data: modu-resource: http: https:"), "HTML 回退页 CSP 允许安全本地与远程图片")
            check(htmlFallback.contains("modu-markdown://local?"), "HTML 回退页可链接工作目录内的 Markdown 或 HTML 文档")
            check(htmlFallback.contains(".card { border: 1px solid currentColor; }"), "HTML 回退页保留内联样式")
            check(!htmlFallback.contains("unsafeExecuted"), "HTML 静态回退不会执行文档自带脚本")
            check(
                htmlFallback.contains("style-src 'unsafe-inline'; script-src 'none'") &&
                    htmlFallback.contains("font-src 'none'") &&
                    !htmlFallback.contains("style-src 'unsafe-inline' http"),
                "HTML 静态回退只为图片开放远程资源，禁止脚本、远程样式与字体"
            )
            let staticHTMLCompatibilityScript = MarkdownWebView.Coordinator.staticHTMLCompatibilityScript
            check(
                staticHTMLCompatibilityScript.contains("#write.modu-html-document") &&
                    staticHTMLCompatibilityScript.contains("visibleSlides.length > 1") &&
                    staticHTMLCompatibilityScript.contains("modu-static-slide-frame") &&
                    staticHTMLCompatibilityScript.contains("window.addEventListener('pagehide', cleanup"),
                "HTML 原始文件加载失败时可安全降级为可清理的静态长页"
            )

            check(BundledAssetSchemeHandler.mermaidAssetURL != nil, "固定版本 Mermaid JavaScript 已打入 SwiftPM 资源")
            check(BundledAssetSchemeHandler.highlighterAssetURL != nil, "固定版本 Highlight.js 已打入 SwiftPM 资源")
            let originURL = Bundle.main.url(
                forResource: "ORIGIN",
                withExtension: "md",
                subdirectory: "Mermaid"
            ) ?? AppResources.bundle.url(
                forResource: "ORIGIN",
                withExtension: "md",
                subdirectory: "Mermaid"
            )
            let origin = originURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            check(
                origin?.contains("- Product: Mermaid") == true &&
                    origin?.contains("- Version: \(LocalDocumentResourcePolicy.mermaidVersion)") == true &&
                    origin?.contains("https://registry.npmjs.org/mermaid/") == true,
                "Mermaid 资源记录固定版本与来源"
            )

            let extensionlessClassificationURL = root.appendingPathComponent("extensionless")
            try "plain text\n".write(
                to: extensionlessClassificationURL,
                atomically: true,
                encoding: .utf8
            )
            let extensionlessDirectoryURL = root.appendingPathComponent("docs", isDirectory: true)
            try FileManager.default.createDirectory(
                at: extensionlessDirectoryURL,
                withIntermediateDirectories: true
            )
            let extensionlessPipeURL = root.appendingPathComponent("events")
            let pipeCreated = extensionlessPipeURL.path.withCString { path in
                Darwin.mkfifo(path, 0o600) == 0
            }
            check(
                PreviewDocumentKind.resolve(fileName: "main.SWIFT", isRegularFile: true) == .source(.swift) &&
                    PreviewDocumentKind.resolve(fileName: ".env.local", isRegularFile: true) == .source(.properties) &&
                    PreviewDocumentKind.resolve(fileName: "Dockerfile.dev", isRegularFile: true) == .source(.dockerfile) &&
                    PreviewDocumentKind.resolve(fileName: "preview.PNG", isRegularFile: true) == .image &&
                    PreviewDocumentKind.resolve(fileName: "diagram.svg", isRegularFile: true) == .image &&
                    FileSystemService.previewKind(at: extensionlessClassificationURL) == .source(.plaintext) &&
                    FileSystemService.previewKind(at: extensionlessDirectoryURL) == nil &&
                    (!pipeCreated || FileSystemService.previewKind(at: extensionlessPipeURL) == nil) &&
                    PreviewDocumentKind.resolve(fileName: "unknown.bin", isRegularFile: true) == nil,
                "代码、配置、特殊文件名及真实无后缀文件使用确定分类，目录与管道不会误判为源码"
            )
            check(
                !DocumentSearchState().isPresented &&
                    !SourceLineJumpState().isPresented &&
                    DocumentSearchRequest(
                        id: UUID(),
                        query: "text",
                        isCaseSensitive: false,
                        direction: .next
                    ).direction == .next,
                "通用文档查找栏与源码行号跳转默认隐藏"
            )
            check(
                MarkdownWebView.Coordinator.shouldDeferFind(
                    webViewIsLoading: true,
                    isDocumentReady: false
                ) &&
                    MarkdownWebView.Coordinator.shouldDeferFind(
                        webViewIsLoading: false,
                        isDocumentReady: false
                    ) &&
                    !MarkdownWebView.Coordinator.shouldDeferFind(
                        webViewIsLoading: false,
                        isDocumentReady: true
                    ),
                "文档或源码高亮尚未就绪时延后查找，完成后再执行"
            )

            let previewImageURL = root.appendingPathComponent("preview.png")
            guard let previewImageData = Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII="
            ) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try previewImageData.write(to: previewImageURL)
            let renderedImage = try ImageDocumentRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: previewImageURL,
                rootURL: root
            ).render()
            check(
                renderedImage.renderingMode == .image &&
                    renderedImage.html.contains("modu-resource://local?") &&
                    renderedImage.html.contains("img-src modu-resource:") &&
                    renderedImage.html.contains("connect-src 'none'") &&
                    !renderedImage.html.contains("data:image"),
                "图片预览通过工作区受限资源协议加载且不把原图嵌入 HTML"
            )
            let invalidImageURL = root.appendingPathComponent("damaged.png")
            try "not an image".write(to: invalidImageURL, atomically: true, encoding: .utf8)
            let invalidRasterRejected: Bool
            do {
                _ = try ImageDocumentRenderer(
                    style: ResolvedReaderTheme(style: .github, isDark: false),
                    documentURL: invalidImageURL,
                    rootURL: root
                ).render()
                invalidRasterRejected = false
            } catch ImageDocumentError.invalidImage {
                invalidRasterRejected = true
            } catch {
                invalidRasterRejected = false
            }
            let validSVGURL = root.appendingPathComponent("valid.svg")
            try "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"2\" height=\"2\"><rect width=\"2\" height=\"2\"/></svg>".write(
                to: validSVGURL,
                atomically: true,
                encoding: .utf8
            )
            let validSVGAccepted = (try? ImageDocumentRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: validSVGURL,
                rootURL: root
            ).render()) != nil
            check(
                invalidRasterRejected && validSVGAccepted,
                "图片进入 loaded 状态前验证实际可解码内容并保留有效 SVG 预览"
            )

            let extensionlessURL = root.appendingPathComponent("run-tool")
            try "#!/usr/bin/env -S python3 -u\nprint('ready')\n".write(
                to: extensionlessURL,
                atomically: true,
                encoding: .utf8
            )
            let extensionlessSession = try SourceFileSession(fileURL: extensionlessURL, rootURL: root)
            check(
                extensionlessSession.suggestedLanguage == .python,
                "无后缀文本可通过 shebang 推断源码高亮语言"
            )

            let sourceURL = root.appendingPathComponent("large.swift")
            let sourceLines = (1...4_500).map { line in
                if line == 1 { return "let unsafe = \"<script>alert('x')</script>\"" }
                if line == 100 || line == 4_201 { return "let searchNeedle = \"needle-\(line)\"" }
                return "let value\(line) = \(line)"
            }
            try sourceLines.joined(separator: "\n").write(to: sourceURL, atomically: true, encoding: .utf8)
            let sourceSession = try SourceFileSession(fileURL: sourceURL, rootURL: root)
            let firstSourcePage = try sourceSession.page(at: 0)
            let secondSourcePage = try sourceSession.page(at: 1)
            let thirdSourcePage = try sourceSession.page(at: 2)
            let lineJumpPage = try sourceSession.page(containingLine: 4_201)
            let missingLineJumpPage = try sourceSession.page(containingLine: 9_999)
            check(
                firstSourcePage.startLine == 1 && firstSourcePage.endLine == 2_000 &&
                    secondSourcePage.startLine == 2_001 && secondSourcePage.endLine == 4_000 &&
                    thirdSourcePage.startLine == 4_001 && !thirdSourcePage.hasNext,
                "源码按行与字节边界分段且不受文件总大小上限限制"
            )
            check(
                lineJumpPage?.index == 2 && lineJumpPage?.startLine == 4_001 &&
                    missingLineJumpPage == nil,
                "源码可按行号定位所属分段并拒绝越界行号"
            )
            check(
                firstSourcePage.text.utf8.count <= SourceFileSession.maximumPageBytes &&
                    secondSourcePage.text.utf8.count <= SourceFileSession.maximumPageBytes,
                "源码读取会话限制单段驻留内容而不是拒绝大文件"
            )

            let bareCRURL = root.appendingPathComponent("bare-cr.txt")
            let bareCRSource = (1...3_001).map { "line\($0)" }.joined(separator: "\r")
            try bareCRSource.write(to: bareCRURL, atomically: true, encoding: .utf8)
            let bareCRSession = try SourceFileSession(fileURL: bareCRURL, rootURL: root)
            let bareCRFirstPage = try bareCRSession.page(at: 0)
            let bareCRSecondPage = try bareCRSession.page(at: 1)
            check(
                bareCRFirstPage.startLine == 1 && bareCRFirstPage.endLine == 2_000 &&
                    bareCRSecondPage.startLine == 2_001 &&
                    !bareCRFirstPage.text.contains("\r"),
                "裸 CR 与 LF 一样参与源码分行并受每页最大行数限制"
            )

            let splitCRLFURL = root.appendingPathComponent("split-crlf.txt")
            let splitCRLFSource = String(
                repeating: "x",
                count: SourceFileSession.maximumPageBytes - 1
            ) + "\r\nnext"
            try splitCRLFSource.write(to: splitCRLFURL, atomically: true, encoding: .utf8)
            let splitCRLFSession = try SourceFileSession(fileURL: splitCRLFURL, rootURL: root)
            let splitCRLFFirstPage = try splitCRLFSession.page(at: 0)
            let splitCRLFSecondPage = try splitCRLFSession.page(at: 1)
            check(
                splitCRLFFirstPage.endOffset == UInt64(SourceFileSession.maximumPageBytes + 1) &&
                    splitCRLFFirstPage.endLine == 1 && splitCRLFFirstPage.text.hasSuffix("\n") &&
                    splitCRLFSecondPage.startLine == 2 && splitCRLFSecondPage.text == "next",
                "跨字节硬边界的 CRLF 作为原子换行处理且不会插入空行"
            )

            let boundarySearchURL = root.appendingPathComponent("boundary-search.txt")
            let boundarySearchSource = String(
                repeating: "x",
                count: SourceFileSession.maximumPageBytes - 3
            ) + "BOUNDARY-tail"
            try boundarySearchSource.write(to: boundarySearchURL, atomically: true, encoding: .utf8)
            let boundarySearchSession = try SourceFileSession(fileURL: boundarySearchURL, rootURL: root)
            let boundaryMatch = try boundarySearchSession.find(
                "BOUNDARY",
                caseSensitive: true,
                direction: .next,
                currentPageIndex: 0,
                currentMatch: nil
            ).match
            let reverseBoundaryMatch = try boundarySearchSession.find(
                "BOUNDARY",
                caseSensitive: true,
                direction: .previous,
                currentPageIndex: 1,
                currentMatch: nil
            ).match
            check(
                boundaryMatch?.pageIndex == 0 &&
                    boundaryMatch?.range.location == SourceFileSession.maximumPageBytes - 3 &&
                    boundaryMatch?.range.length == 3 &&
                    reverseBoundaryMatch == boundaryMatch,
                "源码前后查找均可识别跨越硬分页边界的匹配并定位到起始页"
            )

            let sparseIndexURL = root.appendingPathComponent("sparse-index.txt")
            let sparsePageCount = 540
            try String(
                repeating: "x\n",
                count: sparsePageCount * SourceFileSession.maximumPageLines
            ).write(to: sparseIndexURL, atomically: true, encoding: .utf8)
            let sparseIndexSession = try SourceFileSession(fileURL: sparseIndexURL, rootURL: root)
            let sparseSearch = try sparseIndexSession.find(
                "definitely-not-present",
                caseSensitive: true,
                direction: .next,
                currentPageIndex: 0,
                currentMatch: nil
            )
            check(
                sparseSearch.match == nil &&
                    sparseIndexSession.indexedLocationCountForTesting <=
                        SourceFileSession.maximumRecentLocations + sparsePageCount / SourceFileSession.checkpointStride + 2,
                "扫描超大短行源码只保留稀疏检查点和有界近期页位置"
            )

            let firstMatch = try sourceSession.find(
                "searchNeedle",
                caseSensitive: true,
                direction: .next,
                currentPageIndex: 0,
                currentMatch: nil
            )
            let secondMatch = try sourceSession.find(
                "searchNeedle",
                caseSensitive: true,
                direction: .next,
                currentPageIndex: firstMatch.match?.pageIndex ?? 0,
                currentMatch: firstMatch.match
            )
            let previousMatch = try sourceSession.find(
                "searchNeedle",
                caseSensitive: true,
                direction: .previous,
                currentPageIndex: secondMatch.match?.pageIndex ?? 0,
                currentMatch: secondMatch.match
            )
            check(
                firstMatch.match?.line == 100 && secondMatch.match?.line == 4_201 &&
                    previousMatch.match?.line == 100,
                "文件内检索跨源码分段支持下一个与上一个匹配项"
            )

            let overrideRoot = root.appendingPathComponent("old-directory", isDirectory: true)
            let renamedOverrideRoot = root.appendingPathComponent("new-directory", isDirectory: true)
            let migratedOverrides = ReaderViewModel.migratingSourceLanguageOverrides(
                [
                    overrideRoot.appendingPathComponent("Sources/Main.txt").path: .swift,
                    overrideRoot.appendingPathComponent("Config/app.conf").path: .toml,
                    root.appendingPathComponent("unrelated.txt").path: .python
                ],
                from: overrideRoot,
                to: renamedOverrideRoot
            )
            check(
                migratedOverrides[renamedOverrideRoot.appendingPathComponent("Sources/Main.txt").path] == .swift &&
                    migratedOverrides[renamedOverrideRoot.appendingPathComponent("Config/app.conf").path] == .toml &&
                    migratedOverrides[root.appendingPathComponent("unrelated.txt").path] == .python &&
                    migratedOverrides.keys.allSatisfy { !$0.hasPrefix(overrideRoot.path + "/") },
                "重命名目录会批量迁移全部子文件的手动高亮语言覆盖"
            )

            let sourceRenderer = SourceDocumentRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: sourceURL
            )
            let renderedSource = try sourceRenderer.render(
                page: firstSourcePage,
                language: .swift,
                inferredLanguage: .swift,
                fileSize: sourceSession.fileSize,
                modifiedAt: sourceSession.modifiedAt,
                selectedRange: firstMatch.match?.range
            )
            let manuallyAdjustedSource = try sourceRenderer.render(
                page: firstSourcePage,
                language: .python,
                inferredLanguage: .swift,
                fileSize: sourceSession.fileSize,
                modifiedAt: sourceSession.modifiedAt
            )
            check(
                renderedSource.renderingMode == .sourceCode &&
                    renderedSource.html.contains("language-swift") &&
                    manuallyAdjustedSource.html.contains("language-python") &&
                    renderedSource.html.contains("id=\"source-segments\"") &&
                    renderedSource.html.contains("data-page-index=\"0\""),
                "源码语言可自动映射并按文件手动切换高亮语言"
            )
            check(
                MarkdownWebView.Coordinator.sourceViewportTrackingScript.contains("maximumSegments = 3") &&
                    MarkdownWebView.Coordinator.sourceViewportTrackingScript.contains("requestBoundary('next'") &&
                    MarkdownWebView.Coordinator.sourceViewportTrackingScript.contains("releasePrevious") &&
                    MarkdownWebView.Coordinator.sourceViewportTrackingScript.contains("releaseNext") &&
                    MarkdownWebView.Coordinator.sourceViewportTrackingScript.contains("window.scrollBy(0, -removedHeight)"),
                "源码连续滚动使用三段滑动窗口、释放失败方向并补偿移除分段的滚动偏移"
            )
            check(
                renderedSource.html.contains("min-height: 100vh") &&
                    renderedSource.html.contains("border-radius: 0") &&
                    !renderedSource.html.contains("padding: 24px 28px"),
                "源码与行号背景铺满阅读区域且不使用外层卡片"
            )
            check(
                SourceDocumentRenderer.stylesheet.contains(".hljs-title.class_") &&
                    SourceDocumentRenderer.stylesheet.contains("#9656bd") &&
                    SourceDocumentRenderer.stylesheet.contains(".hljs-title.function_") &&
                    SourceDocumentRenderer.stylesheet.contains("#278764") &&
                    SourceDocumentRenderer.stylesheet.contains(".hljs-string") &&
                    SourceDocumentRenderer.stylesheet.contains("#b56a2b") &&
                    SourceDocumentRenderer.stylesheet.contains(".hljs-number") &&
                    SourceDocumentRenderer.stylesheet.contains("#ad4e73"),
                "源码高亮为类型、方法、字符串与字面量使用可区分的语义色"
            )
            check(
                renderedSource.html.contains("&lt;script&gt;alert('x')&lt;/script&gt;") &&
                    renderedSource.html.contains("script-src modu-asset:") &&
                    renderedSource.html.contains("connect-src 'none'") &&
                    !renderedSource.html.contains("cdn."),
                "源码内容经过转义且高亮页面仅允许固定离线脚本"
            )

            let highlighterOriginURL = Bundle.main.url(
                forResource: "ORIGIN",
                withExtension: "md",
                subdirectory: "Highlighter"
            ) ?? AppResources.bundle.url(
                forResource: "ORIGIN",
                withExtension: "md",
                subdirectory: "Highlighter"
            )
            let highlighterOrigin = highlighterOriginURL.flatMap {
                try? String(contentsOf: $0, encoding: .utf8)
            }
            check(
                highlighterOrigin?.contains("- Product: Highlight.js") == true &&
                highlighterOrigin?.contains("- Version: \(LocalDocumentResourcePolicy.highlighterVersion)") == true,
                "Highlight.js 资源记录固定版本、来源、许可证与摘要"
            )

            check(FileSystemService.isIgnoredAppleMetadata(named: ".DS_Store"), "目录列表忽略 Finder 元数据")
            check(FileSystemService.isIgnoredAppleMetadata(named: "._preview.png"), "目录列表忽略 AppleDouble 元数据")
            check(!FileSystemService.isIgnoredAppleMetadata(named: ".env"), "目录列表保留普通点文件")
            check(!FileSystemService.isIgnoredAppleMetadata(named: ".github"), "目录列表保留普通点目录")

            let treeDirectoryEntry = FileEntry(
                url: root.appendingPathComponent("tree", isDirectory: true),
                kind: .directory
            )
            let retainedChildEntry = FileEntry(
                url: treeDirectoryEntry.url.appendingPathComponent("retained.md"),
                kind: .file
            )
            let removedChildEntry = FileEntry(
                url: treeDirectoryEntry.url.appendingPathComponent("removed.md"),
                kind: .file
            )
            let addedChildEntry = FileEntry(
                url: treeDirectoryEntry.url.appendingPathComponent("added.md"),
                kind: .file
            )
            let treeDirectoryNode = FileNode(entry: treeDirectoryEntry)
            let retainedChildNode = FileNode(entry: retainedChildEntry)
            treeDirectoryNode.isExpanded = true
            treeDirectoryNode.children = [
                retainedChildNode,
                FileNode(entry: removedChildEntry)
            ]
            FileTreeMerger.prepareForRefresh([treeDirectoryNode])
            let mergedTree = FileTreeMerger.merge(
                entries: [treeDirectoryEntry],
                reusing: [treeDirectoryNode],
                refreshedEntriesByDirectory: [
                    treeDirectoryEntry.url.path: [retainedChildEntry, addedChildEntry]
                ],
                forcedExpandedPaths: []
            )
            check(mergedTree.first === treeDirectoryNode, "目录刷新复用路径未变化的节点身份")
            check(treeDirectoryNode.isExpanded, "目录刷新保持用户已经展开的状态")
            check(
                treeDirectoryNode.children?.first === retainedChildNode &&
                    treeDirectoryNode.children?.map(\.name) == ["retained.md", "added.md"],
                "目录刷新只增删变化的子项并复用未变化行"
            )
            check(
                SidePanelLayout.maximumWidth(forWindowWidth: 1_440) == 480 &&
                    SidePanelLayout.maximumWidth(forWindowWidth: 600) == 260,
                "左右侧栏最大宽度按当前窗口三分之一动态调整并保留最小可用宽度"
            )
            check(
                OutlineResizeMath.width(
                    startWidth: 320,
                    startPointerX: 800,
                    currentPointerX: 740,
                    minimumWidth: 260,
                    maximumWidth: 600
                ) == 380 &&
                    OutlineResizeMath.width(
                        startWidth: 320,
                        startPointerX: 800,
                        currentPointerX: 900,
                        minimumWidth: 260,
                        maximumWidth: 600
                    ) == 260,
                "大纲分割条按全局鼠标位移一比一调整宽度并正确限制边界"
            )

            check(MarkdownStyle.migrated(from: "paper") == .newsprint, "旧纸页主题偏好可迁移")
            check(MarkdownStyle.migrated(from: "graphite") == .dark, "旧深色主题偏好可迁移")

            let symlinkTarget = root.appendingPathComponent("skill-research/example", isDirectory: true)
            let symlinkContainer = root.appendingPathComponent(".agents/skills", isDirectory: true)
            let symlink = symlinkContainer.appendingPathComponent("example", isDirectory: true)
            try FileManager.default.createDirectory(at: symlinkTarget, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: symlinkContainer, withIntermediateDirectories: true)
            try "# Example Skill\n".write(
                to: symlinkTarget.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: symlinkTarget)
            let symlinkIsDirectory: Bool
            if case .directory = try FileSystemService.kind(of: symlink, inside: root) {
                symlinkIsDirectory = true
            } else {
                symlinkIsDirectory = false
            }
            check(symlinkIsDirectory, "工作目录内的 .agents/skills 符号链接按目录展开")
            let symlinkEntries = try FileSystemService.entriesSynchronously(at: symlink, inside: root)
            check(
                symlinkEntries.contains {
                    $0.url.path == symlink.appendingPathComponent("SKILL.md").path &&
                        $0.kind == .file
                },
                "符号链接 Skill 目录可列出逻辑路径下的 SKILL.md"
            )

            let outside = FileManager.default.temporaryDirectory
                .appendingPathComponent("outside/secret.md")
            do {
                try FileSystemService.validate(outside, inside: root)
                check(false, "阻止读取工作目录外的路径")
            } catch {
                check(true, "阻止读取工作目录外的路径")
            }
        } catch {
            failures.append("自检执行失败：\(error.localizedDescription)")
            print("✗ \(error.localizedDescription)")
        }

        if failures.isEmpty {
            print("\n全部自检通过。")
            return 0
        }

        print("\n自检失败 \(failures.count) 项。")
        return 1
    }
}
#endif

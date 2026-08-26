import Foundation

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
            check(rendered.html.contains("<script src=\"\(MarkdownRenderer.mermaidScriptURL)\"></script>"), "页面仅加载固定版本 Mermaid 离线资源")
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
            check(!plainDocument.html.contains(MarkdownRenderer.mermaidScriptURL), "无 Mermaid 文档不加载 Mermaid 资源")

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
            let renderedHTML = try HTMLDocumentRenderer(
                style: ResolvedReaderTheme(style: .github, isDark: false),
                documentURL: root.appendingPathComponent("sample.html"),
                rootURL: root
            ).render(htmlSource, fileSize: Int64(htmlSource.utf8.count), modifiedAt: nil)
            check(FileNode.previewableExtensions.contains("html"), "HTML 与 HTM 文件进入可预览文档类型")
            check(renderedHTML.renderingMode == .interactiveHTML, "HTML 使用保留原始 CSS 与 JavaScript 的交互网页模式")
            check(renderedHTML.html.contains("<h1 id=\"html-标题\">HTML 标题</h1>"), "HTML 同时生成加载失败时的静态回退内容")
            check(renderedHTML.outline.map(\.title) == ["HTML 标题"], "HTML 标题生成右侧大纲")
            check(renderedHTML.html.contains("modu-resource://local?"), "HTML 本地图片改写为安全目录资源")
            check(renderedHTML.html.contains("img-src data: modu-resource: http: https:"), "HTML CSP 允许安全本地与远程图片")
            check(renderedHTML.html.contains("modu-markdown://local?"), "HTML 可链接工作目录内的 Markdown 或 HTML 文档")
            check(renderedHTML.html.contains(".card { border: 1px solid currentColor; }"), "HTML 内联样式被保留")
            check(!renderedHTML.html.contains("unsafeExecuted"), "HTML 静态回退不会执行文档自带脚本")
            check(
                renderedHTML.html.contains("style-src 'unsafe-inline'; script-src 'none'") &&
                    renderedHTML.html.contains("font-src 'none'") &&
                    !renderedHTML.html.contains("style-src 'unsafe-inline' http"),
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
                    origin?.contains("- Version: \(MarkdownRenderer.mermaidVersion)") == true &&
                    origin?.contains("https://registry.npmjs.org/mermaid/") == true,
                "Mermaid 资源记录固定版本与来源"
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

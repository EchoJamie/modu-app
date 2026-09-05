import Foundation
import Testing
@testable import MoDu

@Suite("Markdown embedded HTML")
struct MarkdownHTMLTests {
    private func render(_ source: String) throws -> String {
        let root = URL(fileURLWithPath: "/tmp/modu-html-tests", isDirectory: true)
        let renderer = MarkdownRenderer(
            style: ResolvedReaderTheme(style: MarkdownStyle.allCases[0], isDark: false),
            documentURL: root.appendingPathComponent("sample.md"), rootURL: root
        )
        return try renderer.render(source, fileSize: 0, modifiedAt: nil).html
    }

    @Test func rendersBlocksAndInlineHTML() throws {
        let html = try render("""
        Hello<br><span style="color: red">red **bold**</span>.

        <details open><summary>More</summary><p>Content</p></details>

        <table><tr><td colspan="2">Cell</td></tr></table>
        """)
        #expect(html.contains("Hello<br><span style=\"color: red\">red <strong>bold</strong></span>"))
        #expect(html.contains("<details open=\"\"><summary>More</summary><p>Content</p></details>"))
        #expect(html.contains("<td colspan=\"2\">Cell</td>"))
    }

    @Test func keepsCodeLiteral() throws {
        let html = try render("```html\n<div>example</div>\n```\n\n`<br>`")
        #expect(html.contains("&lt;div&gt;example&lt;/div&gt;"))
        #expect(html.contains("<code>&lt;br&gt;</code>"))
    }

    @Test func filtersActiveContentAndRewritesResources() throws {
        let html = try render("""
        <div onclick="alert(1)"><script>alert(1)</script><iframe srcdoc="bad"></iframe></div>

        <a href="jav&#x61;script:alert(1)">bad</a><a href="https://example.com/?a=1&amp;b=2">good</a>

        <img src="images/pic.png" onerror="alert(1)" srcset="https://evil.test/a 2x">
        """)
        #expect(!html.contains("onclick="))
        #expect(!html.contains("onerror="))
        #expect(!html.contains("srcset="))
        #expect(!html.contains("<script>"))
        #expect(!html.contains("<iframe"))
        #expect(html.contains("<a>bad</a>"))
        #expect(html.contains("href=\"https://example.com/?a=1&amp;b=2\""))
        #expect(html.contains("\(LocalDocumentResourcePolicy.resourceScheme)://local?path=images/pic.png"))
    }

    @Test func malformedMarkupCannotEscapeAttributes() {
        let html = MarkdownHTMLSanitizer.render(
            #"<SPAN title="a > b &quot; onclick='bad'">ok</SPAN><img src=x onerror=bad><svg/onload=bad>"#,
            link: { _ in nil }, image: { _ in nil }
        )
        #expect(html.contains(#"<span title="a &gt; b &quot; onclick='bad'">ok</span>"#))
        #expect(!html.contains(" onerror="))
        #expect(!html.contains("<svg"))
    }
}

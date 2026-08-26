import AppKit
import SwiftUI

/// 一套主题同时控制应用界面与 Markdown 正文；明暗由 `AppAppearance` 决定。
enum MarkdownStyle: String, CaseIterable, Identifiable, Sendable {
    case newsprint
    case minimal
    case sepia
    case dark
    case github

    var id: String { rawValue }

    var name: String {
        switch self {
        case .newsprint: "纸页"
        case .minimal: "极简"
        case .sepia: "暖沙"
        case .dark: "墨夜"
        case .github: "GitHub"
        }
    }

    var subtitle: String {
        switch self {
        case .newsprint: "宋体正文与纸张质感"
        case .minimal: "留白充足的现代阅读"
        case .sepia: "适合长时间阅读的暖色"
        case .dark: "克制的中性墨色界面"
        case .github: "熟悉的技术文档排版"
        }
    }

    var symbol: String {
        switch self {
        case .newsprint: "newspaper"
        case .minimal: "circle.lefthalf.filled"
        case .sepia: "sun.haze"
        case .dark: "moon.stars"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }

    static func migrated(from rawValue: String?) -> MarkdownStyle? {
        switch rawValue {
        case "paper", "newsprint": .newsprint
        case "minimal": .minimal
        case "sepia", "warmSand": .sepia
        case "dark", "graphite", "ink": .dark
        case "github", "snow": .github
        default: nil
        }
    }
}

struct ResolvedReaderTheme: Equatable, Sendable {
    let style: MarkdownStyle
    let isDark: Bool

    var canvasColor: NSColor { NSColor(themeHex: palette.canvas) }
    var canvas: Color { Color(nsColor: canvasColor) }
    var chrome: Color { Color(nsColor: NSColor(themeHex: palette.chrome)) }
    var foreground: Color { Color(nsColor: NSColor(themeHex: palette.text)) }
    var secondary: Color { Color(nsColor: NSColor(themeHex: palette.muted)) }
    var accent: Color { Color(nsColor: NSColor(themeHex: palette.accent)) }
    var divider: Color { Color(nsColor: NSColor(themeHex: palette.border)) }

    var stylesheet: String {
        Self.baseStylesheet + "\n" + rootVariables + "\n" + layoutStylesheet
    }

    private var palette: ThemePalette {
        switch (style, isDark) {
        case (.newsprint, false):
            ThemePalette(
                canvas: 0xF6F3EC, chrome: 0xEEEAE1, text: 0x2A2520, muted: 0x746C62,
                heading: 0x201D1A, accent: 0xA04F38, border: 0xCFC7B9,
                softBorder: 0xDED8CD, codeBackground: 0xEBE7DF, codeText: 0x302B26,
                quoteBackground: 0xE8E1D5, tableHead: 0xE9E4DB, tableStripe: 0xEFEAE1
            )
        case (.newsprint, true):
            ThemePalette(
                canvas: 0x24211E, chrome: 0x2D2925, text: 0xE8E0D5, muted: 0xAEA397,
                heading: 0xF4EDE3, accent: 0xE39A7B, border: 0x514A43,
                softBorder: 0x443E38, codeBackground: 0x1C1A18, codeText: 0xE8E0D5,
                quoteBackground: 0x302B27, tableHead: 0x38322D, tableStripe: 0x292622
            )
        case (.minimal, false):
            ThemePalette(
                canvas: 0xFFFFFF, chrome: 0xF7F7F6, text: 0x242424, muted: 0x747474,
                heading: 0x171717, accent: 0x4E67C8, border: 0xDEDEDB,
                softBorder: 0xECECEA, codeBackground: 0xF7F7F6, codeText: 0x262626,
                quoteBackground: 0xFAFAF9, tableHead: 0xF7F7F6, tableStripe: 0xFBFBFA
            )
        case (.minimal, true):
            ThemePalette(
                canvas: 0x191B1F, chrome: 0x202329, text: 0xE7E8EA, muted: 0xA0A5AE,
                heading: 0xF7F7F8, accent: 0x93A7FF, border: 0x383D45,
                softBorder: 0x30343B, codeBackground: 0x14161A, codeText: 0xE7E8EA,
                quoteBackground: 0x22252B, tableHead: 0x282C33, tableStripe: 0x1D2025
            )
        case (.sepia, false):
            ThemePalette(
                canvas: 0xF5EDDF, chrome: 0xEDE2D1, text: 0x3B3026, muted: 0x7B6958,
                heading: 0x2D251E, accent: 0x9A5B35, border: 0xCFBDA4,
                softBorder: 0xDED0BC, codeBackground: 0xEADFCE, codeText: 0x3C332A,
                quoteBackground: 0xEBDDC9, tableHead: 0xE5D7C2, tableStripe: 0xEFE3D2
            )
        case (.sepia, true):
            ThemePalette(
                canvas: 0x2B241E, chrome: 0x352C24, text: 0xEADBC9, muted: 0xB6A18C,
                heading: 0xF5E7D6, accent: 0xE2A06D, border: 0x5B4B3D,
                softBorder: 0x4B3E33, codeBackground: 0x211C18, codeText: 0xEADBC9,
                quoteBackground: 0x392F27, tableHead: 0x42362C, tableStripe: 0x302821
            )
        case (.dark, false):
            ThemePalette(
                canvas: 0xF1F3F5, chrome: 0xE7EAED, text: 0x252A30, muted: 0x68717B,
                heading: 0x171B1F, accent: 0x3D6F9E, border: 0xC8CED5,
                softBorder: 0xD8DDE2, codeBackground: 0xE3E7EB, codeText: 0x22272C,
                quoteBackground: 0xE8EBEE, tableHead: 0xDFE4E8, tableStripe: 0xEBEEF1
            )
        case (.dark, true):
            ThemePalette(
                canvas: 0x1F2328, chrome: 0x252A30, text: 0xE6EDF3, muted: 0x9DA7B1,
                heading: 0xF0F6FC, accent: 0x58A6FF, border: 0x3D444D,
                softBorder: 0x343B43, codeBackground: 0x161B22, codeText: 0xE6EDF3,
                quoteBackground: 0x252A30, tableHead: 0x2D333B, tableStripe: 0x262C33
            )
        case (.github, false):
            ThemePalette(
                canvas: 0xFFFFFF, chrome: 0xF6F8FA, text: 0x1F2328, muted: 0x656D76,
                heading: 0x1F2328, accent: 0x0969DA, border: 0xD0D7DE,
                softBorder: 0xD8DEE4, codeBackground: 0xF6F8FA, codeText: 0x24292F,
                quoteBackground: 0xF6F8FA, tableHead: 0xF6F8FA, tableStripe: 0xF8F9FA
            )
        case (.github, true):
            ThemePalette(
                canvas: 0x0D1117, chrome: 0x161B22, text: 0xE6EDF3, muted: 0x8B949E,
                heading: 0xF0F6FC, accent: 0x58A6FF, border: 0x30363D,
                softBorder: 0x21262D, codeBackground: 0x161B22, codeText: 0xE6EDF3,
                quoteBackground: 0x161B22, tableHead: 0x161B22, tableStripe: 0x11161D
            )
        }
    }

    private var rootVariables: String {
        let p = palette
        return """
        :root {
          color-scheme: \(isDark ? "dark" : "light");
          --page-bg: \(p.css(\.canvas)); --text: \(p.css(\.text)); --muted: \(p.css(\.muted));
          --heading: \(p.css(\.heading)); --accent: \(p.css(\.accent));
          --accent-soft: \(p.rgba(\.accent, alpha: isDark ? 0.18 : 0.12));
          --border: \(p.css(\.border)); --soft-border: \(p.css(\.softBorder));
          --code-bg: \(p.css(\.codeBackground)); --code-text: \(p.css(\.codeText));
          --inline-code-bg: \(p.rgba(\.muted, alpha: isDark ? 0.22 : 0.12));
          --quote-bg: \(p.css(\.quoteBackground)); --table-head: \(p.css(\.tableHead));
          --table-stripe: \(p.css(\.tableStripe));
        }
        """
    }

    private var layoutStylesheet: String {
        switch style {
        case .github:
            """
            :root { --body-font: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", sans-serif; --heading-font: var(--body-font); --content-width: 860px; --body-size: 16px; --line-height: 1.68; }
            #write > h1, #write > h2 { padding-bottom: .3em; border-bottom: 1px solid var(--soft-border); }
            """
        case .newsprint:
            """
            :root { --body-font: "Songti SC", "STSong", Georgia, serif; --heading-font: "PingFang SC", -apple-system, sans-serif; --content-width: 760px; --body-size: 17px; --line-height: 1.82; }
            #write > h1 { text-align: center; margin-bottom: 1.5em; letter-spacing: .03em; }
            #write > h2 { margin-top: 2.4em; }
            table { font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; font-size: .88em; }
            """
        case .minimal:
            """
            :root { --body-font: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; --heading-font: var(--body-font); --content-width: 800px; --body-size: 16.5px; --line-height: 1.76; }
            #write { letter-spacing: .005em; }
            #write > h1 { font-size: 2.15em; letter-spacing: -.035em; }
            blockquote { border-left-width: 2px; }
            """
        case .sepia:
            """
            :root { --body-font: "Songti SC", "STSong", Georgia, serif; --heading-font: "PingFang SC", -apple-system, sans-serif; --content-width: 780px; --body-size: 17px; --line-height: 1.8; }
            table { font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; font-size: .9em; }
            """
        case .dark:
            """
            :root { --body-font: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", sans-serif; --heading-font: var(--body-font); --content-width: 860px; --body-size: 16px; --line-height: 1.7; }
            #write > h1, #write > h2 { padding-bottom: .3em; border-bottom: 1px solid var(--soft-border); }
            """
        }
    }

    private static let baseStylesheet = """
    * { box-sizing: border-box; }
    html { margin: 0; padding: 0; background: var(--page-bg); -webkit-font-smoothing: antialiased; }
    body { margin: 0; background: var(--page-bg); color: var(--text); font-family: var(--body-font); font-size: var(--body-size); line-height: var(--line-height); text-rendering: optimizeLegibility; }
    #write { max-width: var(--content-width); margin: 0 auto; padding: 54px 46px 120px; overflow-wrap: break-word; -webkit-user-select: text; user-select: text; }
    #write * { -webkit-user-select: text; user-select: text; }
    #write > :first-child { margin-top: 0; }
    #write > :last-child { margin-bottom: 0; }
    h1, h2, h3, h4, h5, h6 { color: var(--heading); font-family: var(--heading-font); line-height: 1.32; margin: 1.9em 0 .72em; scroll-margin-top: 28px; }
    h1 { font-size: 2em; font-weight: 750; letter-spacing: -.025em; }
    h2 { font-size: 1.55em; font-weight: 720; letter-spacing: -.018em; }
    h3 { font-size: 1.25em; font-weight: 680; }
    h4 { font-size: 1.08em; font-weight: 650; }
    h5 { font-size: 1em; font-weight: 650; }
    h6 { font-size: .94em; font-weight: 650; color: var(--muted); }
    p { margin: 0 0 1em; }
    strong { color: var(--heading); font-weight: 650; }
    em { font-style: italic; }
    del { color: var(--muted); }
    a { color: var(--accent); background: none; text-decoration: underline; text-decoration-color: color-mix(in srgb, var(--accent) 55%, transparent); text-underline-offset: .18em; }
    a:hover { text-decoration-thickness: 2px; }
    ul, ol { margin: .7em 0 1.1em; padding-left: 1.7em; }
    li { margin: .32em 0; padding-left: .15em; }
    li > ul, li > ol { margin: .25em 0; }
    li.task-list-item { list-style: none; margin-left: -1.45em; }
    input[type="checkbox"] { appearance: none; width: 15px; height: 15px; margin: 0 .5em 0 0; vertical-align: -.15em; border: 1px solid var(--border); border-radius: 4px; background: var(--page-bg); }
    input[type="checkbox"]:checked { border-color: var(--accent); background: var(--accent); }
    input[type="checkbox"]:checked::after { content: "✓"; display: block; color: white; font: 700 11px/13px -apple-system; text-align: center; }
    blockquote { margin: 1.35em 0; padding: .78em 1.05em; border-left: 4px solid var(--accent); background: var(--quote-bg); color: var(--muted); }
    blockquote > :last-child { margin-bottom: 0; }
    hr { height: 1px; margin: 2.2em 0; border: 0; background: var(--soft-border); }
    code, pre { font-family: ui-monospace, "SFMono-Regular", Menlo, Monaco, Consolas, monospace; }
    :not(pre) > code { padding: .12em .34em; border-radius: 4px; background: var(--inline-code-bg); color: var(--text); font-size: .88em; }
    a code { padding: 0; background: none; color: inherit; }
    pre { position: relative; margin: 1.35em 0; padding: 18px 20px; overflow: auto; border: 1px solid var(--soft-border); border-radius: 7px; background: var(--code-bg); color: var(--code-text); font-size: 13px; line-height: 1.58; tab-size: 4; }
    pre[data-language] { padding-top: 36px; }
    pre[data-language]::before { content: attr(data-language); position: absolute; top: 10px; left: 19px; color: var(--muted); font: 650 10px/1 ui-monospace, "SFMono-Regular", Menlo, monospace; letter-spacing: .07em; text-transform: uppercase; }
    pre code { padding: 0; border: 0; background: none; color: inherit; font-size: inherit; white-space: pre; }
    .front-matter { margin: .15em 0 1.45em; padding: .72rem .95rem .68rem; border-radius: 10px; background: linear-gradient(115deg, var(--accent-soft), color-mix(in srgb, var(--table-head) 68%, transparent)); font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; font-size: 13px; line-height: 1.45; }
    .front-matter-heading { display: flex; align-items: center; min-height: 1.15rem; margin-bottom: .38rem; color: var(--muted); }
    .front-matter-mark { width: 3px; height: .92rem; margin-right: .58rem; border-radius: 99px; background: var(--accent); box-shadow: 5px 0 0 color-mix(in srgb, var(--accent) 38%, transparent); }
    .front-matter-title { color: var(--heading); font-size: 11px; font-weight: 700; letter-spacing: .08em; }
    .front-matter-count { margin-left: auto; font-size: 10.5px; font-variant-numeric: tabular-nums; }
    .front-matter-list { margin: 0; }
    .front-matter-row { display: grid; grid-template-columns: minmax(6.5rem, 24%) minmax(0, 1fr); column-gap: 1rem; align-items: start; padding: .12rem 0; }
    .front-matter dt { min-width: 0; color: var(--muted); font: 600 11.5px/1.55 ui-monospace, "SFMono-Regular", Menlo, monospace; overflow-wrap: anywhere; }
    .front-matter dt::after { content: ":"; margin-left: .08em; color: color-mix(in srgb, var(--muted) 64%, transparent); }
    .front-matter dd { min-width: 0; margin: 0; color: var(--text); white-space: pre-line; overflow-wrap: anywhere; }
    .front-matter.is-collapsible .front-matter-preview dd { display: -webkit-box; overflow: hidden; white-space: normal; -webkit-box-orient: vertical; -webkit-line-clamp: 2; }
    .front-matter:has(.front-matter-more[open]) .front-matter-preview dd { display: block; overflow: visible; white-space: pre-line; -webkit-line-clamp: unset; }
    .front-matter-more { margin-top: .3rem; color: var(--accent); }
    .front-matter-more summary { display: flex; width: fit-content; align-items: center; gap: .42rem; cursor: pointer; list-style: none; font-size: 11.5px; font-weight: 600; user-select: none; -webkit-user-select: none; }
    .front-matter-more summary::-webkit-details-marker { display: none; }
    .front-matter-more summary::before { width: .38rem; height: .38rem; border-right: 1.5px solid currentColor; border-bottom: 1.5px solid currentColor; content: ""; transform: rotate(-45deg); transition: transform 120ms ease; }
    .front-matter-more[open] summary::before { transform: rotate(45deg) translate(-1px, -1px); }
    .front-matter-collapse { display: none; }
    .front-matter-more[open] .front-matter-expand { display: none; }
    .front-matter-more[open] .front-matter-collapse { display: inline; }
    .front-matter-remainder { margin-top: .28rem; }
    .front-matter + h1 { margin-top: 1.2em; }
    .table-wrap { width: 100%; margin: 1.4em 0; overflow-x: auto; border: 1px solid var(--border); border-radius: 7px; }
    .table-wrap.is-wide { position: relative; left: 50%; width: min(1800px, calc(100vw - 72px)); max-width: none; transform: translateX(-50%); }
    table { width: 100%; min-width: 100%; table-layout: auto; border-collapse: collapse; border-spacing: 0; line-height: 1.5; font-size: .91em; }
    .table-wrap.is-wide table { min-width: 68rem; }
    th, td { min-width: 8rem; max-width: 36rem; padding: 9px 12px; border-right: 1px solid var(--border); border-bottom: 1px solid var(--border); vertical-align: top; text-align: left; overflow-wrap: break-word; word-break: normal; white-space: normal; }
    th:last-child, td:last-child { min-width: 10rem; border-right: 0; }
    .table-wrap.is-wide th:last-child, .table-wrap.is-wide td:last-child { min-width: 18rem; }
    tbody tr:last-child td { border-bottom: 0; }
    th { background: var(--table-head); color: var(--heading); font-weight: 650; }
    tbody tr:nth-child(even) { background: var(--table-stripe); }
    td code, th code { white-space: normal; }
    img { display: block; max-width: 100%; height: auto; margin: 1.5em auto; border-radius: 6px; }
    .image-placeholder { display: inline-block; padding: .3em .6em; border: 1px dashed var(--border); border-radius: 5px; color: var(--muted); font-size: .88em; }
    .raw-html { white-space: pre-wrap; }
    @media (max-width: 760px) { #write { padding: 38px 28px 90px; } h1 { font-size: 1.8em; } .front-matter-row { grid-template-columns: minmax(5.25rem, 30%) minmax(0, 1fr); column-gap: .7rem; } }
    """
}

private struct ThemePalette: Sendable {
    let canvas: UInt32
    let chrome: UInt32
    let text: UInt32
    let muted: UInt32
    let heading: UInt32
    let accent: UInt32
    let border: UInt32
    let softBorder: UInt32
    let codeBackground: UInt32
    let codeText: UInt32
    let quoteBackground: UInt32
    let tableHead: UInt32
    let tableStripe: UInt32

    func css(_ keyPath: KeyPath<ThemePalette, UInt32>) -> String {
        String(format: "#%06X", self[keyPath: keyPath])
    }

    func rgba(_ keyPath: KeyPath<ThemePalette, UInt32>, alpha: Double) -> String {
        let value = self[keyPath: keyPath]
        let red = (value >> 16) & 0xFF
        let green = (value >> 8) & 0xFF
        let blue = value & 0xFF
        return "rgba(\(red),\(green),\(blue),\(alpha))"
    }
}

private extension NSColor {
    convenience init(themeHex: UInt32) {
        self.init(
            calibratedRed: CGFloat((themeHex >> 16) & 0xFF) / 255,
            green: CGFloat((themeHex >> 8) & 0xFF) / 255,
            blue: CGFloat(themeHex & 0xFF) / 255,
            alpha: 1
        )
    }
}

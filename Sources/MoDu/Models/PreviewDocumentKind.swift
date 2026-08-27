import Foundation

enum PreviewDocumentKind: Equatable, Sendable {
    case markdown
    case html
    case image
    case source(SourceLanguage)

    static func resolve(fileName rawName: String, isRegularFile: Bool) -> PreviewDocumentKind? {
        guard isRegularFile else { return nil }
        let name = rawName.lowercased()
        let fileExtension = URL(fileURLWithPath: rawName).pathExtension.lowercased()

        if markdownExtensions.contains(fileExtension) { return .markdown }
        if htmlExtensions.contains(fileExtension) { return .html }
        if imageExtensions.contains(fileExtension) { return .image }

        if name == "dockerfile" || name.hasPrefix("dockerfile.") { return .source(.dockerfile) }
        if name == "makefile" || name.hasPrefix("makefile.") { return .source(.makefile) }
        if name == "gemfile" || name == "rakefile" || name == "podfile" { return .source(.ruby) }
        if name == "package.resolved" { return .source(.json) }
        if name == ".env" || name.hasPrefix(".env.") { return .source(.properties) }

        let specialFiles: [String: SourceLanguage] = [
            ".editorconfig": .ini,
            ".gitattributes": .plaintext,
            ".gitignore": .plaintext,
            ".dockerignore": .plaintext,
            ".npmrc": .ini,
            ".yarnrc": .yaml,
            "license": .plaintext,
            "notice": .plaintext,
            "readme": .plaintext
        ]
        if let language = specialFiles[name] { return .source(language) }

        if let language = sourceExtensions[fileExtension] {
            return .source(language)
        }
        if fileExtension.isEmpty {
            return .source(.plaintext)
        }
        return nil
    }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    static let htmlExtensions: Set<String> = ["html", "htm"]
    static let imageExtensions = LocalDocumentResourcePolicy.imageExtensions(
        for: .standalonePreview
    )

    private static let sourceExtensions: [String: SourceLanguage] = [
        "txt": .plaintext, "text": .plaintext, "log": .plaintext,
        "csv": .plaintext, "tsv": .plaintext, "lock": .plaintext,
        "swift": .swift,
        "c": .c, "h": .c,
        "cc": .cpp, "cpp": .cpp, "cxx": .cpp,
        "hh": .cpp, "hpp": .cpp, "hxx": .cpp,
        "m": .objectivec, "mm": .objectivec,
        "cs": .csharp,
        "java": .java, "kt": .kotlin, "kts": .kotlin,
        "js": .javascript, "jsx": .javascript, "mjs": .javascript, "cjs": .javascript,
        "ts": .typescript, "tsx": .typescript, "mts": .typescript, "cts": .typescript,
        "py": .python, "pyw": .python,
        "go": .go, "rs": .rust, "rb": .ruby,
        "php": .php, "lua": .lua, "pl": .perl, "pm": .perl, "r": .r,
        "sh": .bash, "bash": .bash, "zsh": .bash, "fish": .bash, "command": .bash,
        "css": .css, "scss": .scss, "sass": .scss, "less": .less,
        "sql": .sql,
        "json": .json, "jsonc": .json, "json5": .json,
        "yaml": .yaml, "yml": .yaml,
        "xml": .xml, "plist": .xml, "xib": .xml, "storyboard": .xml, "svg": .xml,
        "ini": .ini, "cfg": .ini, "conf": .ini, "toml": .toml,
        "properties": .properties, "env": .properties,
        "gradle": .gradle, "groovy": .groovy,
        "diff": .diff, "patch": .diff,
        "graphql": .graphql, "gql": .graphql,
        "mk": .makefile
    ]
}

enum SourceLanguage: String, CaseIterable, Identifiable, Sendable {
    case plaintext
    case bash
    case c
    case cpp
    case objectivec
    case csharp
    case swift
    case java
    case kotlin
    case javascript
    case typescript
    case python
    case go
    case rust
    case ruby
    case php
    case lua
    case perl
    case r
    case css
    case scss
    case less
    case sql
    case json
    case yaml
    case xml
    case ini
    case toml
    case dockerfile
    case makefile
    case groovy
    case gradle
    case properties
    case diff
    case graphql
    case markdown

    var id: String { rawValue }

    var highlightIdentifier: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .plaintext: L10n.string(.sourceLanguagePlainText)
        case .bash: "Shell"
        case .c: "C"
        case .cpp: "C++"
        case .objectivec: "Objective-C"
        case .csharp: "C#"
        case .swift: "Swift"
        case .java: "Java"
        case .kotlin: "Kotlin"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .python: "Python"
        case .go: "Go"
        case .rust: "Rust"
        case .ruby: "Ruby"
        case .php: "PHP"
        case .lua: "Lua"
        case .perl: "Perl"
        case .r: "R"
        case .css: "CSS"
        case .scss: "SCSS"
        case .less: "Less"
        case .sql: "SQL"
        case .json: "JSON"
        case .yaml: "YAML"
        case .xml: "XML"
        case .ini: "INI"
        case .toml: "TOML"
        case .dockerfile: "Dockerfile"
        case .makefile: "Makefile"
        case .groovy: "Groovy"
        case .gradle: "Gradle"
        case .properties: "Properties"
        case .diff: "Diff"
        case .graphql: "GraphQL"
        case .markdown: "Markdown"
        }
    }
}

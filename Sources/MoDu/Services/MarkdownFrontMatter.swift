import Foundation

struct MarkdownFrontMatter: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let key: String
        let value: String
    }

    static let previewEntryLimit = 4

    let entries: [Entry]
    let sourceLineCount: Int

    var isCollapsible: Bool {
        entries.count > Self.previewEntryLimit ||
            sourceLineCount > 6 ||
            entries.contains { $0.value.count > 180 || $0.value.contains("\n") }
    }

    static func extract(from source: String) -> (metadata: MarkdownFrontMatter?, markdown: String) {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let sourceWithoutBOM = normalized.hasPrefix("\u{FEFF}")
            ? String(normalized.dropFirst())
            : normalized
        let lines = sourceWithoutBOM.components(separatedBy: "\n")

        guard lines.first.map(isOpeningDelimiter) == true else {
            return (nil, source)
        }

        guard let closingIndex = lines.indices.dropFirst().first(where: {
            isClosingDelimiter(lines[$0])
        }) else {
            return (nil, source)
        }

        let metadataLines = Array(lines[1..<closingIndex])
        let entries = parseEntries(from: metadataLines)
        guard !entries.isEmpty else {
            return (nil, source)
        }

        return (
            MarkdownFrontMatter(entries: entries, sourceLineCount: metadataLines.count),
            lines.dropFirst(closingIndex + 1).joined(separator: "\n")
        )
    }

    private static func isOpeningDelimiter(_ line: String) -> Bool {
        guard line.first.map({ !$0.isWhitespace }) ?? false else { return false }
        return line.trimmingCharacters(in: .whitespaces) == "---"
    }

    private static func isClosingDelimiter(_ line: String) -> Bool {
        guard line.first.map({ !$0.isWhitespace }) ?? false else { return false }
        let delimiter = line.trimmingCharacters(in: .whitespaces)
        return delimiter == "---" || delimiter == "..."
    }

    private static func parseEntries(from lines: [String]) -> [Entry] {
        var entries: [Entry] = []
        var currentKey: String?
        var initialValue = ""
        var continuationLines: [String] = []

        func flushCurrentEntry() {
            guard let key = currentKey else { return }
            let value = formattedValue(initial: initialValue, continuation: continuationLines)
            entries.append(Entry(key: key, value: value.isEmpty ? "—" : value))
        }

        for line in lines {
            if let pair = topLevelPair(in: line) {
                flushCurrentEntry()
                currentKey = pair.key
                initialValue = pair.value
                continuationLines = []
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard currentKey != nil else { continue }
            if !trimmed.hasPrefix("#") {
                continuationLines.append(trimmed)
            }
        }

        flushCurrentEntry()
        return entries
    }

    private static func topLevelPair(in line: String) -> (key: String, value: String)? {
        guard line.first.map({ !$0.isWhitespace }) ?? false else { return nil }
        guard !line.hasPrefix("#"), !line.hasPrefix("-") else { return nil }
        guard let separator = line.firstIndex(of: ":") else { return nil }

        let rawKey = line[..<separator].trimmingCharacters(in: .whitespaces)
        guard !rawKey.isEmpty else { return nil }

        let valueStart = line.index(after: separator)
        let rawValue = line[valueStart...].trimmingCharacters(in: .whitespaces)
        return (unquoted(rawKey), rawValue)
    }

    private static func formattedValue(initial: String, continuation: [String]) -> String {
        let marker = initial.trimmingCharacters(in: .whitespaces)
        let meaningfulContinuation = continuation
            .drop(while: { $0.isEmpty })
            .reversed()
            .drop(while: { $0.isEmpty })
            .reversed()

        if marker.hasPrefix(">") {
            return unquoted(meaningfulContinuation.joined(separator: " "))
        }
        if marker.hasPrefix("|") {
            return unquoted(meaningfulContinuation.joined(separator: "\n"))
        }

        let pieces = ([marker] + meaningfulContinuation).filter { !$0.isEmpty }
        return unquoted(pieces.joined(separator: "\n"))
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last else {
            return value
        }
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

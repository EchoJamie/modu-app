import Foundation

enum SourceFileError: LocalizedError {
    case notRegularFile
    case fileChanged
    case pageUnavailable

    var errorDescription: String? {
        switch self {
        case .notRegularFile: L10n.string(.sourceNotRegularFile)
        case .fileChanged: L10n.string(.sourceFileChanged)
        case .pageUnavailable: L10n.string(.sourcePageUnavailable)
        }
    }
}

final class SourceFileSession: @unchecked Sendable {
    static let maximumPageBytes = 256 * 1_024
    static let maximumPageLines = 2_000
    static let checkpointStride = 256
    static let maximumRecentLocations = 512

    let fileURL: URL
    let rootURL: URL
    let fileSize: Int64
    let modifiedAt: Date?
    let encoding: SourceTextEncoding
    let suggestedLanguage: SourceLanguage?

    private let contentStartOffset: UInt64
    private let lock = NSLock()
    private var checkpointLocations: [Int: SourcePageLocation]
    private var recentLocations: [Int: SourcePageLocation] = [:]
    private var recentLocationOrder: [Int] = []
    private var cachedPages: [Int: SourcePage] = [:]
    private var lastPageIndex: Int?

    init(fileURL: URL, rootURL: URL) throws {
        let readableURL = try FileSystemService.validatedURL(fileURL, inside: rootURL)
        let validatedRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let values = try readableURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        guard values.isRegularFile == true else { throw SourceFileError.notRegularFile }

        self.fileURL = readableURL
        self.rootURL = validatedRootURL
        fileSize = Int64(values.fileSize ?? 0)
        modifiedAt = values.contentModificationDate

        let probe = try Self.read(
            from: readableURL,
            offset: 0,
            count: min(64 * 1_024, max(0, values.fileSize ?? 0))
        )
        let detection = try Self.detectEncoding(in: probe)
        encoding = detection.encoding
        suggestedLanguage = Self.detectShebangLanguage(
            in: probe,
            encoding: detection.encoding,
            bomLength: detection.bomLength
        )
        contentStartOffset = detection.bomLength
        let initialLocation = SourcePageLocation(
            offset: detection.bomLength,
            startLine: 1,
            leadingContinuation: false
        )
        checkpointLocations = [0: initialLocation]
        recentLocations = [0: initialLocation]
        recentLocationOrder = [0]
    }

    func page(at requestedIndex: Int) throws -> SourcePage {
        try Task.checkCancellation()
        guard requestedIndex >= 0 else { throw SourceFileError.pageUnavailable }

        lock.lock()
        defer { lock.unlock() }
        try validateUnchanged()

        if let lastPageIndex, requestedIndex > lastPageIndex {
            throw SourceFileError.pageUnavailable
        }

        if let cached = cachedPages[requestedIndex] {
            cache(cached, around: requestedIndex)
            return cached
        }

        var (pageIndex, location) = nearestLocation(atOrBefore: requestedIndex)
        while pageIndex < requestedIndex {
            try Task.checkCancellation()
            rememberRecent(location, at: pageIndex)
            let preceding = try readPage(at: location, index: pageIndex)
            guard preceding.hasNext else {
                lastPageIndex = pageIndex
                throw SourceFileError.pageUnavailable
            }
            pageIndex += 1
            location = nextLocation(after: preceding)
            rememberCheckpointIfNeeded(location, at: pageIndex)
        }

        rememberRecent(location, at: requestedIndex)
        let page = try readPage(at: location, index: requestedIndex)
        if !page.hasNext { lastPageIndex = requestedIndex }
        if page.hasNext {
            let followingLocation = nextLocation(after: page)
            rememberRecent(followingLocation, at: requestedIndex + 1)
            rememberCheckpointIfNeeded(followingLocation, at: requestedIndex + 1)
        }
        cache(page, around: requestedIndex)
        return page
    }

    func page(containingLine requestedLine: Int) throws -> SourcePage? {
        try Task.checkCancellation()
        guard requestedLine > 0 else { return nil }

        lock.lock()
        let knownLocations = checkpointLocations
            .merging(recentLocations) { _, recent in recent }
            .sorted { $0.key < $1.key }
        var startingIndex = 0
        for (index, location) in knownLocations {
            if location.startLine < requestedLine {
                startingIndex = index
                continue
            }
            if location.startLine == requestedLine { startingIndex = index }
            break
        }
        lock.unlock()

        var pageIndex = startingIndex
        while true {
            try Task.checkCancellation()
            let candidate = try page(at: pageIndex)
            if requestedLine >= candidate.startLine, requestedLine <= candidate.endLine {
                return candidate
            }
            guard candidate.hasNext else { return nil }
            pageIndex += 1
        }
    }

    func find(
        _ query: String,
        caseSensitive: Bool,
        direction: DocumentSearchDirection,
        currentPageIndex: Int,
        currentMatch: SourceSearchMatch?
    ) throws -> (match: SourceSearchMatch?, didWrap: Bool) {
        try Task.checkCancellation()
        guard !query.isEmpty else { return (nil, false) }

        switch direction {
        case .next:
            return try findNext(
                query,
                caseSensitive: caseSensitive,
                currentPageIndex: currentPageIndex,
                currentMatch: currentMatch
            )
        case .previous:
            return try findPrevious(
                query,
                caseSensitive: caseSensitive,
                currentPageIndex: currentPageIndex,
                currentMatch: currentMatch
            )
        }
    }

    private func findNext(
        _ query: String,
        caseSensitive: Bool,
        currentPageIndex: Int,
        currentMatch: SourceSearchMatch?
    ) throws -> (SourceSearchMatch?, Bool) {
        let currentPage = try page(at: currentPageIndex)
        let initialLocation = currentMatch?.pageIndex == currentPageIndex
            ? min(currentMatch!.range.location + currentMatch!.range.length, currentPage.text.utf16.count)
            : 0

        if let match = try match(
            query,
            in: currentPage,
            caseSensitive: caseSensitive,
            direction: .next,
            utf16Range: NSRange(location: initialLocation, length: currentPage.text.utf16.count - initialLocation)
        ) {
            return (match, false)
        }

        var pageIndex = currentPageIndex + 1
        var previousPage = currentPage
        while previousPage.hasNext {
            try Task.checkCancellation()
            let candidate = try page(at: pageIndex)
            if let match = try match(query, in: candidate, caseSensitive: caseSensitive, direction: .next) {
                return (match, false)
            }
            previousPage = candidate
            pageIndex += 1
        }

        if currentPageIndex > 0 {
            for wrappedIndex in 0..<currentPageIndex {
                try Task.checkCancellation()
                let candidate = try page(at: wrappedIndex)
                if let match = try match(query, in: candidate, caseSensitive: caseSensitive, direction: .next) {
                    return (match, true)
                }
            }
        }

        if initialLocation > 0, let match = try match(
            query,
            in: currentPage,
            caseSensitive: caseSensitive,
            direction: .next,
            utf16Range: NSRange(location: 0, length: initialLocation)
        ) {
            return (match, true)
        }
        return (nil, false)
    }

    private func findPrevious(
        _ query: String,
        caseSensitive: Bool,
        currentPageIndex: Int,
        currentMatch: SourceSearchMatch?
    ) throws -> (SourceSearchMatch?, Bool) {
        let currentPage = try page(at: currentPageIndex)
        let initialLength = currentMatch?.pageIndex == currentPageIndex
            ? min(currentMatch!.range.location, currentPage.text.utf16.count)
            : currentPage.text.utf16.count

        if let match = try match(
            query,
            in: currentPage,
            caseSensitive: caseSensitive,
            direction: .previous,
            utf16Range: NSRange(location: 0, length: initialLength)
        ) {
            return (match, false)
        }

        if currentPageIndex > 0 {
            for candidateIndex in stride(from: currentPageIndex - 1, through: 0, by: -1) {
                try Task.checkCancellation()
                let candidate = try page(at: candidateIndex)
                if let match = try match(query, in: candidate, caseSensitive: caseSensitive, direction: .previous) {
                    return (match, false)
                }
            }
        }

        let finalPageIndex = try ensureLastPageIndex(startingAt: currentPageIndex)
        if finalPageIndex > currentPageIndex {
            for candidateIndex in stride(from: finalPageIndex, through: currentPageIndex + 1, by: -1) {
                try Task.checkCancellation()
                let candidate = try page(at: candidateIndex)
                if let match = try match(query, in: candidate, caseSensitive: caseSensitive, direction: .previous) {
                    return (match, true)
                }
            }
        }

        if initialLength < currentPage.text.utf16.count, let match = try match(
            query,
            in: currentPage,
            caseSensitive: caseSensitive,
            direction: .previous,
            utf16Range: NSRange(
                location: initialLength,
                length: currentPage.text.utf16.count - initialLength
            )
        ) {
            return (match, true)
        }
        return (nil, false)
    }

    private func ensureLastPageIndex(startingAt start: Int) throws -> Int {
        if let lastPageIndex { return lastPageIndex }
        var index = start
        var candidate = try page(at: index)
        while candidate.hasNext {
            try Task.checkCancellation()
            index += 1
            candidate = try page(at: index)
        }
        return index
    }

    private func match(
        _ query: String,
        in page: SourcePage,
        caseSensitive: Bool,
        direction: DocumentSearchDirection,
        utf16Range: NSRange? = nil
    ) throws -> SourceSearchMatch? {
        let boundedRange = utf16Range ?? NSRange(location: 0, length: page.text.utf16.count)
        guard let stringRange = Range(boundedRange, in: page.text) else { return nil }
        var options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        if direction == .previous { options.insert(.backwards) }
        if let found = page.text.range(of: query, options: options, range: stringRange) {
            return searchMatch(in: page.text, page: page, found: found)
        }

        let pageUTF16Count = page.text.utf16.count
        let boundedEnd = boundedRange.location + boundedRange.length
        let overlapLength = max(0, query.utf16.count - 1)
        guard
            page.hasNext,
            overlapLength > 0,
            boundedEnd == pageUTF16Count
        else { return nil }

        let overlap = try followingSearchOverlap(after: page, maximumUTF16Units: overlapLength)
        guard !overlap.isEmpty else { return nil }
        let combined = page.text + overlap
        let combinedRange = NSRange(
            location: boundedRange.location,
            length: combined.utf16.count - boundedRange.location
        )
        guard
            let combinedStringRange = Range(combinedRange, in: combined),
            let found = combined.range(of: query, options: options, range: combinedStringRange)
        else { return nil }

        let foundRange = NSRange(found, in: combined)
        guard foundRange.location < pageUTF16Count else { return nil }
        return searchMatch(in: combined, page: page, found: found)
    }

    private func searchMatch(
        in searchedText: String,
        page: SourcePage,
        found: Range<String.Index>
    ) -> SourceSearchMatch {
        let fullRange = NSRange(found, in: searchedText)
        let pageUTF16Count = page.text.utf16.count
        let visibleLength = min(fullRange.length, pageUTF16Count - fullRange.location)
        let prefix = searchedText[..<found.lowerBound]
        return SourceSearchMatch(
            pageIndex: page.index,
            range: NSRange(location: fullRange.location, length: visibleLength),
            line: page.startLine + prefix.reduce(into: 0) { count, character in
                if character == "\n" { count += 1 }
            }
        )
    }

    private func followingSearchOverlap(
        after page: SourcePage,
        maximumUTF16Units: Int
    ) throws -> String {
        var remaining = maximumUTF16Units
        var pageIndex = page.index
        var previousPage = page
        var result = ""

        while remaining > 0, previousPage.hasNext {
            try Task.checkCancellation()
            pageIndex += 1
            let candidate = try self.page(at: pageIndex)
            let prefix = Self.prefix(candidate.text, maximumUTF16Units: remaining)
            result += prefix
            let consumed = prefix.utf16.count
            remaining = max(0, remaining - consumed)
            if prefix.utf16.count < candidate.text.utf16.count { break }
            previousPage = candidate
        }
        return result
    }

    private func readPage(at location: SourcePageLocation, index: Int) throws -> SourcePage {
        try Task.checkCancellation()
        let totalSize = UInt64(max(0, fileSize))
        guard location.offset <= totalSize else { throw SourceFileError.pageUnavailable }
        let remaining = Int(min(
            UInt64(Self.maximumPageBytes + 8),
            totalSize - location.offset
        ))
        let readableURL = try FileSystemService.validatedURL(fileURL, inside: rootURL)
        let data = try Self.read(from: readableURL, offset: location.offset, count: remaining)
        let cutLength = try pageCut(in: data, reachesEnd: location.offset + UInt64(data.count) >= totalSize)
        let pageData = data.prefix(cutLength)
        guard let decodedText = String(data: pageData, encoding: encoding.stringEncoding) else {
            throw FileSystemError.unsupportedEncoding
        }
        let text = decodedText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let endOffset = location.offset + UInt64(cutLength)
        let newlineCount = Self.newlineCount(in: text)
        let endsAtLineBoundary = text.hasSuffix("\n") || endOffset >= totalSize
        let visibleLineCount = text.isEmpty
            ? 1
            : newlineCount + (text.hasSuffix("\n") ? 0 : 1)

        return SourcePage(
            index: index,
            text: text,
            startOffset: location.offset,
            endOffset: endOffset,
            startLine: location.startLine,
            endLine: location.startLine + max(0, visibleLineCount - 1),
            leadingContinuation: location.leadingContinuation,
            trailingContinuation: !endsAtLineBoundary,
            hasPrevious: index > 0,
            hasNext: endOffset < totalSize
        )
    }

    private func pageCut(in data: Data, reachesEnd: Bool) throws -> Int {
        guard !data.isEmpty else { return 0 }
        let unitWidth = encoding == .utf8 ? 1 : 2
        var hardLimit = min(data.count, Self.maximumPageBytes)
        hardLimit -= hardLimit % unitWidth

        var newlineCount = 0
        var lastNewlineEnd = 0
        var cursor = 0
        while cursor + unitWidth <= hardLimit {
            try Task.checkCancellation()
            let unit = codeUnit(in: data, at: cursor)
            if unit == 0x000D {
                newlineCount += 1
                let followingOffset = cursor + unitWidth
                let hasFollowingLF = followingOffset + unitWidth <= data.count &&
                    codeUnit(in: data, at: followingOffset) == 0x000A
                lastNewlineEnd = cursor + unitWidth * (hasFollowingLF ? 2 : 1)
                if newlineCount >= Self.maximumPageLines {
                    return lastNewlineEnd
                }
                cursor += unitWidth * (hasFollowingLF ? 2 : 1)
                continue
            }
            if unit == 0x000A {
                newlineCount += 1
                lastNewlineEnd = cursor + unitWidth
                if newlineCount >= Self.maximumPageLines { return lastNewlineEnd }
            }
            cursor += unitWidth
        }

        if reachesEnd, data.count <= Self.maximumPageBytes {
            return validCharacterBoundary(in: data, proposedEnd: data.count)
        }
        if lastNewlineEnd > 0 { return lastNewlineEnd }
        return validCharacterBoundary(in: data, proposedEnd: hardLimit)
    }

    private func validCharacterBoundary(in data: Data, proposedEnd: Int) -> Int {
        switch encoding {
        case .utf8:
            var end = min(proposedEnd, data.count)
            while end > 0, end < data.count, (data[end] & 0b1100_0000) == 0b1000_0000 {
                end -= 1
            }
            return end
        case .utf16LittleEndian, .utf16BigEndian:
            var end = min(proposedEnd, data.count)
            end -= end % 2
            guard end >= 2 else { return end }
            let lastUnit = utf16Unit(in: data, at: end - 2)
            if (0xD800...0xDBFF).contains(lastUnit) { end -= 2 }
            return end
        }
    }

    private func codeUnit(in data: Data, at offset: Int) -> UInt16 {
        switch encoding {
        case .utf8: UInt16(data[offset])
        case .utf16LittleEndian, .utf16BigEndian: utf16Unit(in: data, at: offset)
        }
    }

    private func utf16Unit(in data: Data, at offset: Int) -> UInt16 {
        let first = UInt16(data[offset])
        let second = UInt16(data[offset + 1])
        return encoding == .utf16LittleEndian
            ? first | (second << 8)
            : (first << 8) | second
    }

    private func cache(_ page: SourcePage, around index: Int) {
        cachedPages[page.index] = page
        cachedPages = cachedPages.filter { abs($0.key - index) <= 1 }
    }

    private func nearestLocation(atOrBefore requestedIndex: Int) -> (Int, SourcePageLocation) {
        let knownLocations = checkpointLocations.merging(recentLocations) { _, recent in recent }
        return knownLocations
            .filter { $0.key <= requestedIndex }
            .max { $0.key < $1.key }
            .map { ($0.key, $0.value) }
            ?? (0, checkpointLocations[0]!)
    }

    private func nextLocation(after page: SourcePage) -> SourcePageLocation {
        SourcePageLocation(
            offset: page.endOffset,
            startLine: page.startLine + Self.newlineCount(in: page.text),
            leadingContinuation: page.trailingContinuation
        )
    }

    private func rememberCheckpointIfNeeded(_ location: SourcePageLocation, at index: Int) {
        if index.isMultiple(of: Self.checkpointStride) {
            checkpointLocations[index] = location
        }
    }

    private func rememberRecent(_ location: SourcePageLocation, at index: Int) {
        recentLocations[index] = location
        recentLocationOrder.removeAll { $0 == index }
        recentLocationOrder.append(index)
        while recentLocationOrder.count > Self.maximumRecentLocations {
            let removedIndex = recentLocationOrder.removeFirst()
            recentLocations.removeValue(forKey: removedIndex)
        }
    }

    var indexedLocationCountForTesting: Int {
        lock.lock()
        defer { lock.unlock() }
        return Set(checkpointLocations.keys).union(recentLocations.keys).count
    }

    private static func prefix(_ text: String, maximumUTF16Units: Int) -> String {
        guard maximumUTF16Units > 0 else { return "" }
        var end = text.startIndex
        var consumed = 0
        while end < text.endIndex, consumed < maximumUTF16Units {
            let next = text.index(after: end)
            consumed += text[end..<next].utf16.count
            end = next
        }
        return String(text[..<end])
    }

    private func validateUnchanged() throws {
        let readableURL = try FileSystemService.validatedURL(fileURL, inside: rootURL)
        let values = try readableURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard Int64(values.fileSize ?? 0) == fileSize else { throw SourceFileError.fileChanged }
        if let modifiedAt, let current = values.contentModificationDate, current != modifiedAt {
            throw SourceFileError.fileChanged
        }
    }

    private static func detectEncoding(in probe: Data) throws -> (encoding: SourceTextEncoding, bomLength: UInt64) {
        if probe.starts(with: [0xEF, 0xBB, 0xBF]) { return (.utf8, 3) }
        if probe.starts(with: [0xFF, 0xFE]) { return (.utf16LittleEndian, 2) }
        if probe.starts(with: [0xFE, 0xFF]) { return (.utf16BigEndian, 2) }

        if likelyUTF16(probe, zeroOnEvenOffsets: false) { return (.utf16LittleEndian, 0) }
        if likelyUTF16(probe, zeroOnEvenOffsets: true) { return (.utf16BigEndian, 0) }

        var candidate = probe
        while String(data: candidate, encoding: .utf8) == nil, !candidate.isEmpty, probe.count - candidate.count < 4 {
            candidate.removeLast()
        }
        guard let sample = String(data: candidate, encoding: .utf8), isPlausibleText(sample) else {
            throw FileSystemError.unsupportedEncoding
        }
        return (.utf8, 0)
    }

    private static func likelyUTF16(_ data: Data, zeroOnEvenOffsets: Bool) -> Bool {
        guard data.count >= 8 else { return false }
        let pairs = min(data.count / 2, 2_048)
        var zeroCount = 0
        for pair in 0..<pairs {
            let index = pair * 2 + (zeroOnEvenOffsets ? 0 : 1)
            if data[index] == 0 { zeroCount += 1 }
        }
        return zeroCount * 3 > pairs * 2
    }

    private static func isPlausibleText(_ value: String) -> Bool {
        guard !value.isEmpty else { return true }
        var controls = 0
        var total = 0
        for scalar in value.unicodeScalars.prefix(8_192) {
            total += 1
            if scalar.value == 0 { return false }
            if scalar.value < 0x20, scalar != "\n", scalar != "\r", scalar != "\t" {
                controls += 1
            }
        }
        return controls * 100 <= max(1, total)
    }

    private static func detectShebangLanguage(
        in probe: Data,
        encoding: SourceTextEncoding,
        bomLength: UInt64
    ) -> SourceLanguage? {
        guard encoding == .utf8, probe.count > Int(bomLength) else { return nil }
        let payload = probe.dropFirst(Int(bomLength)).prefix(4_096)
        guard let firstLine = String(decoding: payload, as: UTF8.self)
            .split(whereSeparator: \Character.isNewline)
            .first,
            firstLine.hasPrefix("#!")
        else { return nil }

        let command = firstLine.dropFirst(2)
        let tokens = command.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard let executable = tokens.first else { return nil }

        let initialName = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        let interpreter: String
        if initialName == "env" {
            guard let envInterpreter = tokens.dropFirst().first(where: { !$0.hasPrefix("-") }) else {
                return nil
            }
            interpreter = URL(fileURLWithPath: envInterpreter).lastPathComponent.lowercased()
        } else {
            interpreter = initialName
        }

        if interpreter == "sh" || interpreter.hasPrefix("bash") ||
            interpreter.hasPrefix("zsh") || interpreter.hasPrefix("fish") {
            return .bash
        }
        if interpreter.hasPrefix("python") || interpreter.hasPrefix("pypy") { return .python }
        if interpreter == "node" || interpreter.hasPrefix("nodejs") || interpreter == "bun" {
            return .javascript
        }
        if interpreter == "deno" || interpreter == "tsx" { return .typescript }
        if interpreter.hasPrefix("ruby") { return .ruby }
        if interpreter.hasPrefix("perl") { return .perl }
        if interpreter.hasPrefix("php") { return .php }
        if interpreter.hasPrefix("lua") { return .lua }
        if interpreter == "swift" { return .swift }
        if interpreter == "rscript" { return .r }
        return nil
    }

    private static func read(from url: URL, offset: UInt64, count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }

    private static func newlineCount(in text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
    }
}

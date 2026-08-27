import Foundation

enum SourceTextEncoding: Equatable, Sendable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8: .utf8
        case .utf16LittleEndian: .utf16LittleEndian
        case .utf16BigEndian: .utf16BigEndian
        }
    }
}

struct SourcePageLocation: Sendable {
    let offset: UInt64
    let startLine: Int
    let leadingContinuation: Bool
}

struct SourcePage: @unchecked Sendable {
    let index: Int
    let text: String
    let startOffset: UInt64
    let endOffset: UInt64
    let startLine: Int
    let endLine: Int
    let leadingContinuation: Bool
    let trailingContinuation: Bool
    let hasPrevious: Bool
    let hasNext: Bool
}

struct SourceSearchMatch: Equatable, Sendable {
    let pageIndex: Int
    let range: NSRange
    let line: Int
}

enum DocumentSearchDirection: Equatable, Sendable {
    case previous
    case next
}

struct DocumentSearchRequest: Equatable, Sendable {
    let id: UUID
    let query: String
    let isCaseSensitive: Bool
    let direction: DocumentSearchDirection
}

struct DocumentSearchState: Equatable, Sendable {
    var isPresented = false
    var query = ""
    var isCaseSensitive = false
    var isSearching = false
    var match: SourceSearchMatch?
    var didWrap = false
    var didFail = false
    var failure: ReaderFailure?
}

struct RenderedSourcePage: @unchecked Sendable {
    let page: SourcePage
    let language: SourceLanguage
    let inferredLanguage: SourceLanguage
    let selectedRange: NSRange?
}

enum SourceViewportDirection: String, Hashable, Sendable {
    case previous
    case next
}

enum SourceViewportUpdateAction: String, Sendable {
    case prepend
    case append
    case replace
    case clearPending
    case releasePrevious
    case releaseNext
}

struct SourceViewportUpdate: @unchecked Sendable {
    let id = UUID()
    let action: SourceViewportUpdateAction
    let page: SourcePage
    let language: SourceLanguage
    let selectedRange: NSRange?
    let targetLine: Int?
}

struct SourceLineJumpState: Equatable, Sendable {
    var isPresented = false
    var input = ""
    var isResolving = false
    var didFail = false
    var failure: ReaderFailure?
}

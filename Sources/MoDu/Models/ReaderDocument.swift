import Foundation

struct OutlineItem: Identifiable, @unchecked Sendable {
    let id = UUID()
    let title: String
    let level: Int
    let anchor: String
}

enum RenderedDocumentContent: @unchecked Sendable {
    case styledHTML(String)
    case interactiveHTML(sourceHTML: String, fallbackHTML: String)
    case source(html: String, page: RenderedSourcePage)
    case image(String)

    var html: String {
        switch self {
        case .styledHTML(let html), .image(let html): html
        case .interactiveHTML(let sourceHTML, _): sourceHTML
        case .source(let html, _): html
        }
    }

    var interactiveHTMLFallback: String? {
        guard case .interactiveHTML(_, let fallbackHTML) = self else { return nil }
        return fallbackHTML
    }

    var renderingMode: ReaderDocumentRenderingMode {
        switch self {
        case .styledHTML: .styledDocument
        case .interactiveHTML: .interactiveHTML
        case .source: .sourceCode
        case .image: .image
        }
    }

    var sourcePage: RenderedSourcePage? {
        guard case .source(_, let page) = self else { return nil }
        return page
    }
}

struct RenderedDocument: @unchecked Sendable {
    let id = UUID()
    let content: RenderedDocumentContent
    let outline: [OutlineItem]
    let fileSize: Int64
    let modifiedAt: Date?

    var html: String { content.html }
    var renderingMode: ReaderDocumentRenderingMode { content.renderingMode }
    var sourcePage: RenderedSourcePage? { content.sourcePage }
    var interactiveHTMLFallback: String? { content.interactiveHTMLFallback }

    init(
        content: RenderedDocumentContent,
        outline: [OutlineItem],
        fileSize: Int64,
        modifiedAt: Date?
    ) {
        self.content = content
        self.outline = outline
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
    }
}

struct ScrollRequest: Equatable {
    let id = UUID()
    let anchor: String
}

enum ReaderDocumentRenderingMode: Equatable, Sendable {
    case styledDocument
    case interactiveHTML
    case sourceCode
    case image
}

enum ReaderDocumentState {
    case welcome
    case loading(URL)
    case loaded(URL, RenderedDocument)
    case unsupported(URL)
    case failed(URL?, ReaderFailure)
}

enum ReaderFailureOperation: String, Sendable {
    case documentLoad
    case sourcePaging
    case documentSearch
    case lineJump
    case webContentRecovery
}

enum ReaderFailureCategory: String, Sendable {
    case fileSystem
    case sourceFile
    case imageDocument
    case unknown
}

enum ReaderRecoveryAction: String, Sendable {
    case reloadDocument
    case retryOperation
}

struct ReaderFailure: Equatable, Sendable {
    let operation: ReaderFailureOperation
    let category: ReaderFailureCategory
    let message: String
    let recoveryAction: ReaderRecoveryAction

    init(error: Error, operation: ReaderFailureOperation) {
        self.operation = operation
        switch error {
        case is FileSystemError:
            category = .fileSystem
        case is SourceFileError:
            category = .sourceFile
        case is ImageDocumentError:
            category = .imageDocument
        default:
            category = .unknown
        }
        message = error.localizedDescription
        recoveryAction = operation == .documentLoad ? .reloadDocument : .retryOperation
    }
}

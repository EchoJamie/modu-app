import Foundation

struct OutlineItem: Identifiable, @unchecked Sendable {
    let id = UUID()
    let title: String
    let level: Int
    let anchor: String
}

struct RenderedMarkdown: @unchecked Sendable {
    let id = UUID()
    let html: String
    let outline: [OutlineItem]
    let fileSize: Int64
    let modifiedAt: Date?
    let renderingMode: ReaderDocumentRenderingMode

    init(
        html: String,
        outline: [OutlineItem],
        fileSize: Int64,
        modifiedAt: Date?,
        renderingMode: ReaderDocumentRenderingMode = .styledDocument
    ) {
        self.html = html
        self.outline = outline
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.renderingMode = renderingMode
    }
}

struct ScrollRequest: Equatable {
    let id = UUID()
    let anchor: String
}

enum ReaderDocumentRenderingMode: Sendable {
    case styledDocument
    case interactiveHTML
}

enum ReaderDocumentState {
    case welcome
    case loading(URL)
    case loaded(URL, RenderedMarkdown)
    case unsupported(URL)
    case failed(URL?, String)
}

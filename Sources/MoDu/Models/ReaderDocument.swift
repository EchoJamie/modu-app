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
}

struct ScrollRequest: Equatable {
    let id = UUID()
    let anchor: String
}

enum ReaderDocumentState {
    case welcome
    case loading(URL)
    case loaded(URL, RenderedMarkdown)
    case unsupported(URL)
    case failed(URL?, String)
}

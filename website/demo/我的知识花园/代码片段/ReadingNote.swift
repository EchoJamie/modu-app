import Foundation

struct ReadingNote {
    let title: String
    let content: String

    var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

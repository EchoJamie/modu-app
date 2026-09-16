import AppKit
import SwiftUI

/// Only the empty space in the custom titlebar starts a window drag.
struct WindowTitlebarDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> TitlebarDragView {
        TitlebarDragView()
    }

    func updateNSView(_ nsView: TitlebarDragView, context: Context) {}
}

final class TitlebarDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize":
                window.performMiniaturize(nil)
            case "None":
                break
            default:
                window.performZoom(nil)
            }
        } else {
            window.performDrag(with: event)
        }
    }
}

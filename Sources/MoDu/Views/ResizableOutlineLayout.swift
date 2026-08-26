import AppKit
import SwiftUI

struct ResizableOutlineLayout<Content: View, Outline: View>: View {
    @Binding private var preferredOutlineWidth: CGFloat

    private let outlineIsVisible: Bool
    private let minimumContentWidth: CGFloat
    private let minimumOutlineWidth: CGFloat
    private let maximumOutlineWidth: CGFloat
    private let dividerColor: Color
    private let onOutlineWidthCommit: (CGFloat) -> Void
    private let content: Content
    private let outline: Outline

    init(
        outlineIsVisible: Bool,
        minimumContentWidth: CGFloat,
        preferredOutlineWidth: Binding<CGFloat>,
        minimumOutlineWidth: CGFloat,
        maximumOutlineWidth: CGFloat,
        dividerColor: Color,
        onOutlineWidthCommit: @escaping (CGFloat) -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder outline: () -> Outline
    ) {
        self.outlineIsVisible = outlineIsVisible
        self.minimumContentWidth = minimumContentWidth
        _preferredOutlineWidth = preferredOutlineWidth
        self.minimumOutlineWidth = minimumOutlineWidth
        self.maximumOutlineWidth = maximumOutlineWidth
        self.dividerColor = dividerColor
        self.onOutlineWidthCommit = onOutlineWidthCommit
        self.content = content()
        self.outline = outline()
    }

    var body: some View {
        GeometryReader { geometry in
            let availableMaximum = maximumAvailableOutlineWidth(
                totalWidth: geometry.size.width
            )
            let displayedWidth = min(
                max(preferredOutlineWidth, minimumOutlineWidth),
                availableMaximum
            )

            HStack(spacing: 0) {
                content
                    .frame(
                        minWidth: minimumContentWidth,
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )

                if outlineIsVisible {
                    OutlineResizeHandle(
                        preferredWidth: $preferredOutlineWidth,
                        displayedWidth: displayedWidth,
                        minimumWidth: minimumOutlineWidth,
                        maximumWidth: availableMaximum,
                        dividerColor: dividerColor,
                        onCommit: onOutlineWidthCommit
                    )

                    outline
                        .frame(width: displayedWidth)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func maximumAvailableOutlineWidth(totalWidth: CGFloat) -> CGFloat {
        let available = totalWidth
            - minimumContentWidth
            - OutlineResizeHandle.hitWidth
        return min(maximumOutlineWidth, max(minimumOutlineWidth, available))
    }
}

private struct OutlineResizeHandle: View {
    static let hitWidth: CGFloat = 9

    @Binding var preferredWidth: CGFloat
    let displayedWidth: CGFloat
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat
    let dividerColor: Color
    let onCommit: (CGFloat) -> Void

    @State private var dragStartWidth: CGFloat?
    @State private var dragStartPointerX: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: Self.hitWidth)
            .overlay {
                Rectangle()
                    .fill(dividerColor.opacity(0.75))
                    .frame(width: 1)
            }
            .background(HorizontalResizeCursorArea())
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = displayedWidth
                            dragStartPointerX = value.startLocation.x
                        }
                        guard let dragStartWidth, let dragStartPointerX else { return }
                        preferredWidth = OutlineResizeMath.width(
                            startWidth: dragStartWidth,
                            startPointerX: dragStartPointerX,
                            currentPointerX: value.location.x,
                            minimumWidth: minimumWidth,
                            maximumWidth: maximumWidth
                        )
                        NSCursor.resizeLeftRight.set()
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        dragStartPointerX = nil
                        NSCursor.resizeLeftRight.set()
                        onCommit(preferredWidth)
                    }
            )
            .onDisappear {
                NSCursor.arrow.set()
                if dragStartWidth != nil {
                    dragStartWidth = nil
                    dragStartPointerX = nil
                    onCommit(preferredWidth)
                }
            }
            .help(L10n.string(.outlineResizeHelp))
            .accessibilityLabel(L10n.string(.outlineResizeAccessibility))
    }
}

enum OutlineResizeMath {
    static func width(
        startWidth: CGFloat,
        startPointerX: CGFloat,
        currentPointerX: CGFloat,
        minimumWidth: CGFloat,
        maximumWidth: CGFloat
    ) -> CGFloat {
        let pointerDelta = currentPointerX - startPointerX
        return min(max(startWidth - pointerDelta, minimumWidth), maximumWidth)
    }
}

private struct HorizontalResizeCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeCursorTrackingView {
        ResizeCursorTrackingView(frame: .zero)
    }

    func updateNSView(_ nsView: ResizeCursorTrackingView, context: Context) {
        nsView.updateTrackingAreas()
    }
}

private final class ResizeCursorTrackingView: NSView {
    private var cursorTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

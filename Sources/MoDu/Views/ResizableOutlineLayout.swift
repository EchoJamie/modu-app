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

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: Self.hitWidth)
            .overlay {
                Rectangle()
                    .fill(dividerColor.opacity(0.75))
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = displayedWidth
                        }
                        guard let dragStartWidth else { return }
                        preferredWidth = min(
                            max(dragStartWidth - value.translation.width, minimumWidth),
                            maximumWidth
                        )
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        onCommit(preferredWidth)
                    }
            )
            .onHover { isHovering in
                (isHovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
            }
            .onDisappear {
                NSCursor.arrow.set()
                if dragStartWidth != nil {
                    dragStartWidth = nil
                    onCommit(preferredWidth)
                }
            }
            .help("拖动调整大纲宽度")
            .accessibilityLabel("调整大纲宽度")
    }
}

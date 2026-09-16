import AppKit
import SwiftUI

struct ResizableSidePanelLayout<Content: View, Panel: View>: View {
    @Binding private var preferredPanelWidth: CGFloat

    private let panelIsVisible: Bool
    private let edge: HorizontalEdge
    private let minimumContentWidth: CGFloat
    private let minimumPanelWidth: CGFloat
    private let maximumPanelWidth: CGFloat
    private let dividerColor: Color
    private let onPanelWidthCommit: (CGFloat) -> Void
    private let content: Content
    private let panel: Panel

    init(
        panelIsVisible: Bool,
        edge: HorizontalEdge,
        minimumContentWidth: CGFloat,
        preferredPanelWidth: Binding<CGFloat>,
        minimumPanelWidth: CGFloat,
        maximumPanelWidth: CGFloat,
        dividerColor: Color,
        onPanelWidthCommit: @escaping (CGFloat) -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder panel: () -> Panel
    ) {
        self.panelIsVisible = panelIsVisible
        self.edge = edge
        self.minimumContentWidth = minimumContentWidth
        _preferredPanelWidth = preferredPanelWidth
        self.minimumPanelWidth = minimumPanelWidth
        self.maximumPanelWidth = maximumPanelWidth
        self.dividerColor = dividerColor
        self.onPanelWidthCommit = onPanelWidthCommit
        self.content = content()
        self.panel = panel()
    }

    var body: some View {
        GeometryReader { geometry in
            let availableMaximum = maximumAvailablePanelWidth(
                totalWidth: geometry.size.width
            )
            let displayedWidth = min(
                max(preferredPanelWidth, minimumPanelWidth),
                availableMaximum
            )

            HStack(spacing: 0) {
                if edge == .leading {
                    sizedPanel(width: displayedWidth, maximum: availableMaximum)
                }

                content
                    .frame(
                        minWidth: minimumContentWidth,
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )

                if edge == .trailing {
                    sizedPanel(width: displayedWidth, maximum: availableMaximum)
                }
            }
        }
    }

    private func sizedPanel(width: CGFloat, maximum: CGFloat) -> some View {
        panel
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .overlay(alignment: edge == .leading ? .trailing : .leading) {
                SidePanelResizeHandle(
                    preferredWidth: $preferredPanelWidth,
                    edge: edge,
                    displayedWidth: width,
                    minimumWidth: minimumPanelWidth,
                    maximumWidth: maximum,
                    dividerColor: dividerColor,
                    onCommit: onPanelWidthCommit
                )
            }
            // Keep selection and scroll state alive while the panel is collapsed.
            .frame(width: panelIsVisible ? width : 0)
            .clipped()
            .disabled(!panelIsVisible)
            .allowsHitTesting(panelIsVisible)
            .accessibilityHidden(!panelIsVisible)
    }

    private func maximumAvailablePanelWidth(totalWidth: CGFloat) -> CGFloat {
        let available = totalWidth
            - minimumContentWidth
        return min(maximumPanelWidth, max(minimumPanelWidth, available))
    }
}

private struct SidePanelResizeHandle: View {
    static let hitWidth: CGFloat = 9

    @Binding var preferredWidth: CGFloat
    let edge: HorizontalEdge
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
            .overlay(alignment: edge == .leading ? .trailing : .leading) {
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
                        preferredWidth = SidePanelResizeMath.width(
                            startWidth: dragStartWidth,
                            startPointerX: dragStartPointerX,
                            currentPointerX: value.location.x,
                            minimumWidth: minimumWidth,
                            maximumWidth: maximumWidth,
                            edge: edge
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
            .help(L10n.string(edge == .leading ? .sidebarResizeHelp : .outlineResizeHelp))
            .accessibilityLabel(L10n.string(edge == .leading ? .sidebarResizeAccessibility : .outlineResizeAccessibility))
    }
}

enum SidePanelResizeMath {
    static func width(
        startWidth: CGFloat,
        startPointerX: CGFloat,
        currentPointerX: CGFloat,
        minimumWidth: CGFloat,
        maximumWidth: CGFloat,
        edge: HorizontalEdge = .trailing
    ) -> CGFloat {
        let pointerDelta = currentPointerX - startPointerX
        let width = startWidth + (edge == .leading ? pointerDelta : -pointerDelta)
        return min(max(width, minimumWidth), maximumWidth)
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

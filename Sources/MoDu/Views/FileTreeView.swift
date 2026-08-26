import AppKit
import SwiftUI

struct FileTreeView: View {
    @EnvironmentObject private var model: ReaderViewModel
    @State private var focusedNodeID: String?
    @State private var focusRequestID = UUID()
    @State private var editingNodeID: String?
    @State private var renameDraft = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.rootNodes) { node in
                        FileTreeRow(
                            node: node,
                            depth: 0,
                            focusedNodeID: $focusedNodeID,
                            editingNodeID: editingNodeID,
                            renameDraft: $renameDraft,
                            onFocusNode: focusNode,
                            onBeginRename: beginRename,
                            onCommitRename: commitRename,
                            onCancelRename: cancelRename
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: focusedNodeID) { nodeID in
                guard let nodeID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(nodeID, anchor: .center)
                }
            }
        }
        .background {
            FileTreeKeyboardMonitor(
                focusedNodeID: focusedNodeID,
                focusRequestID: focusRequestID,
                isRenaming: editingNodeID != nil,
                onRename: beginRenamingFocusedNode,
                onCopy: copyFocusedNodePath,
                onOpenInOtherPane: openFocusedNodeInOtherPane,
                onMoveUp: { moveFocus(by: -1) },
                onMoveDown: { moveFocus(by: 1) },
                onMoveLeft: moveFocusLeft,
                onMoveRight: moveFocusRight,
                onFocusLost: {
                    focusedNodeID = nil
                }
            )
        }
    }

    private func focusNode(_ node: FileNode) {
        focusedNodeID = node.id
        focusRequestID = UUID()
    }

    private func beginRenamingFocusedNode() {
        guard
            let focusedNodeID,
            let node = findNode(withID: focusedNodeID, in: model.rootNodes)
        else { return }
        beginRename(node)
    }

    private func copyFocusedNodePath() {
        guard
            let focusedNodeID,
            let node = findNode(withID: focusedNodeID, in: model.rootNodes)
        else { return }
        model.copyAbsolutePath(of: node)
    }

    private func openFocusedNodeInOtherPane() -> Bool {
        guard
            let focusedNodeID,
            let node = findNode(withID: focusedNodeID, in: model.rootNodes),
            !node.isDirectory
        else { return false }
        model.openInOtherPane(node)
        return true
    }

    private func moveFocus(by offset: Int) -> Bool {
        guard
            let focusedNodeID,
            let currentIndex = visibleNodes.firstIndex(where: { $0.id == focusedNodeID })
        else { return false }

        let targetIndex = min(max(currentIndex + offset, 0), visibleNodes.count - 1)
        if targetIndex != currentIndex {
            focusNode(visibleNodes[targetIndex])
        }
        return true
    }

    private func moveFocusLeft() -> Bool {
        guard
            let focusedNodeID,
            let node = findNode(withID: focusedNodeID, in: model.rootNodes)
        else { return false }

        if node.isDirectory, node.isExpanded {
            model.setExpanded(node, expanded: false)
        } else if let parent = findParent(of: focusedNodeID, in: model.rootNodes) {
            focusNode(parent)
        }
        return true
    }

    private func moveFocusRight() -> Bool {
        guard
            let focusedNodeID,
            let node = findNode(withID: focusedNodeID, in: model.rootNodes)
        else { return false }

        guard node.isDirectory else { return true }
        if !node.isExpanded {
            model.setExpanded(node, expanded: true)
        } else if let firstChild = node.children?.first {
            focusNode(firstChild)
        }
        return true
    }

    private var visibleNodes: [FileNode] {
        flattenedVisibleNodes(in: model.rootNodes)
    }

    private func flattenedVisibleNodes(in nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            result.append(node)
            if node.isExpanded, let children = node.children {
                result.append(contentsOf: flattenedVisibleNodes(in: children))
            }
        }
        return result
    }

    private func findParent(of id: String, in nodes: [FileNode], parent: FileNode? = nil) -> FileNode? {
        for node in nodes {
            if node.id == id { return parent }
            if let children = node.children,
               let match = findParent(of: id, in: children, parent: node) {
                return match
            }
        }
        return nil
    }

    private func beginRename(_ node: FileNode) {
        model.dismissFileOperationError()
        focusedNodeID = node.id
        renameDraft = node.name
        editingNodeID = node.id
    }

    private func commitRename(_ node: FileNode) {
        guard editingNodeID == node.id else { return }
        guard let renamedURL = model.rename(node, to: renameDraft) else { return }

        editingNodeID = nil
        renameDraft = ""
        focusedNodeID = renamedURL.standardizedFileURL.path
        focusRequestID = UUID()
    }

    private func cancelRename(_ node: FileNode) {
        guard editingNodeID == node.id else { return }
        editingNodeID = nil
        renameDraft = ""
        focusedNodeID = node.id
        focusRequestID = UUID()
    }

    private func findNode(withID id: String, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if let children = node.children,
               let match = findNode(withID: id, in: children) {
                return match
            }
        }
        return nil
    }
}

private struct FileTreeRow: View {
    @EnvironmentObject private var model: ReaderViewModel
    @ObservedObject var node: FileNode
    let depth: Int
    @Binding var focusedNodeID: String?
    let editingNodeID: String?
    @Binding var renameDraft: String
    let onFocusNode: (FileNode) -> Void
    let onBeginRename: (FileNode) -> Void
    let onCommitRename: (FileNode) -> Void
    let onCancelRename: (FileNode) -> Void
    @FocusState private var renameFieldIsFocused: Bool

    private var theme: ResolvedReaderTheme { model.resolvedTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if editingNodeID == node.id {
                rowContent
                    .padding(.leading, CGFloat(depth) * 15)
                    .onAppear {
                        DispatchQueue.main.async {
                            renameFieldIsFocused = true
                        }
                    }
            } else {
                Button {
                    onFocusNode(node)
                    model.select(node)
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding(.leading, CGFloat(depth) * 15)
                .contextMenu {
                    if !node.isDirectory {
                        Button {
                            model.openInOtherPane(node)
                        } label: {
                            contextMenuLabel(L10n.string(.fileTreeOpenOtherPane), shortcut: "⌥↩")
                        }

                        Divider()
                    }

                    Button {
                        onBeginRename(node)
                    } label: {
                        contextMenuLabel(
                            L10n.string(.fileTreeRename),
                            shortcut: L10n.string(.fileTreeReturnKey)
                        )
                    }

                    Button {
                        model.copyAbsolutePath(of: node)
                    } label: {
                        contextMenuLabel(L10n.string(.fileTreeCopyPath), shortcut: "⌘C")
                    }
                }
            }

            if node.isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileTreeRow(
                        node: child,
                        depth: depth + 1,
                        focusedNodeID: $focusedNodeID,
                        editingNodeID: editingNodeID,
                        renameDraft: $renameDraft,
                        onFocusNode: onFocusNode,
                        onBeginRename: onBeginRename,
                        onCommitRename: onCommitRename,
                        onCancelRename: onCancelRename
                    )
                }
            }
        }
        .id(node.id)
    }

    private var rowContent: some View {
        HStack(spacing: 7) {
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                    .foregroundStyle(theme.secondary)
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12, height: 1)
            }

            Image(systemName: node.iconName)
                .font(.system(size: 13, weight: node.isPreviewable ? .medium : .regular))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            if editingNodeID == node.id {
                TextField(L10n.string(.fileTreeNamePlaceholder), text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: node.isPreviewable ? .medium : .regular))
                    .foregroundStyle(theme.foreground)
                    .focused($renameFieldIsFocused)
                    .onSubmit {
                        onCommitRename(node)
                    }
                    .onExitCommand {
                        onCancelRename(node)
                    }
            } else {
                Text(node.name)
                    .font(.system(size: 13, weight: node.isPreviewable ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(
                        node.isPreviewable || node.isDirectory
                            ? theme.foreground
                            : theme.secondary
                    )
            }

            Spacer(minLength: 4)

            if node.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 7)
        .frame(height: 29)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var rowBackground: Color {
        if editingNodeID == node.id || focusedNodeID == node.id {
            return theme.accent.opacity(theme.isDark ? 0.28 : 0.17)
        }
        return .clear
    }

    private func contextMenuLabel(_ title: String, shortcut: String) -> some View {
        HStack(spacing: 24) {
            Text(title)
            Spacer(minLength: 12)
            Text(shortcut)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 190, alignment: .leading)
    }

    private var iconColor: Color {
        if node.isDirectory { return theme.accent.opacity(0.82) }
        if node.isPreviewable { return theme.foreground.opacity(0.84) }
        return theme.secondary.opacity(0.7)
    }
}

private struct FileTreeKeyboardMonitor: NSViewRepresentable {
    let focusedNodeID: String?
    let focusRequestID: UUID
    let isRenaming: Bool
    let onRename: () -> Void
    let onCopy: () -> Void
    let onOpenInOtherPane: () -> Bool
    let onMoveUp: () -> Bool
    let onMoveDown: () -> Bool
    let onMoveLeft: () -> Bool
    let onMoveRight: () -> Bool
    let onFocusLost: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = FileTreeFocusView(frame: .zero)
        view.onFocusLost = onFocusLost
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.focusedNodeID = focusedNodeID
        context.coordinator.isRenaming = isRenaming
        context.coordinator.onRename = onRename
        context.coordinator.onCopy = onCopy
        context.coordinator.onOpenInOtherPane = onOpenInOtherPane
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onMoveLeft = onMoveLeft
        context.coordinator.onMoveRight = onMoveRight
        (nsView as? FileTreeFocusView)?.onFocusLost = onFocusLost
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            guard focusedNodeID != nil, !isRenaming else { return }
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView else { return }
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        (nsView as? FileTreeFocusView)?.onFocusLost = nil
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        weak var view: NSView?
        var focusedNodeID: String?
        var isRenaming = false
        var onRename: () -> Void = {}
        var onCopy: () -> Void = {}
        var onOpenInOtherPane: () -> Bool = { false }
        var onMoveUp: () -> Bool = { false }
        var onMoveDown: () -> Bool = { false }
        var onMoveLeft: () -> Bool = { false }
        var onMoveRight: () -> Bool = { false }
        var lastFocusRequestID: UUID?
        private var eventMonitor: Any?

        func attach(to view: NSView) {
            self.view = view
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard
                !isRenaming,
                focusedNodeID != nil,
                let view,
                event.window === view.window,
                view.window?.firstResponder === view
            else { return event }

            let relevantModifiers = event.modifierFlags.intersection([
                .command,
                .option,
                .control,
                .shift
            ])

            if event.keyCode == 36 || event.keyCode == 76 {
                if !event.isARepeat, relevantModifiers == .option, onOpenInOtherPane() {
                    return nil
                }
                if !event.isARepeat, relevantModifiers.isEmpty {
                    onRename()
                    return nil
                }
            }

            if event.charactersIgnoringModifiers?.lowercased() == "c",
               !event.isARepeat,
               relevantModifiers == .command {
                onCopy()
                return nil
            }

            if relevantModifiers.isEmpty {
                let handled: Bool
                switch event.keyCode {
                case 123: handled = onMoveLeft()
                case 124: handled = onMoveRight()
                case 125: handled = onMoveDown()
                case 126: handled = onMoveUp()
                default: handled = false
                }
                if handled { return nil }
            }

            return event
        }

        deinit {
            stopMonitoring()
        }
    }
}

private final class FileTreeFocusView: NSView {
    var onFocusLost: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { onFocusLost?() }
        return didResign
    }
}

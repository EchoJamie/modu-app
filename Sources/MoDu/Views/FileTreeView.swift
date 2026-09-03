import AppKit
import SwiftUI

struct FileTreeView: View {
    @EnvironmentObject private var model: ReaderViewModel
    @State private var selectedNodeID: String?
    @State private var treeHasKeyboardFocus = false
    @State private var focusRequestID = UUID()
    @State private var scrollRequestID = UUID()
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
                            selectedNodeID: $selectedNodeID,
                            selectionIsActive: treeHasKeyboardFocus,
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
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                restoreTreeFocusIfNeeded()
            })
            .onChange(of: scrollRequestID) { _ in
                guard let selectedNodeID else { return }
                proxy.scrollTo(selectedNodeID)
            }
        }
        .background {
            FileTreeKeyboardMonitor(
                selectedNodeID: selectedNodeID,
                focusRequestID: focusRequestID,
                isRenaming: editingNodeID != nil,
                onRename: beginRenamingFocusedNode,
                onCopy: copyFocusedNodePath,
                onOpen: openFocusedNode,
                onOpenInOtherPane: openFocusedNodeInOtherPane,
                onMoveUp: { moveFocus(by: -1) },
                onMoveDown: { moveFocus(by: 1) },
                onMoveLeft: moveFocusLeft,
                onMoveRight: moveFocusRight,
                onFocusChanged: { hasFocus in
                    treeHasKeyboardFocus = hasFocus
                }
            )
        }
        .onAppear {
            applySelectionRequest(model.fileTreeSelectionRequest)
        }
        .onChange(of: model.fileTreeSelectionRequest) { request in
            applySelectionRequest(request)
        }
    }

    private func focusNode(_ node: FileNode) {
        selectedNodeID = node.id
        focusRequestID = UUID()
    }

    private func restoreTreeFocusIfNeeded() {
        guard
            !treeHasKeyboardFocus,
            selectedNodeID != nil,
            editingNodeID == nil
        else { return }
        focusRequestID = UUID()
    }

    private func focusAndRevealNode(_ node: FileNode) {
        focusNode(node)
        scrollRequestID = UUID()
    }

    private func applySelectionRequest(_ request: FileTreeSelectionRequest?) {
        guard let request else { return }
        editingNodeID = nil
        renameDraft = ""

        switch request.target {
        case .none:
            selectedNodeID = nil
        case .firstRootNode:
            selectedNodeID = model.rootNodes.first?.id
            if selectedNodeID != nil {
                scrollRequestID = UUID()
            }
        case .url(let url):
            selectedNodeID = findNode(
                withID: url.standardizedFileURL.path,
                in: model.rootNodes
            )?.id
            if selectedNodeID != nil {
                scrollRequestID = UUID()
            }
        }
    }

    private func beginRenamingFocusedNode() -> Bool {
        guard
            let selectedNodeID,
            let node = findNode(withID: selectedNodeID, in: model.rootNodes)
        else { return false }
        beginRename(node)
        return true
    }

    private func copyFocusedNodePath() -> Bool {
        guard
            let selectedNodeID,
            let node = findNode(withID: selectedNodeID, in: model.rootNodes)
        else { return false }
        model.copyAbsolutePath(of: node)
        return true
    }

    private func openFocusedNodeInOtherPane() -> Bool {
        guard
            let selectedNodeID,
            let node = findNode(withID: selectedNodeID, in: model.rootNodes),
            !node.isDirectory
        else { return false }
        model.openInOtherPane(node)
        return true
    }

    private func openFocusedNode() -> Bool {
        guard
            let selectedNodeID,
            let node = findNode(withID: selectedNodeID, in: model.rootNodes),
            !node.isDirectory
        else { return false }
        model.select(node)
        return true
    }

    private func moveFocus(by offset: Int) -> Bool {
        guard
            let selectedNodeID,
            let currentIndex = visibleNodes.firstIndex(where: { $0.id == selectedNodeID })
        else { return false }

        let targetIndex = min(max(currentIndex + offset, 0), visibleNodes.count - 1)
        if targetIndex != currentIndex {
            focusAndRevealNode(visibleNodes[targetIndex])
        }
        return true
    }

    private func moveFocusLeft() -> Bool {
        guard
            let selectedNodeID,
            let node = findNode(withID: selectedNodeID, in: model.rootNodes)
        else { return false }

        if node.isDirectory, node.isExpanded {
            model.setExpanded(node, expanded: false)
        } else if let parent = findParent(of: selectedNodeID, in: model.rootNodes) {
            focusAndRevealNode(parent)
        }
        return true
    }

    private func moveFocusRight() -> Bool {
        guard
            let selectedNodeID,
            let node = findNode(withID: selectedNodeID, in: model.rootNodes)
        else { return false }

        guard node.isDirectory else { return true }
        if !node.isExpanded {
            model.setExpanded(node, expanded: true)
        } else if let firstChild = node.children?.first {
            focusAndRevealNode(firstChild)
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
        selectedNodeID = node.id
        renameDraft = node.name
        editingNodeID = node.id
    }

    private func commitRename(_ node: FileNode) {
        guard editingNodeID == node.id else { return }
        guard let renamedURL = model.rename(node, to: renameDraft) else { return }

        editingNodeID = nil
        renameDraft = ""
        selectedNodeID = renamedURL.standardizedFileURL.path
        focusRequestID = UUID()
    }

    private func cancelRename(_ node: FileNode) {
        guard editingNodeID == node.id else { return }
        editingNodeID = nil
        renameDraft = ""
        selectedNodeID = node.id
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
    @Binding var selectedNodeID: String?
    let selectionIsActive: Bool
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
                rowContent
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onFocusNode(node)
                    }
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        onFocusNode(node)
                        model.select(node)
                    })
                    .padding(.leading, CGFloat(depth) * 15)
                    .contextMenu {
                        if !node.isDirectory {
                            Button {
                                onFocusNode(node)
                                model.openInOtherPane(node)
                            } label: {
                                contextMenuLabel(L10n.string(.fileTreeOpenOtherPane), shortcut: "⌥↩")
                            }

                            Divider()
                        }

                        Button {
                            onFocusNode(node)
                            onBeginRename(node)
                        } label: {
                            contextMenuLabel(
                                L10n.string(.fileTreeRename),
                                shortcut: L10n.string(.fileTreeReturnKey)
                            )
                        }

                        Button {
                            onFocusNode(node)
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
                        selectedNodeID: $selectedNodeID,
                        selectionIsActive: selectionIsActive,
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
                Button {
                    onFocusNode(node)
                    model.setExpanded(node, expanded: !node.isExpanded)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                        .foregroundStyle(theme.secondary)
                        .frame(width: 12, height: 24)
                }
                .buttonStyle(.plain)
                .focusable(false)
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
        if editingNodeID == node.id {
            return theme.accent.opacity(theme.isDark ? 0.28 : 0.17)
        }
        if selectedNodeID == node.id {
            if selectionIsActive {
                return theme.accent.opacity(theme.isDark ? 0.28 : 0.17)
            }
            return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                .opacity(theme.isDark ? 0.72 : 0.62)
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
    let selectedNodeID: String?
    let focusRequestID: UUID
    let isRenaming: Bool
    let onRename: () -> Bool
    let onCopy: () -> Bool
    let onOpen: () -> Bool
    let onOpenInOtherPane: () -> Bool
    let onMoveUp: () -> Bool
    let onMoveDown: () -> Bool
    let onMoveLeft: () -> Bool
    let onMoveRight: () -> Bool
    let onFocusChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = FileTreeFocusView(frame: .zero)
        view.onFocusChanged = onFocusChanged
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.selectedNodeID = selectedNodeID
        context.coordinator.isRenaming = isRenaming
        context.coordinator.onRename = onRename
        context.coordinator.onCopy = onCopy
        context.coordinator.onOpen = onOpen
        context.coordinator.onOpenInOtherPane = onOpenInOtherPane
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onMoveLeft = onMoveLeft
        context.coordinator.onMoveRight = onMoveRight
        if let focusView = nsView as? FileTreeFocusView {
            focusView.onFocusChanged = onFocusChanged
            context.coordinator.attach(to: focusView)
        }
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            guard selectedNodeID != nil, !isRenaming else { return }
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView else { return }
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        guard let focusView = nsView as? FileTreeFocusView else { return }
        focusView.onFocusChanged = nil
        focusView.onKeyEvent = nil
    }

    final class Coordinator {
        var selectedNodeID: String?
        var isRenaming = false
        var onRename: () -> Bool = { false }
        var onCopy: () -> Bool = { false }
        var onOpen: () -> Bool = { false }
        var onOpenInOtherPane: () -> Bool = { false }
        var onMoveUp: () -> Bool = { false }
        var onMoveDown: () -> Bool = { false }
        var onMoveLeft: () -> Bool = { false }
        var onMoveRight: () -> Bool = { false }
        var lastFocusRequestID: UUID?
        private var lastHandledSingleFireKeyCode: UInt16?
        private var lastHandledSingleFireModifiers: NSEvent.ModifierFlags = []

        func attach(to view: FileTreeFocusView) {
            view.onKeyEvent = { [weak self] event in
                self?.handle(event) ?? false
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard !isRenaming else { return false }

            let relevantModifiers = event.modifierFlags.intersection([
                .command,
                .option,
                .control,
                .shift
            ])

            if event.keyCode == 36 || event.keyCode == 76 {
                if relevantModifiers == .option {
                    return handleSingleFire(
                        event,
                        modifiers: relevantModifiers,
                        action: onOpenInOtherPane
                    )
                }
                if relevantModifiers.isEmpty {
                    return handleSingleFire(
                        event,
                        modifiers: relevantModifiers,
                        action: onRename
                    )
                }
            }

            if event.keyCode == 49, relevantModifiers.isEmpty {
                return handleSingleFire(
                    event,
                    modifiers: relevantModifiers,
                    action: onOpen
                )
            }

            if event.charactersIgnoringModifiers?.lowercased() == "c",
               relevantModifiers == .command {
                return handleSingleFire(
                    event,
                    modifiers: relevantModifiers,
                    action: onCopy
                )
            }

            if relevantModifiers.isEmpty {
                switch event.keyCode {
                case 123:
                    return onMoveLeft()
                case 124:
                    return onMoveRight()
                case 125:
                    return onMoveDown()
                case 126:
                    return onMoveUp()
                default:
                    break
                }
            }

            return false
        }

        private func handleSingleFire(
            _ event: NSEvent,
            modifiers: NSEvent.ModifierFlags,
            action: () -> Bool
        ) -> Bool {
            if event.isARepeat {
                return lastHandledSingleFireKeyCode == event.keyCode
                    && lastHandledSingleFireModifiers == modifiers
            }

            let handled = action()
            lastHandledSingleFireKeyCode = handled ? event.keyCode : nil
            lastHandledSingleFireModifiers = handled ? modifiers : []
            return handled
        }
    }
}

final class FileTreeFocusView: NSView {
    var onFocusChanged: ((Bool) -> Void)?
    var onKeyEvent: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { onFocusChanged?(true) }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { onFocusChanged?(false) }
        return didResign
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        if onKeyEvent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyEvent?(event) == true { return }
        super.keyDown(with: event)
    }
}

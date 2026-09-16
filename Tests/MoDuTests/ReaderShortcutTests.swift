import AppKit
import SwiftUI
import Testing
@testable import MoDu

@Suite("Reader keyboard shortcuts")
struct ReaderShortcutTests {
    @Test("Custom bindings survive restart, reject conflicts, and reset together")
    @MainActor
    func persistenceAndConflicts() throws {
        _ = NSApplication.shared
        let suiteName = "ReaderShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = ApplicationState(defaults: defaults, restoreRecentWorkspaces: false)
        let custom = ReaderShortcut(key: "j", modifiers: [.command, .option])
        #expect(state.shortcut(for: .toggleSidebar) == ReaderShortcut(key: "b"))
        #expect(state.shortcut(for: .toggleOutline) == ReaderShortcut(key: "b", modifiers: [.command, .shift]))
        #expect(state.setShortcut(custom, for: .toggleSidebar) == nil)
        #expect(state.setShortcut(custom, for: .toggleOutline) != nil)
        #expect(state.shortcut(for: .toggleOutline) == ReaderShortcutAction.toggleOutline.defaultBinding)
        #expect(state.setShortcut(ReaderShortcut(key: "a", modifiers: []), for: .toggleSidebar) != nil)
        #expect(state.shortcut(for: .toggleSidebar) == custom)

        let restored = ApplicationState(defaults: defaults, restoreRecentWorkspaces: false)
        #expect(restored.shortcut(for: .toggleSidebar) == custom)
        restored.resetShortcuts()
        let reset = ApplicationState(defaults: defaults, restoreRecentWorkspaces: false)
        for action in ReaderShortcutAction.allCases {
            #expect(reset.shortcut(for: action) == action.defaultBinding)
        }
    }

    @Test("Menu conflicts include disabled native commands and normalized Shift keys")
    @MainActor
    func menuConflicts() {
        let menu = NSMenu()
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let copy = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "c")
        copy.keyEquivalentModifierMask = .command
        copy.isEnabled = false
        submenu.addItem(copy)
        let redo = NSMenuItem(title: "Redo", action: nil, keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = .command
        submenu.addItem(redo)
        edit.submenu = submenu
        menu.addItem(edit)
        #expect(ReaderShortcut(key: "c").conflictingMenuItem(in: menu) == "Copy")
        #expect(ReaderShortcut(key: "z", modifiers: [.command, .shift]).conflictingMenuItem(in: menu) == "Redo")
        #expect(ReaderShortcut(key: "b").conflictingMenuItem(in: menu) == nil)
    }

    @Test("Sidebar toggling stays independent of the outline and other windows")
    @MainActor
    func sidebarState() {
        _ = NSApplication.shared
        let first = ReaderViewModel(restorePersistedState: false)
        let second = ReaderViewModel(restorePersistedState: false)
        first.toggleSidebar()
        #expect(!first.sidebarIsVisible)
        #expect(second.sidebarIsVisible)
        #expect(first.outlineIsVisible)
        first.toggleSidebar()
        #expect(first.sidebarIsVisible)
        first.outlineIsVisible = false
        first.toggleSidebar()
        #expect(!first.sidebarIsVisible)
        #expect(!first.outlineIsVisible)
        #expect(second.sidebarIsVisible)
    }

    @Test("Recorder owns shortcuts only during focused capture and Escape cancels")
    @MainActor
    func recorderFocusAndCancellation() throws {
        _ = NSApplication.shared
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let recorder = ShortcutRecorderButton()
        let textView = NSTextView(frame: NSRect(x: 160, y: 0, width: 140, height: 100))
        content.addSubview(recorder)
        content.addSubview(textView)
        let window = NSWindow(contentRect: content.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = content
        var recorded: [ReaderShortcut] = []
        recorder.onRecord = { recorded.append($0); return true }
        let shortcut = try event(key: "B", code: 11, modifiers: [.command, .shift, .capsLock], window: window)

        #expect(window.makeFirstResponder(textView))
        #expect(!recorder.performKeyEquivalent(with: shortcut))
        recorder.startRecording()
        #expect(recorder.isRecording)
        #expect(recorder.performKeyEquivalent(with: shortcut))
        #expect(recorded == [ReaderShortcutAction.toggleOutline.defaultBinding])
        #expect(!recorder.isRecording)

        recorder.startRecording()
        let escape = try event(key: "\u{1B}", code: 53, modifiers: [], window: window)
        recorder.keyDown(with: escape)
        #expect(!recorder.isRecording)
        #expect(recorded.count == 1)

        recorder.startRecording()
        #expect(window.makeFirstResponder(textView))
        #expect(!recorder.isRecording)
        #expect(!recorder.performKeyEquivalent(with: shortcut))
        #expect(recorded.count == 1)
    }

    @MainActor
    private func event(key: String, code: UInt16, modifiers: NSEvent.ModifierFlags, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: key,
            charactersIgnoringModifiers: key, isARepeat: false, keyCode: code
        ))
    }
}

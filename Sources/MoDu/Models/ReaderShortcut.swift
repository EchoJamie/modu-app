import AppKit
import SwiftUI

enum ReaderShortcutAction: String, CaseIterable, Identifiable {
    case toggleSidebar, toggleOutline, newWindow, openFolder
    case reloadDocument, reloadDirectory, findInDocument, goToLine, toggleSplitReading

    var id: String { rawValue }

    var title: String {
        let key: L10n.Key
        switch self {
        case .toggleSidebar: key = .commandToggleSidebar
        case .toggleOutline: key = .commandToggleOutline
        case .newWindow: key = .commandNewWindow
        case .openFolder: key = .commandOpenFolder
        case .reloadDocument: key = .commandReloadDocumentOutline
        case .reloadDirectory: key = .commandReloadDirectory
        case .findInDocument: key = .commandFindInDocument
        case .goToLine: key = .commandGoToLine
        case .toggleSplitReading: key = .commandToggleSplitReading
        }
        return L10n.string(key)
    }

    var defaultBinding: ReaderShortcut {
        switch self {
        case .toggleSidebar: ReaderShortcut(key: "b")
        case .toggleOutline: ReaderShortcut(key: "b", modifiers: [.command, .shift])
        case .newWindow: ReaderShortcut(key: "n")
        case .openFolder: ReaderShortcut(key: "o")
        case .reloadDocument: ReaderShortcut(key: "r")
        case .reloadDirectory: ReaderShortcut(key: "r", modifiers: [.command, .option])
        case .findInDocument: ReaderShortcut(key: "f")
        case .goToLine: ReaderShortcut(key: "l")
        case .toggleSplitReading: ReaderShortcut(key: "\\")
        }
    }
}

struct ReaderShortcut: Codable, Equatable {
    let key: String
    private let modifierFlags: UInt

    static let supportedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    init(key: String, modifiers: NSEvent.ModifierFlags = .command) {
        self.key = key.lowercased()
        modifierFlags = modifiers.intersection(Self.supportedModifiers).rawValue
    }

    init?(event: NSEvent) {
        // Read the base character so Shift/Option do not become part of the key itself.
        guard let key = event.characters(byApplyingModifiers: []), key.count == 1 else {
            return nil
        }
        self.init(key: key, modifiers: event.modifierFlags)
        guard isValid else { return nil }
    }

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    var isValid: Bool {
        key.count == 1 && key != "\u{1B}"
            && !modifiers.intersection([.command, .control]).isEmpty
    }

    var keyboardShortcut: KeyboardShortcut {
        var flags: EventModifiers = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(Character(key)), modifiers: flags)
    }

    var displayName: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        switch key {
        case " ": value += L10n.string(.settingsShortcutSpace)
        case "\r": value += "↩"
        case "\t": value += "⇥"
        case "\u{7F}": value += "⌫"
        case "\u{F700}": value += "↑"
        case "\u{F701}": value += "↓"
        case "\u{F702}": value += "←"
        case "\u{F703}": value += "→"
        case "\u{F728}": value += "⌦"
        case "\u{F729}": value += "↖"
        case "\u{F72B}": value += "↘"
        case "\u{F72C}": value += "⇞"
        case "\u{F72D}": value += "⇟"
        default:
            if let scalar = key.unicodeScalars.first, (0xF704...0xF726).contains(scalar.value) {
                value += "F\(scalar.value - 0xF704 + 1)"
            } else {
                value += key.uppercased()
            }
        }
        return value
    }

    @MainActor
    func conflictingMenuItem(in menu: NSMenu?) -> String? {
        for item in menu?.items ?? [] {
            if let title = conflictingMenuItem(in: item.submenu) { return title }
            guard !item.keyEquivalent.isEmpty else { continue }
            var flags = item.keyEquivalentModifierMask
            if item.keyEquivalent != item.keyEquivalent.lowercased() { flags.insert(.shift) }
            if self == ReaderShortcut(key: item.keyEquivalent, modifiers: flags) {
                return item.title
            }
        }
        return nil
    }
}

import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @EnvironmentObject private var applicationState: ApplicationState
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                ForEach(ReaderShortcutAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        ShortcutRecorder(
                            shortcut: applicationState.shortcut(for: action),
                            actionTitle: action.title
                        ) { shortcut in
                            errorMessage = applicationState.setShortcut(shortcut, for: action)
                            return errorMessage == nil
                        }
                        .frame(width: 150, height: 24)
                    }
                }
            } footer: {
                Text(L10n.string(.settingsShortcutHint))
            }

            Section {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                Button(L10n.string(.settingsShortcutReset)) {
                    applicationState.resetShortcuts()
                    errorMessage = nil
                }
                .disabled(applicationState.shortcutBindings.isEmpty)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: ReaderShortcut
    let actionTitle: String
    let onRecord: (ReaderShortcut) -> Bool

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        ShortcutRecorderButton()
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcutTitle = shortcut.displayName
        button.onRecord = onRecord
        button.setAccessibilityLabel(actionTitle)
        button.refreshTitle()
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: Void) {
        button.stopRecording()
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcutTitle = ""
    var onRecord: ((ReaderShortcut) -> Bool)?
    private(set) var isRecording = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    @objc func startRecording() {
        guard window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        refreshTitle()
    }

    func stopRecording() {
        isRecording = false
        refreshTitle()
    }

    func refreshTitle() {
        title = isRecording ? L10n.string(.settingsShortcutRecording) : shortcutTitle
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == 53 {
            stopRecording()
            return
        }
        guard let shortcut = ReaderShortcut(event: event) else {
            title = L10n.string(.settingsShortcutInvalid)
            return
        }
        if onRecord?(shortcut) == true { stopRecording() }
    }
}

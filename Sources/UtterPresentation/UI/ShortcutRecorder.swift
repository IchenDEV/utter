import AppKit
import SwiftUI
import UtterContracts

/// Captures one key press with its modifiers. Esc alone cancels. Modifier-only presses are ignored
/// because a chord needs a key.
final class ShortcutCaptureNSView: NSView {
    var onCapture: ((KeyChord) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Task { @MainActor [weak self] in self?.window?.makeFirstResponder(self) }
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.isDisjoint(with: [.command, .option, .control, .shift]) {
            onCancel?()
            return
        }
        onCapture?(KeyChordText.chord(keyCode: event.keyCode, flags: flags))
    }

    /// Command combinations arrive here first; taking them keeps the menu bar from acting on them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
    }
}

private struct ShortcutCapture: NSViewRepresentable {
    var onCapture: (KeyChord) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? ShortcutCaptureNSView else { return }
        view.onCapture = onCapture
        view.onCancel = onCancel
    }
}

/// The popover content that records a shortcut for one cell.
struct ShortcutRecorderView: View {
    var onCapture: (KeyChord) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ShortcutCapture(onCapture: onCapture, onCancel: onCancel)
                Text(L("remote_buttons.recorder.prompt"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, height: 56)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
            Text(L("remote_buttons.recorder.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(L("remote_buttons.recorder.cancel"), action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }
}

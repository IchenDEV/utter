import AppKit

// Batch 0 scratch tool, not product code. A harmless frontmost window that shows the current
// instruction from /tmp/b0/instruction.txt and swallows key presses, so the remote's keys do not
// reach another app and do not beep. Quits when /tmp/b0/quit appears.

final class SinkWindow: NSWindow {
    override func keyDown(with event: NSEvent) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = SinkWindow(
    contentRect: NSRect(x: 0, y: 0, width: 720, height: 320),
    styleMask: [.titled], backing: .buffered, defer: false
)
window.title = "按键测量"
let label = NSTextField(wrappingLabelWithString: "准备中…")
label.font = .systemFont(ofSize: 36, weight: .semibold)
label.alignment = .center
label.frame = NSRect(x: 20, y: 40, width: 680, height: 220)
window.contentView?.addSubview(label)
window.center()
window.level = .floating
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
    if FileManager.default.fileExists(atPath: "/tmp/b0/quit") { app.terminate(nil) }
    if let text = try? String(contentsOfFile: "/tmp/b0/instruction.txt", encoding: .utf8), text != label.stringValue {
        label.stringValue = text
    }
    if !app.isActive { app.activate(ignoringOtherApps: true) }
}
app.run()

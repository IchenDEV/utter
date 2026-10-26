import AppKit

// Batch 5 scratch tool, not product code. Measures which synthetic events macOS's own shortcuts react to.
// A frontmost window swallows keys, so an event the system does not consume lands harmlessly here.
// Each variant is posted, observed, and (if it had an effect) posted again to undo it.
// Usage: ActionProbe <logpath>

final class SinkWindow: NSWindow {
    override func keyDown(with event: NSEvent) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}

let logPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/b5-probe.txt"
FileManager.default.createFile(atPath: logPath, contents: nil)
let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
let started = Date()
func log(_ text: String) {
    handle.write(Data(String(format: "[%5.1f] %@\n", Date().timeIntervalSince(started), text).utf8))
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = SinkWindow(
    contentRect: NSRect(x: 300, y: 300, width: 520, height: 160),
    styleMask: [.titled], backing: .buffered, defer: false
)
window.title = "探针（按键测量）"
let label = NSTextField(wrappingLabelWithString: "正在测量系统快捷键，几秒后自动结束")
label.frame = NSRect(x: 20, y: 40, width: 480, height: 80)
window.contentView?.addSubview(label)
window.level = .floating
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

func windowState() -> String {
    let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
    guard let entry = info?.first(where: { ($0[kCGWindowNumber as String] as? Int) == window.windowNumber }) else { return "window=missing" }
    let bounds = entry[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let onscreen = (entry[kCGWindowIsOnscreen as String] as? Bool) ?? false
    return "x=\(Int(bounds["X"] ?? -1)) y=\(Int(bounds["Y"] ?? -1)) onscreen=\(onscreen)"
}
func front() -> String {
    guard let app = NSWorkspace.shared.frontmostApplication else { return "none" }
    return app.processIdentifier == getpid() ? "probe" : (app.bundleIdentifier ?? "unknown")
}

func post(_ code: CGKeyCode, flags: CGEventFlags, modifierEvents: Bool = false, gap: TimeInterval = 0) {
    let source = CGEventSource(stateID: .combinedSessionState)
    func send(_ code: CGKeyCode, down: Bool, flags: CGEventFlags, flagsChanged: Bool = false) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        if flagsChanged { event?.type = .flagsChanged }
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
    var queue: [() -> Void] = []
    if modifierEvents { queue.append { send(55, down: true, flags: .maskCommand, flagsChanged: true) } }
    queue.append { send(code, down: true, flags: flags) }
    queue.append { send(code, down: false, flags: flags) }
    if modifierEvents { queue.append { send(55, down: false, flags: [], flagsChanged: true) } }
    for (i, step) in queue.enumerated() {
        if gap == 0 { step() } else { DispatchQueue.main.asyncAfter(deadline: .now() + gap * Double(i), execute: step) }
    }
}

struct Step { var name: String; var code: CGKeyCode; var flags: CGEventFlags; var modifierEvents = false; var gap: TimeInterval = 0 }
let steps = [
    Step(name: "Cmd+Tab with modifier events, no gaps", code: 48, flags: .maskCommand, modifierEvents: true),
    Step(name: "Cmd+Tab with modifier events, 40 ms gaps", code: 48, flags: .maskCommand, modifierEvents: true, gap: 0.04),
]
var baseline = ""
var index = 0

func runNext() {
    guard index < steps.count else {
        log("END")
        app.terminate(nil)
        return
    }
    let step = steps[index]
    index += 1
    guard front() == "probe" else {
        log("SKIP \(step.name): the probe is not frontmost (\(front())), nothing was posted")
        return runNext()
    }
    log("STEP \(step.name): before front=\(front()) \(windowState())")
    post(step.code, flags: step.flags, modifierEvents: step.modifierEvents, gap: step.gap)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
        let after = windowState()
        let frontAfter = front()
        let changed = after != baseline || frontAfter != "probe"
        log("STEP \(step.name): after  front=\(frontAfter) \(after) EFFECT=\(changed)")
        app.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            log("STEP \(step.name): reactivated front=\(front())")
            runNext()
        }
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    baseline = windowState()
    log("BASELINE front=\(front()) \(baseline)")
    runNext()
}
app.run()

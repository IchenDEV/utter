import AppKit
import ApplicationServices

// Batch 0 probe for the delivery spec (T1: AX selected-text write, T2: clipboard paste).
// Usage: delivery-probe <app-name-substring> <label> [--read-only] [--allow-selected-all] [--wait=seconds]
// Safety: writes a fixed ASCII marker only into a focused field that is empty ("" or "\n") or, with
// --allow-selected-all, whose whole value is selected. Never prints field values, only lengths and flags.
// The clipboard is snapshotted before T2 and restored after it.

func ax(_ el: AXUIElement, _ attr: String) -> (AXError, CFTypeRef?) {
    var v: CFTypeRef?
    let e = AXUIElementCopyAttributeValue(el, attr as CFString, &v)
    return (e, v)
}

func settable(_ el: AXUIElement, _ attr: String) -> String {
    var s: DarwinBoolean = false
    return AXUIElementIsAttributeSettable(el, attr as CFString, &s) == .success ? (s.boolValue ? "settable" : "readonly") : "err"
}

func selection(_ el: AXUIElement) -> (Int, Int)? {
    guard let r = ax(el, kAXSelectedTextRangeAttribute as String).1, CFGetTypeID(r) == AXValueGetTypeID() else { return nil }
    var cr = CFRange()
    return AXValueGetValue(r as! AXValue, .cfRange, &cr) ? (cr.location, cr.length) : nil
}

func value(_ el: AXUIElement) -> String? { ax(el, kAXValueAttribute as String).1 as? String }

let t0 = Date()
func log(_ s: String) { print(String(format: "[%6.2f] ", Date().timeIntervalSince(t0)) + s); fflush(stdout) }

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { print("usage: delivery-probe <app> <label> [--read-only] [--allow-selected-all] [--wait=N]"); exit(2) }
let appName = args[0], label = args[1]
let readOnly = args.contains("--read-only"), allowSelectedAll = args.contains("--allow-selected-all")
let waitSeconds = args.compactMap { $0.hasPrefix("--wait=") ? Double($0.dropFirst(7)) : nil }.first ?? 150

log("AXIsProcessTrusted=\(AXIsProcessTrusted()) label=\(label) readOnly=\(readOnly)")
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.activationPolicy == .regular && ($0.localizedName ?? "").localizedCaseInsensitiveContains(appName) }) else {
    log("RESULT label=\(label) status=app-not-running"); exit(1)
}
let pid = app.processIdentifier
let appEl = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(appEl, 1.0)
log("target app=\(app.localizedName ?? "?") bundle=\(app.bundleIdentifier ?? "?") pid=\(pid)")

func emptyEquivalent(_ v: String) -> Bool { v.isEmpty || v == "\n" }

func focusedField() -> AXUIElement? {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
          let f = ax(appEl, kAXFocusedUIElementAttribute as String).1,
          let v = value(f as! AXUIElement), let sel = selection(f as! AXUIElement) else { return nil }
    if emptyEquivalent(v) { return (f as! AXUIElement) }
    return allowSelectedAll && sel.1 == v.utf16.count && sel.1 > 0 ? (f as! AXUIElement) : nil
}

log("waiting up to \(Int(waitSeconds)) s for the target app in front with an eligible focused field")
var stable = 0
var candidate: AXUIElement?
let deadline = Date().addingTimeInterval(waitSeconds)
while Date() < deadline {
    if let f = focusedField() {
        if let c = candidate, CFEqual(c, f) { stable += 1 } else { candidate = f; stable = 1 }
        if stable >= 3 { break }
    } else { candidate = nil; stable = 0 }
    Thread.sleep(forTimeInterval: 0.4)
}
guard stable >= 3, let el = candidate else { log("RESULT label=\(label) status=no-eligible-field-before-timeout"); exit(1) }

let names: [String] = { var n: CFArray?; return AXUIElementCopyAttributeNames(el, &n) == .success ? (n as? [String] ?? []) : [] }()
let domId = (ax(el, "AXDOMIdentifier").1 as? String).map { ["f-input", "f-textarea", "f-ce"].contains($0) ? $0 : "<redacted>" } ?? "-"
let v0 = value(el) ?? ""
let sel0 = selection(el) ?? (-1, -1)
log("FIELD role=\(ax(el, kAXRoleAttribute as String).1 as? String ?? "?") subrole=\((ax(el, kAXSubroleAttribute as String).1 as? String) ?? "-") domId=\(domId) attrs=\(names.count) ChromeAXNodeId=\(names.contains("ChromeAXNodeId")) AXDOMClassList=\(names.contains("AXDOMClassList")) EditableAncestor=\(names.contains("AXEditableAncestor"))")
log("FIELD initial valueLen=\(v0.utf16.count) isNewlineOnly=\(v0 == "\n") selection=\(sel0.0),\(sel0.1) AXValue=\(settable(el, kAXValueAttribute as String)) AXSelectedText=\(settable(el, kAXSelectedTextAttribute as String)) AXSelectedTextRange=\(settable(el, kAXSelectedTextRangeAttribute as String))")
if readOnly { log("RESULT label=\(label) status=read-only-done"); exit(0) }

func samples(_ tag: String, marker: String) -> Bool {
    var effective = false
    var last = 0.0
    let start = Date()
    for t in [0.05, 0.25, 0.5, 1, 2, 4] {
        Thread.sleep(forTimeInterval: t - last); last = t
        let v = value(el) ?? "<err>"
        let s = selection(el) ?? (-1, -1)
        let has = v.contains(marker)
        effective = effective || has
        log(String(format: "%@ t=%.2f valueLen=%d containsMarker=%@ equalsMarker=%@ isNewlineOnly=%@ selection=%d,%d", tag, Date().timeIntervalSince(start), v.utf16.count, "\(has)", "\(v == marker)", "\(v == "\n")", s.0, s.1))
    }
    return effective
}

let t1 = "UTTERPROBE-T1"
let setErr = AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, t1 as CFString)
log("T1 write returned AXError=\(setErr.rawValue)")
let t1Effective = samples("T1", marker: t1)
log("T1 effective=\(t1Effective)")
if t1Effective { log("RESULT label=\(label) T1=effective T2=skipped"); exit(0) }

guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { log("RESULT label=\(label) T1=ineffective T2=skipped-target-not-frontmost"); exit(1) }
let pb = NSPasteboard.general
let snapshot: [[(NSPasteboard.PasteboardType, Data)]] = pb.pasteboardItems?.map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } } ?? []
let t2 = "UTTERPROBE-T2"
pb.clearContents(); pb.setString(t2, forType: .string)
let src = CGEventSource(stateID: .combinedSessionState)
for down in [true, false] {
    let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)!
    e.flags = .maskCommand
    e.post(tap: .cghidEventTap)
}
log("T2 posted Cmd+V")
let t2Effective = samples("T2", marker: t2)
pb.clearContents()
let restored = snapshot.map { entries -> NSPasteboardItem in
    let item = NSPasteboardItem(); entries.forEach { item.setData($0.1, forType: $0.0) }; return item
}
if !restored.isEmpty { pb.writeObjects(restored) }
let after = pb.pasteboardItems?.map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } } ?? []
let same = after.count == snapshot.count && zip(after, snapshot).allSatisfy { a, b in a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 } }
log("T2 effective=\(t2Effective) clipboardRestoredIdentical=\(same) itemsBefore=\(snapshot.count)")
log("RESULT label=\(label) T1=ineffective T2=\(t2Effective ? "effective" : "ineffective") clipboardRestored=\(same)")

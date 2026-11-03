import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IOLBF, 0)
func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}
/// Shape only: counts per character class. The text itself is never printed or stored.
func shape(_ s: String) -> String {
    var k: [String: Int] = [:]
    for c in s.unicodeScalars {
        let v = c.value
        let name: String
        switch v {
        case 0x0A: name = "LF"
        case 0x20: name = "SP"
        case 0xA0: name = "NBSP"
        case 0x200B...0x200D, 0xFEFF: name = "ZW"
        case 0xFFFC: name = "OBJ"
        case 0x4E00...0x9FFF: name = "CJK"
        case 0x3000...0x303F, 0xFF00...0xFFEF: name = "CJKP"
        case 0x30...0x39: name = "DIG"
        case 0x41...0x5A, 0x61...0x7A: name = "ASCII"
        case 0..<0x20: name = "CTRL"
        default: name = "other"
        }
        k[name, default: 0] += 1
    }
    let body = k.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    return "u16=\((s as NSString).length){\(body)}\(s.hasPrefix("\n") ? " startLF" : "")\(s.hasSuffix("\n") ? " endLF" : "")\(s == "\n" ? " ONLY-LF" : "")"
}
let bundles = (CommandLine.arguments.dropFirst().first ?? "com.openai.codex").split(separator: ",").map(String.init)
let minutes = Double(CommandLine.arguments.dropFirst(2).first ?? "45") ?? 45
let deadline = Date().addingTimeInterval(minutes * 60)
let fmt = DateFormatter(); fmt.dateFormat = "HH:mm:ss.SSS"
var last = ""
var prevValue: String? = nil
var prevOwner = ""
print("watching \(bundles) until \(fmt.string(from: deadline)); shape only, no text")
func common(_ a: [UInt16], _ b: [UInt16]) -> (Int, Int) {
    var p = 0; while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
    var q = 0; while q < a.count - p, q < b.count - p, a[a.count - 1 - q] == b[b.count - 1 - q] { q += 1 }
    return (p, q)
}
while Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.12))
    guard let app = bundles.compactMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }).first(where: { $0.isActive }) else {
        if last != "inactive" { last = "inactive"; print(fmt.string(from: Date()), "target apps not frontmost") }
        continue
    }
    let tag = String((app.bundleIdentifier ?? "?").suffix(8))
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    guard let f = attr(ax, kAXFocusedUIElementAttribute as String) else {
        if last != "nofocus" { last = "nofocus"; print(fmt.string(from: Date()), tag, "no focused element") }
        continue
    }
    let el = f as! AXUIElement
    var names: CFArray?; AXUIElementCopyAttributeNames(el, &names)
    let list = (names as? [String]) ?? []
    var sel = "-"
    if let r = attr(el, "AXSelectedTextRange") { var cf = CFRange(); AXValueGetValue(r as! AXValue, .cfRange, &cf); sel = "\(cf.location),\(cf.length)" }
    let raw = attr(el, "AXValue") as? String
    let value = raw.map(shape) ?? "none"
    let ph = (attr(el, "AXPlaceholderValue") as? String).map(shape) ?? "none"
    var settable = DarwinBoolean(false)
    AXUIElementIsAttributeSettable(el, "AXSelectedText" as CFString, &settable)
    var line = "\(tag) role=\(attr(el, "AXRole") as? String ?? "-") chromeId=\(list.contains("ChromeAXNodeId")) selSettable=\(settable.boolValue) sel=\(sel) value=\(value) placeholder=\(ph)"
    if line != last {
        if let raw, let old = prevValue, prevOwner == tag, old != raw, settable.boolValue {
            let a = Array(old.utf16), b = Array(raw.utf16)
            let (p, q) = common(a, b)
            let inserted = String(utf16CodeUnits: Array(b[p..<(b.count - q)]), count: b.count - p - q)
            line += " DELTA oldLen=\(a.count) newLen=\(b.count) prefix=\(p) suffix=\(q) removed=\(a.count - p - q) inserted=\(shape(inserted))"
        }
        last = line; print(fmt.string(from: Date()), line)
    }
    if settable.boolValue { prevValue = raw; prevOwner = tag } else { prevValue = nil }
}
print("done")

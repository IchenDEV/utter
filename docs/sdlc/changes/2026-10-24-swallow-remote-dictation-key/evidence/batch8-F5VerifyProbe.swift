import Foundation
import CoreGraphics

private var logURL: URL!
private let logLock = NSLock()

private func ts() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date())
}

private func logLine(_ line: String) {
    let s = "[\(ts())] \(line)\n"
    logLock.lock()
    defer { logLock.unlock() }
    if let d = s.data(using: .utf8), let fh = try? FileHandle(forWritingTo: logURL) {
        fh.seekToEndOfFile()
        fh.write(d)
        try? fh.close()
    }
    FileHandle.standardError.write(s.data(using: .utf8)!)
}

private func hidutilMapping() -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    proc.arguments = [
        "property",
        "--matching", "{\"VendorID\":10007,\"ProductID\":12984}",
        "--get", "UserKeyMapping",
    ]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    guard (try? proc.run()) != nil else { return "<run failed>" }
    proc.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

final class TapState {
    let lock = NSLock()
    var f5Down = 0
    var f5Up = 0
    var key126 = 0
    var key36 = 0
    var gate126Down = 0
    var sysDefVol = 0
    var otherKeys: [Int64: Int] = [:]
    var gateDone = false
}

private func handleEvent(_ type: CGEventType, _ event: CGEvent, _ st: TapState) {
    st.lock.lock()
    defer { st.lock.unlock() }
    switch type {
    case .keyDown, .keyUp:
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == 96 {
            if type == .keyDown { st.f5Down += 1; logLine("F5 keyDown total=\(st.f5Down)") }
            else { st.f5Up += 1 }
        } else if code == 126 {
            st.key126 += 1
            if type == .keyDown {
                st.gate126Down += 1
                if st.gate126Down >= 3 { st.gateDone = true }
            }
        } else if code == 36 { st.key36 += 1 }
        else { st.otherKeys[code, default: 0] += 1 }
    case CGEventType(rawValue: 14)!: // NX_SYSDEFINED
        let data1 = event.getIntegerValueField(CGEventField(rawValue: 32)!)
        let subtype = Int((data1 >> 16) & 0xFFFF)
        if subtype == 8 {
            st.sysDefVol += 1
            logLine("systemDefined volume subtype=8")
        }
    default: break
    }
}

private func makeTap(_ st: TapState) -> CFMachPort? {
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        | (1 << 14) // NX_SYSDEFINED
    let ref = Unmanaged.passRetained(st).toOpaque()
    let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: CGEventMask(mask),
        callback: { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let st = Unmanaged<TapState>.fromOpaque(userInfo).takeUnretainedValue()
            handleEvent(type, event, st)
            return Unmanaged.passUnretained(event)
        },
        userInfo: ref
    )
    if tap == nil { Unmanaged<TapState>.fromOpaque(ref).release() }
    return tap
}

private func runLoopWithTap(_ st: TapState, seconds: TimeInterval, pollMapping: Bool) {
    guard let tap = makeTap(st) else {
        logLine("ERROR tapCreate failed — Input Monitoring permission likely missing")
        return
    }
    let ref = Unmanaged.passRetained(st)
    defer { ref.release() }

    let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    var poll: DispatchSourceTimer?
    if pollMapping {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now(), repeating: 0.5)
        t.setEventHandler { logLine("MAPPING \(hidutilMapping())") }
        t.resume()
        poll = t
    }

    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        st.lock.lock()
        let done = st.gateDone
        st.lock.unlock()
        if pollMapping == false && done { break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    poll?.cancel()
    CGEvent.tapEnable(tap: tap, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
}

private func summary(_ st: TapState) -> String {
    st.lock.lock()
    defer { st.lock.unlock() }
    return "f5Down=\(st.f5Down) f5Up=\(st.f5Up) k126=\(st.key126) ret36=\(st.key36) volSys=\(st.sysDefVol) other=\(st.otherKeys)"
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("usage: F5VerifyProbe gate|measure <logpath> [seconds] [label]\n", stderr)
    exit(2)
}

logURL = URL(fileURLWithPath: args[2])
FileManager.default.createFile(atPath: logURL.path, contents: Data("--- F5VerifyProbe ---\n".utf8))

switch args[1] {
case "gate":
    logLine("GATE waiting up=3 on key126 max 600s")
    let st = TapState()
    runLoopWithTap(st, seconds: 600, pollMapping: false)
    st.lock.lock()
    let ok = st.gateDone
    st.lock.unlock()
    logLine("GATE finished ok=\(ok) \(summary(st))")
    exit(ok ? 0 : 1)

case "measure":
    let sec = args.count > 3 ? (Double(args[3]) ?? 30) : 30
    let label = args.count > 4 ? args[4] : "run"
    logLine("MEASURE start label=\(label) sec=\(sec)")
    logLine("MAPPING \(hidutilMapping())")
    let st = TapState()
    runLoopWithTap(st, seconds: sec, pollMapping: true)
    logLine("MEASURE end \(summary(st))")
    exit(0)

default:
    exit(2)
}

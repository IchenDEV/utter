import AppKit
import Foundation
import IOKit.hid

// Batch 0 scratch tool, not product code. Logs, in one time base, the RC003's raw HID input values
// (non-seizing, below UserKeyMapping) and the CG events the session sees (listen-only tap).
// Usage: KeyTable <logpath> <maxSeconds> [selftest]
// `selftest` posts a synthetic F19 press to prove the tap sees events from this host.

private var logHandle: FileHandle!
private let started = ProcessInfo.processInfo.systemUptime
private var stopRequested = false

private func line(_ text: String) {
    let t = String(format: "%8.3f", ProcessInfo.processInfo.systemUptime - started)
    logHandle.write(Data("[\(t)] \(text)\n".utf8))
}

let args = CommandLine.arguments
guard args.count >= 3, let maxSeconds = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: KeyTable <logpath> <maxSeconds> [selftest]\n".utf8))
    exit(2)
}
FileManager.default.createFile(atPath: args[1], contents: Data("--- KeyTable ---\n".utf8))
logHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: args[1]))
let selfTest = args.count > 3 && args[3] == "selftest"

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 10007, kIOHIDProductIDKey: 12984] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    line("HID page=\(IOHIDElementGetUsagePage(element)) usage=\(IOHIDElementGetUsage(element)) value=\(IOHIDValueGetIntegerValue(value)) vendor=10007")
}, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
let matched = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.count ?? 0
line("START hidOpen=\(String(opened, radix: 16)) matchedDevices=\(matched)")

private func describe(_ type: CGEventType, _ event: CGEvent) {
    let flags = String(event.flags.rawValue, radix: 16)
    switch type {
    case .keyDown, .keyUp:
        line("CG \(type == .keyDown ? "keyDown" : "keyUp") code=\(event.getIntegerValueField(.keyboardEventKeycode)) flags=0x\(flags) repeat=\(event.getIntegerValueField(.keyboardEventAutorepeat))")
    case .flagsChanged:
        line("CG flagsChanged code=\(event.getIntegerValueField(.keyboardEventKeycode)) flags=0x\(flags)")
    default:
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined else { return line("CG other type=\(type.rawValue)") }
        let data1 = ns.data1
        let state = (data1 & 0xFF00) >> 8
        line("CG sysdef subtype=\(ns.subtype.rawValue) key=\((data1 & 0xFFFF0000) >> 16) state=\(state == 0xA ? "down" : state == 0xB ? "up" : "0x" + String(state, radix: 16)) flags=0x\(flags)")
    }
}

let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask,
    callback: { _, type, event, _ in
        describe(type, event)
        return Unmanaged.passUnretained(event)
    }, userInfo: nil
) else {
    line("ERROR tapCreate failed")
    exit(1)
}
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
line("TAP created")

signal(SIGTERM, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
term.setEventHandler { stopRequested = true }
term.resume()

if selfTest {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 80, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }
}

let end = Date().addingTimeInterval(maxSeconds)
while Date() < end && !stopRequested { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
line("END")

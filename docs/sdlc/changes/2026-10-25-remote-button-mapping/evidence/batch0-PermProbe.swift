import Foundation
import IOKit.hid

// Batch 0 scratch tool, not product code. Run as an ad hoc signed .app launched with `open`, so it carries
// none of Cursor's or Terminal's permissions. Reports what a non-seizing IOHIDManager on the RC003 gets.
// Args: <logpath> <mode> <seconds>   mode: check | request
//   check   : report IOHIDCheckAccess, open the manager, count remote presses (3 wanted) until timeout.
//   request : call IOHIDRequestAccess (system prompt), poll IOHIDCheckAccess, then count presses in-process.

let args = CommandLine.arguments
guard args.count >= 4, let seconds = Double(args[3]) else { exit(2) }
let mode = args[2]
FileManager.default.createFile(atPath: args[1], contents: nil)
let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: args[1]))
let started = Date()
func log(_ text: String) {
    handle.write(Data(String(format: "[%6.2f] %@\n", Date().timeIntervalSince(started), text).utf8))
}

func access() -> String {
    switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
    case kIOHIDAccessTypeGranted: return "granted"
    case kIOHIDAccessTypeDenied: return "denied"
    case kIOHIDAccessTypeUnknown: return "unknown"
    default: return "other"
    }
}

var downs = 0
var events = 0
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 10007, kIOHIDProductIDKey: 12984] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    let usage = IOHIDElementGetUsage(element)
    events += 1
    if usage == 79 && IOHIDValueGetIntegerValue(value) == 1 { downs += 1; log("press usage=79 total=\(downs)") }
}, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

log("START mode=\(mode) pid=\(getpid()) bundle=\(Bundle.main.bundleIdentifier ?? "none") accessAtLaunch=\(access())")
func openManager() {
    let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    let matched = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.count ?? 0
    log("OPEN result=0x\(String(UInt32(bitPattern: opened), radix: 16)) matchedDevices=\(matched) accessAfterOpen=\(access())")
}
// check mode opens first (what a naive implementation would do); request mode asks first and opens only after.
if mode == "check" { openManager(); log("READY") }

func spin(until done: () -> Bool, limit: Double) {
    let end = Date().addingTimeInterval(limit)
    while Date() < end && !done() { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
}

if mode == "request" {
    let before = access()
    let returned = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    log("REQUEST returned=\(returned) accessBefore=\(before) accessImmediately=\(access())")
    var last = access()
    spin(until: {
        let now = access()
        if now != last { log("ACCESS changed \(last) -> \(now)"); last = now }
        return now == "granted"
    }, limit: seconds)
    log("REQUEST_DONE access=\(access())")
    openManager()
    log("READY2 press right x3 now; same process, no relaunch")
    spin(until: { downs >= 3 }, limit: 60)
} else {
    spin(until: { downs >= 3 }, limit: seconds)
}
log("RESULT access=\(access()) rawEventsSeen=\(events) presses=\(downs)")
log("END")

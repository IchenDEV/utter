#!/usr/bin/env swift
// Tells a booted iOS simulator whether a hardware keyboard is attached.
//
// Xcode 27 replaced Simulator.app with DeviceHub, and a headless `xcodebuild test` boots simulators that
// believe a hardware keyboard is attached, so the software keyboard never appears and keyboard UI tests
// see their keys off screen. The `com.apple.iphonesimulator` default no longer reaches those boots.
// This calls CoreSimulator's private `setHardwareKeyboardEnabled:keyboardType:error:`, which is what
// the simulator host app did. Development machines only; the state resets when the device reboots.
//
// usage: swift scripts/sim-hardware-keyboard.swift <SIMULATOR_UUID> on|off
import Foundation
import ObjectiveC

let args = CommandLine.arguments
guard args.count == 3, ["on", "off"].contains(args[2]) else {
    print("usage: swift scripts/sim-hardware-keyboard.swift <SIMULATOR_UUID> on|off")
    exit(2)
}
let target = args[1].uppercased()
let enable = args[2] == "on"
let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? "/Applications/Xcode.app/Contents/Developer"

func fail(_ message: String) -> Never {
    print("error: \(message)")
    exit(1)
}

guard dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW) != nil else {
    fail("CoreSimulator.framework could not be loaded")
}

typealias ContextFn = @convention(c) (AnyObject, Selector, NSString, UnsafeMutablePointer<NSError?>?) -> AnyObject?
typealias DeviceSetFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> AnyObject?
typealias KeyboardFn = @convention(c) (AnyObject, Selector, Bool, UInt8, UnsafeMutablePointer<NSError?>?) -> Bool

guard let contextClass = NSClassFromString("SimServiceContext"),
      let metaclass = object_getClass(contextClass) else { fail("SimServiceContext is unavailable") }
let contextSelector = NSSelectorFromString("sharedServiceContextForDeveloperDir:error:")
guard let contextImp = class_getMethodImplementation(metaclass, contextSelector) else { fail("no service context entry point") }
var error: NSError?
guard let context = unsafeBitCast(contextImp, to: ContextFn.self)(contextClass, contextSelector, developerDir as NSString, &error) else {
    fail("service context: \(error.map { "\($0)" } ?? "unknown")")
}

let deviceSetSelector = NSSelectorFromString("defaultDeviceSetWithError:")
guard let deviceSetImp = class_getMethodImplementation(type(of: context), deviceSetSelector),
      let deviceSet = unsafeBitCast(deviceSetImp, to: DeviceSetFn.self)(context, deviceSetSelector, &error) else {
    fail("device set: \(error.map { "\($0)" } ?? "unknown")")
}
guard let devices = deviceSet.perform(NSSelectorFromString("devices"))?.takeUnretainedValue() as? [AnyObject] else {
    fail("no simulator list")
}

for device in devices {
    guard let udid = device.perform(NSSelectorFromString("UDID"))?.takeUnretainedValue() as? NSUUID,
          udid.uuidString == target else { continue }
    let selector = NSSelectorFromString("setHardwareKeyboardEnabled:keyboardType:error:")
    guard let imp = class_getMethodImplementation(type(of: device), selector) else { fail("no hardware keyboard entry point") }
    guard unsafeBitCast(imp, to: KeyboardFn.self)(device, selector, enable, 0, &error) else {
        fail("setHardwareKeyboardEnabled(\(enable)): \(error.map { "\($0)" } ?? "unknown")")
    }
    print("hardware keyboard \(enable ? "attached" : "detached") on \(target)")
    exit(0)
}
fail("simulator \(target) not found")

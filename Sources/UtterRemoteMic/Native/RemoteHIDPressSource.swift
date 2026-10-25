import Foundation
import IOKit
import IOKit.hid
import UtterContracts

/// Non-seizing `IOHIDManager` on the supported remote. Needs Input Monitoring: without it opening
/// returns `kIOReturnNotPermitted` while still enumerating the device (measured), and a first open
/// turns "not asked" into "denied" without any prompt, so this never opens until access is granted.
@MainActor
final class RemoteHIDPressSource: RemotePressSourcing {
    private static let notPermitted = Int32(bitPattern: 0xE000_02E2)

    var onEdge: ((RemoteButton, Bool) -> Void)?
    var onDevicesChanged: (() -> Void)?

    private var manager: IOHIDManager?
    /// Keeps `self` alive for the C callbacks until `stop()` unregisters them.
    private var context: Unmanaged<RemoteHIDPressSource>?

    func refresh(prompt: Bool) -> PressSourceStatus {
        var access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access == kIOHIDAccessTypeUnknown, prompt {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        }
        guard access == kIOHIDAccessTypeGranted else {
            stop()
            return .needsPermission(canAsk: access == kIOHIDAccessTypeUnknown)
        }
        if manager == nil, let failure = open() { return failure }
        return deviceCount() > 0 ? .live : .waitingForRemote
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        context?.release()
        context = nil
    }

    private func deviceCount() -> Int {
        guard let manager else { return 0 }
        return (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.count ?? 0
    }

    /// `nil` on success.
    private func open() -> PressSourceStatus? {
        let created = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(created, [
            kIOHIDVendorIDKey: RemoteKeyMappingPolicy.vendorID,
            kIOHIDProductIDKey: RemoteKeyMappingPolicy.productID,
        ] as CFDictionary)
        let retained = Unmanaged.passRetained(self)
        IOHIDManagerRegisterInputValueCallback(created, { context, _, _, value in
            guard let context else { return }
            let source = Unmanaged<RemoteHIDPressSource>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            let page = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))
            let raw = IOHIDValueGetIntegerValue(value)
            MainActor.assumeIsolated { source.handle(page: page, usage: usage, value: raw) }
        }, retained.toOpaque())
        let devicesChanged: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let source = Unmanaged<RemoteHIDPressSource>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { source.onDevicesChanged?() }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(created, devicesChanged, retained.toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(created, devicesChanged, retained.toOpaque())
        IOHIDManagerScheduleWithRunLoop(created, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(created, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            IOHIDManagerRegisterInputValueCallback(created, nil, nil)
            IOHIDManagerRegisterDeviceMatchingCallback(created, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(created, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(created, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            retained.release()
            return result == Self.notPermitted ? .needsRestart : .failed
        }
        manager = created
        context = retained
        return nil
    }

    private func handle(page: Int, usage: Int, value: Int) {
        guard let edge = RemoteButtonEdge.decode(usagePage: page, usage: usage, value: value) else { return }
        onEdge?(edge.button, edge.isDown)
    }
}

import UtterContracts
import Foundation
import CoreGraphics
import AppKit

@MainActor
package final class HotkeyManager {
    let log: UtterContracts.Log
    let settings: () -> SettingsValues
    let markAccessibilityPrompted: () -> Void
    var isClosed = false
    var isStarted = false
    var ownedTasks: [UUID: Task<Void, Never>] = [:]
    var retryTask: Task<Void, Never>?
    let gestures: HotkeyGestureController
    private let eventTime: HotkeyEventTime
    package var eventTimestamp: Duration? { eventTime.current }
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var globalMonitor: Any?

    var retryCount = 0
    let maxRetries = 20

    package init(
        settings: @escaping () -> SettingsValues,
        onStart: @escaping (HotkeyAction) -> Void,
        onStop: @escaping (HotkeyAction) -> Void,
        onPromote: @escaping (HotkeyPromotion) -> Bool = { _ in false },
        onCancel: @escaping () -> Void = {},
        log: UtterContracts.Log,
        markAccessibilityPrompted: @escaping () -> Void
    ) {
        self.markAccessibilityPrompted = markAccessibilityPrompted
        self.log = log
        self.settings = settings
        let eventTime = HotkeyEventTime()
        self.eventTime = eventTime
        gestures = HotkeyGestureController(
            settings: settings,
            onStart: onStart,
            onStop: onStop, onPromote: onPromote, onCancel: onCancel,
            now: { eventTime.current ?? .seconds(ProcessInfo.processInfo.systemUptime) }
        )
    }

    package func start() {
        guard !isStarted else { return }
        isStarted = true
        isClosed = false
        retryCount = 0
        if AXIsProcessTrusted() {
            createEventTap()
            setupGlobalMonitor()
            return
        }

        if !settings().hotkeyAccessibilityPrompted {
            markAccessibilityPrompted()
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        } else {
            log.info("[HotkeyManager] Accessibility not granted, waiting silently (user was prompted before)")
        }

        setupGlobalMonitor()

        scheduleTrustRetry(after: 2)
    }

    func retryIfTrusted() {
        guard !isClosed, eventTap == nil, retryCount < maxRetries else { return }
        retryCount += 1
        if AXIsProcessTrusted() {
            createEventTap()
        } else {
            scheduleTrustRetry(after: 3)
        }
    }

    func createEventTap() {
        guard eventTap == nil else { return }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotkeyEventCallback,
            userInfo: refcon
        ) else {
            log.info("[HotkeyManager] CGEvent tap failed, NSEvent fallback only")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func setupGlobalMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleNSEventFlags(event) }
        }
    }

    package func stop() {
        isClosed = true
        isStarted = false
        for task in ownedTasks.values { task.cancel() }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        eventTap = nil
        runLoopSource = nil
        globalMonitor = nil
        retryTask = nil
        gestures.reset()
    }

    func handleFlagsChanged(_ event: CGEvent) {
        eventTime.current = .nanoseconds(Int64(clamping: event.timestamp))
        if event.type == .keyDown {
            handleNavigationKey(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
            return
        }
        let values = gestures.keySettings
        processPhysicalKeyState(
            primaryPressed: isKeyPressed(values.hotkeyType, flags: event.flags),
            translationModifierPressed: isKeyPressed(values.translationHotkeyModifier, flags: event.flags),
            systemCombination: hasOtherModifiers(event.flags)
        )
    }

    func handleNSEventFlags(_ event: NSEvent) {
        guard eventTap == nil else { return }
        if event.timestamp.isFinite, event.timestamp >= 0 { eventTime.current = .seconds(event.timestamp) }
        if event.type == .keyDown { handleNavigationKey(event.keyCode); return }
        let values = gestures.keySettings
        processPhysicalKeyState(
            primaryPressed: isKeyPressed(values.hotkeyType, flags: event.modifierFlags),
            translationModifierPressed: isKeyPressed(values.translationHotkeyModifier, flags: event.modifierFlags),
            systemCombination: hasOtherModifiers(CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
        )
    }

    func isKeyPressed(_ key: HotkeyType, flags: CGEventFlags) -> Bool {
        switch key {
        case .ctrl: return flags.contains(.maskControl)
        case .shift: return flags.contains(.maskShift)
        case .option: return flags.contains(.maskAlternate)
        case .fn: return flags.contains(.maskSecondaryFn)
        }
    }

    func isKeyPressed(_ key: HotkeyType, flags: NSEvent.ModifierFlags) -> Bool {
        switch key {
        case .ctrl: return flags.contains(.control)
        case .shift: return flags.contains(.shift)
        case .option: return flags.contains(.option)
        case .fn: return flags.contains(.function)
        }
    }

}

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passRetained(event) }
    return MainActor.assumeIsolated {
        let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        manager.handleFlagsChanged(event)
        return Unmanaged.passRetained(event)
    }
}

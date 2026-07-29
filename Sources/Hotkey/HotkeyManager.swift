import Foundation
import CoreGraphics
import AppKit

final class HotkeyManager {
    private let settings: AppSettings
    private let activationController: HotkeyActivationController
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?

    private var activeGestureAction: HotkeyAction?
    private var previousPrimaryPressed = false
    private var previousTranslationModifierPressed = false
    private var suppressUntilPrimaryRelease = false
    private var pendingPrimaryStart: Task<Void, Never>?
    private var retryCount = 0
    private let maxRetries = 20
    private let translationChordGraceNanoseconds: UInt64 = 100_000_000

    init(
        settings: AppSettings,
        onStart: @escaping (HotkeyAction) -> Void,
        onStop: @escaping (HotkeyAction) -> Void
    ) {
        self.settings = settings
        activationController = HotkeyActivationController(
            settings: settings,
            onStart: onStart,
            onStop: onStop
        )
    }

    func start() {
        if AXIsProcessTrusted() {
            createEventTap()
            setupGlobalMonitor()
            return
        }

        // Only prompt once per install — use UserDefaults to avoid nagging on every launch
        let key = "hotkeyAccessibilityPrompted"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        } else {
            Log.info("[HotkeyManager] Accessibility not granted, waiting silently (user was prompted before)")
        }

        setupGlobalMonitor()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.retryIfTrusted()
        }
    }

    private func retryIfTrusted() {
        guard eventTap == nil, retryCount < maxRetries else { return }
        retryCount += 1
        if AXIsProcessTrusted() {
            createEventTap()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.retryIfTrusted()
            }
        }
    }

    private func createEventTap() {
        guard eventTap == nil else { return }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotkeyEventCallback,
            userInfo: refcon
        ) else {
            Log.info("[HotkeyManager] CGEvent tap failed, NSEvent fallback only")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func setupGlobalMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSEventFlags(event)
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
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
        pendingPrimaryStart?.cancel()
        pendingPrimaryStart = nil
    }

    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags
        let primaryPressed = isKeyPressed(settings.hotkeyType, flags: flags)
        let translationModifierPressed = isKeyPressed(settings.translationHotkeyModifier, flags: flags)
        DispatchQueue.main.async { [weak self] in
            self?.processPhysicalKeyState(
                primaryPressed: primaryPressed,
                translationModifierPressed: translationModifierPressed
            )
        }
    }

    private func handleNSEventFlags(_ event: NSEvent) {
        guard eventTap == nil else { return }
        let flags = event.modifierFlags
        let primaryPressed = isKeyPressed(settings.hotkeyType, flags: flags)
        let translationModifierPressed = isKeyPressed(settings.translationHotkeyModifier, flags: flags)
        if Thread.isMainThread {
            processPhysicalKeyState(
                primaryPressed: primaryPressed,
                translationModifierPressed: translationModifierPressed
            )
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.processPhysicalKeyState(
                    primaryPressed: primaryPressed,
                    translationModifierPressed: translationModifierPressed
                )
            }
        }
    }

    func processPhysicalKeyState(
        primaryPressed: Bool,
        translationModifierPressed: Bool
    ) {
        if primaryPressed, !previousPrimaryPressed {
            handlePrimaryPressed(translationModifierPressed: translationModifierPressed)
        } else if primaryPressed, previousPrimaryPressed {
            handleModifierChangeWhilePrimaryPressed(
                translationModifierPressed: translationModifierPressed
            )
        } else if !primaryPressed, previousPrimaryPressed {
            handlePrimaryReleased()
        }

        previousPrimaryPressed = primaryPressed
        previousTranslationModifierPressed = translationModifierPressed
    }

    private func handlePrimaryPressed(translationModifierPressed: Bool) {
        suppressUntilPrimaryRelease = false
        if translationModifierPressed {
            beginGesture(.translation)
            return
        }

        schedulePrimaryGesture()
    }

    private func handleModifierChangeWhilePrimaryPressed(
        translationModifierPressed: Bool
    ) {
        guard !suppressUntilPrimaryRelease else { return }

        if activeGestureAction == nil, translationModifierPressed {
            pendingPrimaryStart?.cancel()
            pendingPrimaryStart = nil
            beginGesture(.translation)
        } else if activeGestureAction == .translation,
                  previousTranslationModifierPressed,
                  !translationModifierPressed {
            endGesture(.translation)
            activeGestureAction = nil
            suppressUntilPrimaryRelease = true
        }
    }

    private func handlePrimaryReleased() {
        if pendingPrimaryStart != nil {
            pendingPrimaryStart?.cancel()
            pendingPrimaryStart = nil
            if settings.activationMode != .longPress {
                beginGesture(.dictation)
            }
        }

        if let action = activeGestureAction {
            endGesture(action)
        }
        activeGestureAction = nil
        suppressUntilPrimaryRelease = false
    }

    private func schedulePrimaryGesture() {
        pendingPrimaryStart?.cancel()
        pendingPrimaryStart = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.translationChordGraceNanoseconds ?? 0)
            guard let self, !Task.isCancelled else { return }
            self.pendingPrimaryStart = nil
            guard self.previousPrimaryPressed,
                  self.activeGestureAction == nil,
                  !self.suppressUntilPrimaryRelease else {
                return
            }
            self.beginGesture(.dictation)
        }
    }

    private func beginGesture(_ action: HotkeyAction) {
        activeGestureAction = action
        activationController.beginGesture(action)
    }

    private func endGesture(_ action: HotkeyAction) {
        activationController.endGesture(action)
    }

    private func isKeyPressed(_ key: HotkeyType, flags: CGEventFlags) -> Bool {
        switch key {
        case .ctrl: return flags.contains(.maskControl)
        case .shift: return flags.contains(.maskShift)
        case .option: return flags.contains(.maskAlternate)
        case .fn: return flags.contains(.maskSecondaryFn)
        }
    }

    private func isKeyPressed(_ key: HotkeyType, flags: NSEvent.ModifierFlags) -> Bool {
        switch key {
        case .ctrl: return flags.contains(.control)
        case .shift: return flags.contains(.shift)
        case .option: return flags.contains(.option)
        case .fn: return flags.contains(.function)
        }
    }

    deinit { stop() }
}

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passRetained(event) }
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

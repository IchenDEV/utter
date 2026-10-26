import Carbon

@MainActor
final class CarbonOverlayShortcuts: OverlayShortcutRegistration {
    static let signature: OSType = 0x55544844 // UTHD
    var onPress: ((UInt32) -> Void)?
    private var handler: EventHandlerRef?
    private var keys: [UInt32: EventHotKeyRef] = [:]
    private var closed = false

    func register(_ key: OverlayShortcuts.Key, id: UInt32) -> Bool {
        guard !closed, installHandler() else { return false }
        let code = key == .cancel ? kVK_Escape : kVK_ANSI_Z
        let modifiers = key == .cancel ? 0 : cmdKey | optionKey
        var reference: EventHotKeyRef?
        // Do not share a chord with another global registration, or claim a failed shortcut is available.
        let status = RegisterEventHotKey(UInt32(code), UInt32(modifiers),
            EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &reference)
        guard status == noErr, let reference else { return false }
        keys[id] = reference
        return true
    }

    private func installHandler() -> Bool {
        if handler != nil { return true }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                Unmanaged<CarbonOverlayShortcuts>.fromOpaque(context).takeUnretainedValue().handle(event)
            }
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr
    }

    /// Decoding is also exercised with a real owned Carbon event, without registering global keys in tests.
    func handle(_ event: EventRef) -> OSStatus {
        guard !closed, GetEventClass(event) == OSType(kEventClassKeyboard),
              GetEventKind(event) == UInt32(kEventHotKeyPressed) else { return OSStatus(eventNotHandledErr) }
        var hotkey = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkey) == noErr,
              hotkey.signature == Self.signature else { return OSStatus(eventNotHandledErr) }
        onPress?(hotkey.id)
        return noErr
    }

    func unregister(_ id: UInt32) {
        if let reference = keys.removeValue(forKey: id) { UnregisterEventHotKey(reference) }
    }

    func close() {
        guard !closed else { return }
        closed = true
        for reference in keys.values { UnregisterEventHotKey(reference) }
        keys.removeAll(); onPress = nil
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}

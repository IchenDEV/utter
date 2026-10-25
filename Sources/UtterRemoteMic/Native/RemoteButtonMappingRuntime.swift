import Foundation
import UtterContracts

/// The platform pieces of the button mapping, replaceable in tests.
@MainActor
struct RemoteButtonMappingParts {
    var source: any RemotePressSourcing
    var poster: any SyntheticInputPosting
    var isSecureInput: () -> Bool
    var symbolicHotKeys: () -> [String: Any]?

    static func system() -> RemoteButtonMappingParts {
        RemoteButtonMappingParts(
            source: RemoteHIDPressSource(), poster: SystemInputPoster(),
            isSecureInput: { SystemInputPoster.isSecureInput },
            symbolicHotKeys: { SystemInputPoster.symbolicHotKeys() }
        )
    }
}

/// Applies the settings to the voice-key remap and the button mapping in the one order that never
/// leaves a key silenced without an observer: the mapping goes off before the remap is restored,
/// and comes on after it.
@MainActor
final class RemoteButtonMappingRuntime {
    private let keys: RemoteKeyMappingController
    private let coordinator: RemoteButtonMappingCoordinator
    private let executor: ButtonActionExecutor
    private var wasWanted = false

    var onStateChange: ((RemoteButtonMappingState) -> Void)? {
        get { coordinator.onStateChange }
        set { coordinator.onStateChange = newValue }
    }

    init(parts: RemoteButtonMappingParts, keys: RemoteKeyMappingController, log: Log) {
        self.keys = keys
        coordinator = RemoteButtonMappingCoordinator(source: parts.source, keys: keys)
        executor = ButtonActionExecutor(
            poster: parts.poster, isSecureInput: parts.isSecureInput,
            showDesktopShortcut: { ButtonActionPlanner.resolveShowDesktop(symbolicHotKeys: parts.symbolicHotKeys()) },
            log: { log.info($0) }
        )
        coordinator.onCommand = { [executor] in executor.perform($0) }
    }

    /// `userChange`: the setting was just changed by the user, so turning the mapping on may ask the
    /// system for permission. Applying the stored settings at launch never does.
    func apply(_ values: SettingsValues, userChange: Bool) {
        let remap = values.remoteKeyRemapEnabled
        if !remap { applyMapping(values, wanted: false, userChange: userChange) }
        keys.setEnabled(remap)
        if remap { applyMapping(values, wanted: values.remoteButtonMappingEnabled, userChange: userChange) }
    }

    func keyRemapChanged() { coordinator.keyRemapChanged() }
    func requestPermission() { coordinator.requestPermission() }
    func refresh() { coordinator.refresh() }

    func shutdown() {
        coordinator.setEnabled(false)
        keys.setEnabled(false)
        wasWanted = false
    }

    private func applyMapping(_ values: SettingsValues, wanted: Bool, userChange: Bool) {
        coordinator.setProfile(values.remoteButtonProfile)
        coordinator.setEnabled(wanted, prompt: userChange && wanted && !wasWanted)
        wasWanted = wanted
    }
}

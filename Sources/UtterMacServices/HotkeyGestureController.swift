import Foundation
import UtterContracts

package final class HotkeyGestureController {
    private let settings: () -> SettingsValues
    private let onStart: (HotkeyAction) -> Void
    private let onStop: (HotkeyAction) -> Void
    private let onPromote: (HotkeyPromotion) -> Bool
    private let onCancel: () -> Void
    private let now: () -> Duration
    private var pressSettings: SettingsValues?
    private var captureSettings: SettingsValues?
    private var pressedAt: Duration?
    private var physicalAction: HotkeyAction?
    private var primaryPressed = false
    private var modifierPressed = false
    private var suppressed = false
    package private(set) var captureID: UUID?

    private lazy var activation = HotkeyActivationController(settings: { [weak self] in self?.keySettings ?? SettingsValues() }, onStart: { [weak self] action in
        guard let self else { return }
        self.captureSettings = self.keySettings
        self.captureID = UUID()
        self.onStart(action)
    }, onStop: { [weak self] action in
        guard let self else { return }
        defer { self.captureID = nil }
        self.captureSettings = nil
        self.onStop(action)
    }, onPromote: onPromote, onCancel: { [weak self] in
        guard let self else { return }
        defer { self.captureID = nil }
        self.captureSettings = nil
        self.onCancel()
    }, now: now)

    package init(settings: @escaping () -> SettingsValues, onStart: @escaping (HotkeyAction) -> Void,
                 onStop: @escaping (HotkeyAction) -> Void, onPromote: @escaping (HotkeyPromotion) -> Bool,
                 onCancel: @escaping () -> Void, now: (() -> Duration)? = nil) {
        self.settings = settings; self.onStart = onStart; self.onStop = onStop
        self.onPromote = onPromote; self.onCancel = onCancel
        let origin = ContinuousClock.now
        self.now = now ?? { origin.duration(to: ContinuousClock.now) }
    }

    package var keySettings: SettingsValues { pressSettings ?? captureSettings ?? settings() }
    package var isPrimaryHeld: Bool { primaryPressed }

    package func process(primaryPressed pressed: Bool, translationModifierPressed modifier: Bool, systemCombination: Bool = false) {
        defer { primaryPressed = pressed; modifierPressed = modifier }
        if pressed, systemCombination {
            if !primaryPressed { pressSettings = keySettings }
            activation.cancelGesture()
            suppressed = true
            physicalAction = nil
            return
        }
        if pressed, !primaryPressed {
            guard !suppressed else { return }
            pressSettings = keySettings
            pressedAt = now()
            let action: HotkeyAction = modifier ? .translation : .dictation
            physicalAction = action
            activation.beginGesture(action)
        } else if pressed, !suppressed, modifier, !modifierPressed,
                  physicalAction == .dictation, let pressedAt {
            let elapsed = now() - pressedAt
            let promotion: HotkeyPromotion = elapsed <= .seconds(1) ? .chordClassification : .recording
            if elapsed >= .zero, activation.promoteToTranslation(promotion) {
                physicalAction = .translation
            }
        } else if !pressed, primaryPressed {
            if let physicalAction, !suppressed { activation.endGesture(physicalAction) }
            pressSettings = nil; pressedAt = nil; physicalAction = nil; suppressed = false
        }
    }

    package func reset() {
        activation.cancelGesture()
        pressSettings = nil; captureSettings = nil; pressedAt = nil; physicalAction = nil
        primaryPressed = false; modifierPressed = false; suppressed = false
    }
}

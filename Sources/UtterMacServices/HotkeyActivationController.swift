import UtterContracts
import Foundation

package final class HotkeyActivationController {
    private let settings: () -> SettingsValues
    private let onStart: (HotkeyAction) -> Void
    private let onStop: (HotkeyAction) -> Void
    private let onPromote: (HotkeyPromotion) -> Bool
    private let onCancel: () -> Void
    private let now: () -> Duration

    private var gestureMode: ActivationMode?
    private var lastPressTime: Duration?
    private var lastTapAction: HotkeyAction?
    private var tapCount = 0
    private var activeCaptureAction: HotkeyAction?

    package init(
        settings: @escaping () -> SettingsValues,
        onStart: @escaping (HotkeyAction) -> Void,
        onStop: @escaping (HotkeyAction) -> Void,
        onPromote: @escaping (HotkeyPromotion) -> Bool = { _ in false },
        onCancel: @escaping () -> Void = {},
        now: (() -> Duration)? = nil
    ) {
        self.settings = settings
        self.onStart = onStart
        self.onStop = onStop
        self.onPromote = onPromote
        self.onCancel = onCancel
        let origin = ContinuousClock.now
        self.now = now ?? { origin.duration(to: ContinuousClock.now) }
    }

    package func beginGesture(_ action: HotkeyAction) {
        let mode = settings().activationMode
        gestureMode = mode
        switch mode {
        case .longPress:
            startCapture(action)
        case .doubleTap:
            registerDoubleTap(action)
        case .toggle:
            toggleCapture(action)
        }
    }

    package func endGesture(_ action: HotkeyAction) {
        guard gestureMode == .longPress, activeCaptureAction == action else { return }
        stopCapture(action)
    }

    package func promoteToTranslation(_ promotion: HotkeyPromotion) -> Bool {
        if activeCaptureAction == .dictation {
            guard onPromote(promotion) else { return false }
            activeCaptureAction = .translation
            return true
        }
        if promotion == .chordClassification, activeCaptureAction == nil,
           gestureMode == .doubleTap, tapCount == 1, lastTapAction == .dictation {
            lastTapAction = .translation
            return true
        }
        return false
    }

    package func cancelGesture() {
        if activeCaptureAction != nil { activeCaptureAction = nil; onCancel() }
        clearGesture()
    }

    package func reset() {
        if let action = activeCaptureAction { stopCapture(action) }
        clearGesture()
    }

    private func clearGesture() {
        gestureMode = nil
        lastPressTime = nil
        lastTapAction = nil
        tapCount = 0
    }

    private func registerDoubleTap(_ action: HotkeyAction) {
        let time = now()
        if lastTapAction == action, let lastPressTime, time >= lastPressTime,
           time - lastPressTime < .seconds(settings().tapInterval) {
            tapCount += 1
        } else {
            tapCount = 1
        }
        lastTapAction = action
        lastPressTime = time

        if tapCount >= 2 {
            tapCount = 0
            toggleCapture(action)
        }
    }

    private func toggleCapture(_ action: HotkeyAction) {
        if let activeCaptureAction {
            stopCapture(activeCaptureAction)
        } else {
            startCapture(action)
        }
    }

    private func startCapture(_ action: HotkeyAction) {
        guard activeCaptureAction == nil else { return }
        activeCaptureAction = action
        onStart(action)
    }

    private func stopCapture(_ action: HotkeyAction) {
        guard activeCaptureAction == action else { return }
        activeCaptureAction = nil
        onStop(action)
    }
}

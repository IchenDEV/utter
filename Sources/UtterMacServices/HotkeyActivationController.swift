import UtterContracts
import Foundation

package final class HotkeyActivationController {
    private let settings: () -> SettingsValues
    private let onStart: (HotkeyAction) -> Void
    private let onStop: (HotkeyAction) -> Void

    private var gestureMode: ActivationMode?
    private var lastPressTime: Date = .distantPast
    private var lastTapAction: HotkeyAction?
    private var tapCount = 0
    private var activeCaptureAction: HotkeyAction?

    package init(
        settings: @escaping () -> SettingsValues,
        onStart: @escaping (HotkeyAction) -> Void,
        onStop: @escaping (HotkeyAction) -> Void
    ) {
        self.settings = settings
        self.onStart = onStart
        self.onStop = onStop
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
        guard gestureMode == .longPress else { return }
        stopCapture(action)
    }

    package func reset() {
        if let action = activeCaptureAction { stopCapture(action) }
        gestureMode = nil
        lastPressTime = .distantPast
        lastTapAction = nil
        tapCount = 0
    }

    private func registerDoubleTap(_ action: HotkeyAction) {
        let now = Date()
        if lastTapAction == action, now.timeIntervalSince(lastPressTime) < settings().tapInterval {
            tapCount += 1
        } else {
            tapCount = 1
        }
        lastTapAction = action
        lastPressTime = now

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

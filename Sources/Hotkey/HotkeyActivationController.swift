import Foundation

enum HotkeyAction: Equatable {
    case dictation
    case translation
}

final class HotkeyActivationController {
    private let settings: AppSettings
    private let onStart: (HotkeyAction) -> Void
    private let onStop: (HotkeyAction) -> Void

    private var lastPressTime: Date = .distantPast
    private var lastTapAction: HotkeyAction?
    private var tapCount = 0
    private var activeCaptureAction: HotkeyAction?

    init(
        settings: AppSettings,
        onStart: @escaping (HotkeyAction) -> Void,
        onStop: @escaping (HotkeyAction) -> Void
    ) {
        self.settings = settings
        self.onStart = onStart
        self.onStop = onStop
    }

    func beginGesture(_ action: HotkeyAction) {
        switch settings.activationMode {
        case .longPress:
            startCapture(action)
        case .doubleTap:
            registerDoubleTap(action)
        case .toggle:
            toggleCapture(action)
        }
    }

    func endGesture(_ action: HotkeyAction) {
        guard settings.activationMode == .longPress else { return }
        stopCapture(action)
    }

    private func registerDoubleTap(_ action: HotkeyAction) {
        let now = Date()
        if lastTapAction == action, now.timeIntervalSince(lastPressTime) < settings.tapInterval {
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

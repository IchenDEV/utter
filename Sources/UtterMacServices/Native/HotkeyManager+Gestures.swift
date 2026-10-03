import Foundation
import UtterContracts

@MainActor
extension HotkeyManager {
    package func processPhysicalKeyState(
        primaryPressed: Bool,
        translationModifierPressed: Bool
    ) {
        guard !isClosed else { return }
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

    func handlePrimaryPressed(translationModifierPressed: Bool) {
        suppressUntilPrimaryRelease = false
        if translationModifierPressed {
            beginGesture(.translation)
            return
        }

        schedulePrimaryGesture()
    }

    func handleModifierChangeWhilePrimaryPressed(
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

    func handlePrimaryReleased() {
        if pendingPrimaryStart != nil {
            pendingPrimaryStart?.cancel()
            pendingPrimaryStart = nil
            if settings().activationMode != .longPress {
                beginGesture(.dictation)
            }
        }

        if let action = activeGestureAction {
            endGesture(action)
        }
        activeGestureAction = nil
        suppressUntilPrimaryRelease = false
    }

    func schedulePrimaryGesture() {
        pendingPrimaryStart?.cancel()
        pendingPrimaryStart = ownedTask { [weak self] in
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

    func beginGesture(_ action: HotkeyAction) {
        activeGestureAction = action
        activationController.beginGesture(action)
    }

    func endGesture(_ action: HotkeyAction) {
        activationController.endGesture(action)
    }

}

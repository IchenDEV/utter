import CoreGraphics
import Foundation
import UtterContracts

@MainActor
extension HotkeyManager {
    package func processPhysicalKeyState(primaryPressed: Bool, translationModifierPressed: Bool, systemCombination: Bool = false) {
        guard !isClosed else { return }
        gestures.process(primaryPressed: primaryPressed, translationModifierPressed: translationModifierPressed,
            systemCombination: systemCombination)
    }

    func handleNavigationKey(_ keyCode: UInt16) {
        guard !isClosed, gestures.isPrimaryHeld,
              [115, 116, 117, 119, 121, 123, 124, 125, 126].contains(keyCode) else { return }
        gestures.process(primaryPressed: true, translationModifierPressed: false, systemCombination: true)
    }

    func hasOtherModifiers(_ flags: CGEventFlags) -> Bool {
        let values = gestures.keySettings
        let allowed = flag(for: values.hotkeyType).union(flag(for: values.translationHotkeyModifier))
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        return !flags.intersection(modifiers).subtracting(allowed).isEmpty
    }

    private func flag(for key: HotkeyType) -> CGEventFlags {
        switch key {
        case .ctrl: return .maskControl
        case .shift: return .maskShift
        case .option: return .maskAlternate
        case .fn: return .maskSecondaryFn
        }
    }
}

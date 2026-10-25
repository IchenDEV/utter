import Foundation

enum DeliveryPath: String {
    case accessibility
    case paste
    case keyPress
    case clipboardOnly
}

enum DeliveryTargetKind: String {
    case web
    case native
}

enum DeliveryKillSwitch {
    static let webEditorPasteDisabledKey = "deliveryWebEditorPasteDisabled"

    /// Hidden default, read on every delivery so `defaults write` needs no new build.
    static func webEditorPasteEnabled(_ defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: webEditorPasteDisabledKey)
    }
}

extension DeliveryCompletion {
    /// Never includes the dictated text, the reason text, or the anchor.
    var logSummary: String {
        "Delivery completed: \(disposition), confirmation: \(confirmation.rawValue), path: \(path?.rawValue ?? "none"), target: \(target.rawValue)"
    }
}

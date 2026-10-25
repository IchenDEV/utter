import Foundation
import UtterContracts

/// Turns a `SyntheticInput` into a real event or call. `false`: it could not be posted.
@MainActor
protocol SyntheticInputPosting: AnyObject {
    func post(_ input: SyntheticInput) -> Bool
}

/// Performs what a recognized gesture is bound to. The only things it can do are key events, media keys
/// and opening an application by bundle identifier: there is no shell, script or URL action.
/// While secure input is on (a password field has the keyboard) nothing keyboard-shaped is posted.
/// Logs carry button, trigger and action kind only, never a key, an app or any text.
@MainActor
final class ButtonActionExecutor {
    private let poster: any SyntheticInputPosting
    private let isSecureInput: () -> Bool
    private let showDesktopShortcut: () -> KeyboardShortcut?
    private let log: (String) -> Void

    init(
        poster: any SyntheticInputPosting,
        isSecureInput: @escaping () -> Bool,
        showDesktopShortcut: @escaping () -> KeyboardShortcut?,
        log: @escaping (String) -> Void
    ) {
        self.poster = poster
        self.isSecureInput = isSecureInput
        self.showDesktopShortcut = showDesktopShortcut
        self.log = log
    }

    func perform(_ command: ButtonCommand) {
        let kind = Self.kind(of: command.action)
        let label = "\(command.button.rawValue) \(command.trigger.rawValue) -> \(kind)"
        let inputs = ButtonActionPlanner.inputs(
            for: command.action, button: command.button, showDesktop: showDesktopShortcut()
        )
        guard !inputs.isEmpty else {
            log("[RemoteButtons] \(label): nothing to post")
            return
        }
        if inputs.contains(where: \.isKeyboard), isSecureInput() {
            log("[RemoteButtons] \(label): dropped, secure input is on")
            return
        }
        var failed = false
        for input in inputs {
            if !failed {
                failed = !poster.post(input)
            } else if case .key(_, false, _, true) = input {
                // A modifier already pressed must still be released, or it stays held system-wide.
                _ = poster.post(input)
            }
        }
        log("[RemoteButtons] \(label)" + (failed ? ": could not be performed" : ""))
    }

    private static func kind(of action: ButtonAction) -> String {
        switch action {
        case .native: "native"
        case .key: "key"
        case .system: "system"
        case .showDesktop: "showDesktop"
        case .appSwitcher: "appSwitcher"
        case .openApp: "openApp"
        }
    }
}

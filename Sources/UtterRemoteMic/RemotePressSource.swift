import Foundation
import UtterContracts

/// Whether presses of the remote can be observed right now.
package enum PressSourceStatus: Equatable, Sendable {
    case stopped
    /// Input Monitoring is not granted. `canAsk`: the system has not been asked, so a prompt can appear.
    case needsPermission(canAsk: Bool)
    /// Reported as granted, yet opening is refused (`kIOReturnNotPermitted`); a restart may be needed.
    case needsRestart
    /// Open, but no matching HID device is present.
    case waitingForRemote
    /// Open with at least one matching device: every press arrives, below any device key mapping.
    case live
    /// Opening failed for another reason.
    case failed
}

/// Observes the remote's raw key edges without seizing the device. Edges arrive below a device
/// `UserKeyMapping`, so a silenced key is still seen.
@MainActor
protocol RemotePressSourcing: AnyObject {
    /// A press (`true`) or release (`false`) of a mappable button.
    var onEdge: ((RemoteButton, Bool) -> Void)? { get set }
    /// A matching device appeared or went away; the status may have changed.
    var onDevicesChanged: (() -> Void)? { get set }
    /// Idempotent. Opens the source when permission is granted and asks the system for permission
    /// only when `prompt` is true and it has never been asked. Never opens without permission,
    /// because a first open silently turns "not asked" into "denied" without showing a prompt.
    func refresh(prompt: Bool) -> PressSourceStatus
    func stop()
}

/// What one raw HID value means for the remote's keys.
enum RemoteButtonEdge {
    /// Only a named keyboard-page element with value 1 or 0 is an edge. The remote also reports the
    /// same key through an array element (usage `0xFFFFFFFF`, value = the usage), which must not be
    /// counted a second time.
    static func decode(usagePage: Int, usage: Int, value: Int) -> (button: RemoteButton, isDown: Bool)? {
        guard value == 0 || value == 1, let button = RemoteButton(usagePage: usagePage, usage: usage) else { return nil }
        return (button, value == 1)
    }
}

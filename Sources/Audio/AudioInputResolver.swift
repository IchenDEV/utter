import Foundation

enum AudioInputResolution: Equatable {
    case use(uid: String)
    case unavailable
}

enum MicFailoverAction: Equatable {
    case keep
    case switchTo(uid: String)
    case fail
}

/// Chooses a usable input device without touching CoreAudio, so the policy is
/// deterministic and unit-testable.
///
/// A device is unusable only when it is the built-in microphone and the lid is
/// closed, which is the case Apple disconnects in hardware.
enum AudioInputResolver {
    static func resolve(
        devices: [AudioInputDevice],
        preferredUID: String?,
        systemDefaultUID: String?,
        lidClosed: Bool
    ) -> AudioInputResolution {
        if let preferredUID,
           let device = devices.first(where: { $0.uid == preferredUID }),
           isUsable(device, lidClosed: lidClosed) {
            return .use(uid: device.uid)
        }
        if let systemDefaultUID,
           let device = devices.first(where: { $0.uid == systemDefaultUID }),
           isUsable(device, lidClosed: lidClosed) {
            return .use(uid: device.uid)
        }
        if let external = devices.first(where: { !$0.isBuiltIn && isUsable($0, lidClosed: lidClosed) }) {
            return .use(uid: external.uid)
        }
        if let fallback = devices.first(where: { isUsable($0, lidClosed: lidClosed) }) {
            return .use(uid: fallback.uid)
        }
        return .unavailable
    }

    static func isUsable(_ device: AudioInputDevice, lidClosed: Bool) -> Bool {
        !(device.isBuiltIn && lidClosed)
    }
}

/// Decides what a running capture should do when re-checking its input.
///
/// Keeps the active device whenever it is still usable so a reopened lid does
/// not cause churn; switches only when the active device became unusable.
enum MicFailoverDecision {
    static func decide(
        activeUID: String?,
        devices: [AudioInputDevice],
        preferredUID: String?,
        systemDefaultUID: String?,
        lidClosed: Bool
    ) -> MicFailoverAction {
        if let activeUID,
           let active = devices.first(where: { $0.uid == activeUID }),
           AudioInputResolver.isUsable(active, lidClosed: lidClosed) {
            return .keep
        }
        switch AudioInputResolver.resolve(
            devices: devices,
            preferredUID: preferredUID,
            systemDefaultUID: systemDefaultUID,
            lidClosed: lidClosed
        ) {
        case .unavailable:
            return .fail
        case .use(let uid):
            return uid == activeUID ? .keep : .switchTo(uid: uid)
        }
    }
}

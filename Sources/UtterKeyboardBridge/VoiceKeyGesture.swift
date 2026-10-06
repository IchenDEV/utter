import Foundation

/// Maps raw touches on the keyboard's voice key to bridge actions.
///
/// A press starts recording immediately so a held press loses no speech. Releasing a hold ends it; a short
/// press only starts, and the next tap ends it. A hold released before the start is confirmed cancels, so
/// recording can never begin after the finger is gone.
public struct VoiceKeyGesture: Equatable, Sendable {
    public enum Voice: Equatable, Sendable {
        case idle
        /// A start was requested but the main app has not reported recording yet.
        case starting
        case recording
        /// Recognizing or otherwise busy: the key does nothing.
        case finishing
    }

    public enum Output: Equatable, Sendable { case none, start, stop, cancel }

    public static let holdThreshold: TimeInterval = 0.4

    private enum Origin { case started, stopping, ignored }
    private var origin: Origin?
    private var pressedAt: TimeInterval = 0

    public init() {}

    public mutating func press(at time: TimeInterval, voice: Voice) -> Output {
        guard origin == nil else { return .none }
        pressedAt = time
        switch voice {
        case .idle: origin = .started; return .start
        case .recording: origin = .stopping; return .none
        case .starting, .finishing: origin = .ignored; return .none
        }
    }

    /// `inside` is false when the finger lifted outside the key; `cancelled` when the system took the touch.
    public mutating func release(at time: TimeInterval, voice: Voice, inside: Bool = true, cancelled: Bool = false) -> Output {
        defer { origin = nil }
        switch origin {
        case .started where time - pressedAt >= Self.holdThreshold:
            switch voice {
            case .recording: return .stop
            case .starting: return .cancel
            case .idle, .finishing: return .none
            }
        case .stopping where inside && !cancelled && voice == .recording:
            return .stop
        case .started, .stopping, .ignored, nil:
            return .none
        }
    }

    /// Assistive activation (VoiceOver double tap) has tap semantics.
    public func activate(voice: Voice) -> Output {
        switch voice {
        case .idle: return .start
        case .recording: return .stop
        case .starting, .finishing: return .none
        }
    }

    public mutating func reset() { origin = nil }
}

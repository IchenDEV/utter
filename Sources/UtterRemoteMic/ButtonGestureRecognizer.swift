import Foundation
import UtterContracts

package enum ButtonGesture: Equatable, Sendable {
    case single, double, long
}

package struct GestureBindings: Equatable, Sendable {
    package var hasDouble: Bool
    package var hasLong: Bool

    package init(hasDouble: Bool, hasLong: Bool) {
        self.hasDouble = hasDouble
        self.hasLong = hasLong
    }
}

package struct GestureTiming: Equatable, Sendable {
    /// Second press must arrive strictly less than this after the first press went down.
    package var doubleWindow: TimeInterval
    package var longThreshold: TimeInterval
    /// A press with no release for this long is closed, so a missed release cannot stick.
    package var holdCeiling: TimeInterval

    package init(doubleWindow: TimeInterval = 0.4, longThreshold: TimeInterval = 0.5, holdCeiling: TimeInterval = 10) {
        self.doubleWindow = doubleWindow
        self.holdCeiling = holdCeiling
        self.longThreshold = min(longThreshold, holdCeiling)
    }
}

package struct GestureFiring: Equatable, Sendable {
    package var gesture: ButtonGesture
    /// When the gesture was decided, which can be earlier than the call that reported it.
    package var at: TimeInterval

    package init(_ gesture: ButtonGesture, at: TimeInterval) {
        self.gesture = gesture
        self.at = at
    }
}

/// One button's gesture state. Pure: time only enters through the arguments, and a caller that
/// owns a timer wakes at `nextDeadline` and calls `advance(to:)`.
///
/// A trigger is bound only when its action is not `native`. Rules (spec erratum 1):
/// - neither double nor long bound: single fires at press;
/// - long only: single fires at release if held less than the threshold, long fires once at the
///   threshold while still held and its release is consumed;
/// - double bound: a press released within the window waits for a second press; the second press
///   fires double at once and its release is consumed; with no second press, single fires when the
///   window ends. A press still held at the end of the window is resolved at release, so a key that
///   is down never fires a single;
/// - with both, a first press held to the threshold is a long press and fires nothing else.
package struct ButtonGestureRecognizer: Equatable, Sendable {
    private enum Phase: Equatable {
        case idle
        /// `consumed`: this press already produced its gesture, so its release does nothing.
        case down(at: TimeInterval, consumed: Bool)
        case waitingForSecond(firstDownAt: TimeInterval)
    }

    package let bindings: GestureBindings
    package let timing: GestureTiming
    private var phase: Phase = .idle

    package init(bindings: GestureBindings, timing: GestureTiming = GestureTiming()) {
        self.bindings = bindings
        self.timing = timing
    }

    package var nextDeadline: TimeInterval? {
        switch phase {
        case .idle:
            return nil
        case .down(let at, let consumed):
            let ceiling = at + timing.holdCeiling
            return !consumed && bindings.hasLong ? min(at + timing.longThreshold, ceiling) : ceiling
        case .waitingForSecond(let first):
            return first + timing.doubleWindow
        }
    }

    package mutating func press(at time: TimeInterval) -> [GestureFiring] {
        var fired = advance(to: time)
        switch phase {
        case .idle:
            if !bindings.hasDouble && !bindings.hasLong {
                fired.append(GestureFiring(.single, at: time))
                phase = .down(at: time, consumed: true)
            } else {
                phase = .down(at: time, consumed: false)
            }
        case .waitingForSecond:
            fired.append(GestureFiring(.double, at: time))
            phase = .down(at: time, consumed: true)
        case .down:
            break
        }
        return fired
    }

    package mutating func release(at time: TimeInterval) -> [GestureFiring] {
        var fired = advance(to: time)
        guard case .down(let at, let consumed) = phase else { return fired }
        if consumed {
            phase = .idle
        } else if bindings.hasDouble && time - at < timing.doubleWindow {
            phase = .waitingForSecond(firstDownAt: at)
        } else {
            fired.append(GestureFiring(.single, at: time))
            phase = .idle
        }
        return fired
    }

    /// Fires every deadline that has passed by `time`, in order.
    package mutating func advance(to time: TimeInterval) -> [GestureFiring] {
        var fired: [GestureFiring] = []
        while let deadline = nextDeadline, deadline <= time {
            switch phase {
            case .idle:
                return fired
            case .down(let at, let consumed):
                if !consumed && bindings.hasLong {
                    fired.append(GestureFiring(.long, at: deadline))
                    phase = .down(at: at, consumed: true)
                } else {
                    phase = .idle
                }
            case .waitingForSecond:
                fired.append(GestureFiring(.single, at: deadline))
                phase = .idle
            }
        }
        return fired
    }
}

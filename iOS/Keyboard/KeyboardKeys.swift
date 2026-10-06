import SwiftUI
import UIKit

/// The system's keycaps are translucent white veils over the keyboard backdrop, so they take on the colour
/// behind them. Measured over five backdrops on the simulator: about 0.85 white in light, 0.165 white in dark.
enum KeyColors {
    static let cap = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.165) : UIColor(white: 1, alpha: 0.85) }
    static let capPressed = UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.27) : UIColor(white: 0.80, alpha: 0.5)
    }
    /// Text and icons that need emphasis on a key; at least 4.5:1 against the key fill.
    static let accent = UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(red: 0.50, green: 0.74, blue: 1.0, alpha: 1) : UIColor(red: 0, green: 0.34, blue: 0.76, alpha: 1)
    }
    /// Filled action key, like the system's blue Search/Go key.
    static let action = UIColor(red: 0, green: 0.34, blue: 0.76, alpha: 1)
    static let recording = UIColor(red: 0.78, green: 0.14, blue: 0.12, alpha: 1)
}

struct KeyStyle: ButtonStyle {
    var radius: CGFloat
    var fill: UIColor = KeyColors.cap
    var pressed: UIColor = KeyColors.capPressed

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(uiColor: configuration.isPressed ? pressed : fill)))
    }
}

/// Transparent control laid over a key to report raw touch down and up, which SwiftUI buttons do not
/// expose. It is the key's only accessibility element, and assistive activation has tap semantics.
struct PressSurface: UIViewRepresentable {
    var identifier: String
    var label: String
    var enabled: Bool
    var onPress: () -> Void
    var onRelease: (_ inside: Bool, _ cancelled: Bool) -> Void
    var onActivate: () -> Void

    func makeUIView(context: Context) -> PressControl { PressControl() }

    // `isEnabled` stays true: disabling a control mid-touch cancels tracking and would lose the release
    // that ends a hold. The gesture state machine ignores presses that are not allowed.
    func updateUIView(_ view: PressControl, context: Context) {
        view.onPress = onPress; view.onRelease = onRelease; view.onActivate = onActivate
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = label
        view.accessibilityTraits = enabled ? .button : [.button, .notEnabled]
    }

    static func dismantleUIView(_ view: PressControl, coordinator: ()) { view.abandonTouch() }
}

final class PressControl: UIControl {
    var onPress: () -> Void = {}
    var onRelease: (Bool, Bool) -> Void = { _, _ in }
    var onActivate: () -> Void = {}
    private var touching = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        isExclusiveTouch = true
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        touching = true; onPress(); return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard touching else { return }
        touching = false
        let inside = touch.map { bounds.insetBy(dx: -24, dy: -24).contains($0.location(in: self)) } ?? false
        onRelease(inside, false)
    }
    override func cancelTracking(with event: UIEvent?) {
        guard touching else { return }
        touching = false; onRelease(false, true)
    }
    func abandonTouch() {
        guard touching else { return }
        touching = false; onRelease(false, true)
    }
    override func accessibilityActivate() -> Bool { onActivate(); return true }
}

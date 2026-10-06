import UIKit
import UtterKeyboardBridge

/// The system's next-keyboard key: a flat keycap drawn inside a larger touch frame, like the system's.
final class GlobeKey: UIButton {
    private let cap = UIView()
    private let glyph = UIImageView()
    var capInsets = UIEdgeInsets.zero { didSet { setNeedsLayout() } }
    var cornerRadius: CGFloat = 9 { didSet { cap.layer.cornerRadius = cornerRadius } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        cap.isUserInteractionEnabled = false
        cap.layer.cornerCurve = .continuous
        cap.layer.cornerRadius = cornerRadius
        cap.backgroundColor = KeyColors.cap
        glyph.image = UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        glyph.tintColor = .label
        glyph.contentMode = .center
        cap.addSubview(glyph); addSubview(cap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        cap.frame = bounds.inset(by: capInsets)
        glyph.frame = cap.bounds
    }
    override var isHighlighted: Bool {
        didSet { cap.backgroundColor = isHighlighted ? KeyColors.capPressed : KeyColors.cap }
    }
}

extension KeyboardController {
    func installGlobe() {
        globe.addTarget(self, action: #selector(keyFeedback), for: .touchDown)
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globe.accessibilityLabel = L("ios.action.next_keyboard")
        globe.accessibilityIdentifier = "keyboard.globe"
        globe.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(globe)
        NSLayoutConstraint.activate([
            globeFrame.leading, globeFrame.width, globeFrame.height, globe.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Positions the globe on the system keyboard's own slot and sizes the view like the system keyboard.
    func applyMetrics() {
        guard view.bounds.width > 0 else { return }
        // iPhones inset the keys from the notch side like the system keyboard; iPads have no side insets.
        let pad = traitCollection.userInterfaceIdiom == .pad
        let left = pad ? 0 : view.safeAreaInsets.left, right = pad ? 0 : view.safeAreaInsets.right
        if let sides = hostSides {
            if sides.leading.constant != left { sides.leading.constant = left }
            if sides.trailing.constant != -right { sides.trailing.constant = -right }
        }
        let metrics = KeyboardMetrics.make(width: view.bounds.width - left - right, landscape: isLandscape, pad: pad)
        if state.metrics != metrics { state.metrics = metrics }
        let extra: CGFloat = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 120 : 0
        let height = metrics.viewHeight + extra
        if heightConstraint.constant != height { heightConstraint.constant = height }
        // The touch frame reaches 3pt left of the key and 1pt above it, as the system's does.
        let below = metrics.viewHeight - metrics.gridBottom
        globeFrame.leading.constant = left + metrics.sideMargin - 3
        globeFrame.width.constant = metrics.unitKeyWidth + metrics.gap
        globeFrame.height.constant = metrics.keyHeight + 1 + below
        globe.capInsets = UIEdgeInsets(top: 1, left: 3, bottom: below, right: metrics.gap - 3)
        globe.cornerRadius = metrics.cornerRadius
    }

    private var isLandscape: Bool {
        if let orientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation { return orientation.isLandscape }
        if let bounds = view.window?.screen.bounds { return bounds.width > bounds.height }
        return false
    }

    var voiceHandlers: VoiceKeyHandlers {
        VoiceKeyHandlers(
            press: { [weak self] in self?.voicePressed() },
            release: { [weak self] inside, cancelled in self?.voiceReleased(inside: inside, cancelled: cancelled) },
            activate: { [weak self] in self?.voiceActivated() })
    }

    private var voiceMode: VoiceKeyGesture.Voice {
        let status = state.status
        if status?.phase == .recording { return .recording }
        if status?.phase == .preparing || (state.pending && status?.isBusy != true) { return .starting }
        return status?.isBusy == true || state.pending ? .finishing : .idle
    }

    private func voicePressed() {
        state.keyDown = true
        perform(voiceGesture.press(at: ProcessInfo.processInfo.systemUptime, voice: voiceMode))
    }

    private func voiceReleased(inside: Bool, cancelled: Bool) {
        state.keyDown = false
        perform(voiceGesture.release(at: ProcessInfo.processInfo.systemUptime, voice: voiceMode, inside: inside, cancelled: cancelled))
    }

    private func voiceActivated() { perform(voiceGesture.activate(voice: voiceMode)) }

    private func perform(_ output: VoiceKeyGesture.Output) {
        guard let lease = state.lease else { return }
        switch output {
        case .none: return
        case .start: _ = prepare(id: UUID(), action: .start, lease: lease)
        case .stop: _ = prepare(id: UUID(), action: .stop, lease: lease)
        case .cancel: _ = prepare(id: UUID(), action: .cancel, lease: lease)
        }
    }
}

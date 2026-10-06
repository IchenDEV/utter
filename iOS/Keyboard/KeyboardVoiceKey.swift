import SwiftUI

struct VoiceKeyHandlers {
    var press: () -> Void
    var release: (_ inside: Bool, _ cancelled: Bool) -> Void
    var activate: () -> Void
}

/// The large dictation key. Visuals are SwiftUI; touches go through `PressSurface` so a press starts
/// recording at once and a hold can end it on release. `handlers == nil` renders the disabled key.
struct VoiceKey: View {
    enum Look: Equatable { case ready, starting, recording, finishing, unavailable, activate }

    let look: Look
    let keyDown: Bool
    let radius: CGFloat
    let identifier: String
    let label: String
    let enabled: Bool
    let handlers: VoiceKeyHandlers?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let handlers {
            visual.accessibilityHidden(true).overlay {
                PressSurface(identifier: identifier, label: label, enabled: enabled,
                             onPress: handlers.press, onRelease: handlers.release, onActivate: handlers.activate)
            }
        } else {
            Button {} label: { visual }.buttonStyle(.plain).disabled(true)
                .accessibilityLabel(label).accessibilityHint(L("ios.keyboard_enable_notice"))
        }
    }

    var visual: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(uiColor: fill))
            VStack(spacing: 6) {
                glyph
                Text(hint).font(.callout).foregroundStyle(textColor)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fill: UIColor {
        switch look {
        case .recording: KeyColors.recording
        case .ready, .starting: keyDown ? KeyColors.capPressed : KeyColors.cap
        case .finishing, .unavailable, .activate: KeyColors.cap
        }
    }
    private var textColor: Color {
        switch look {
        case .recording: .white
        case .unavailable: Color(uiColor: .secondaryLabel)
        default: Color(uiColor: .label)
        }
    }
    private var hint: String {
        switch look {
        case .ready: L("ios.keyboard.record_hint")
        case .starting: L("ios.phase.preparing")
        case .recording: L(keyDown ? "ios.keyboard.release_hint" : "ios.keyboard.stop_hint")
        case .finishing: L("ios.phase.processing")
        case .unavailable: L("ios.keyboard.record_hint")
        case .activate: L("ios.keyboard.activate_hint")
        }
    }

    @ViewBuilder private var glyph: some View {
        switch look {
        case .recording: recordingActivity
        case .starting, .finishing:
            if reduceMotion { Image(systemName: "hourglass").font(.system(size: 26)) } else { ProgressView() }
        case .ready, .activate:
            Image(systemName: "mic.fill").font(.system(size: 30, weight: .regular)).foregroundStyle(Color(uiColor: KeyColors.accent))
        case .unavailable:
            Image(systemName: "mic.fill").font(.system(size: 30, weight: .regular)).foregroundStyle(Color(uiColor: .secondaryLabel))
        }
    }

    @ViewBuilder private var recordingActivity: some View {
        if reduceMotion { wave(at: 0) }
        else {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                wave(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func wave(at time: TimeInterval) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<7) { index in
                let height = 7 + 19 * (1 + sin(time * 5.7 + Double(index) * 0.8)) / 2
                Capsule().fill(.white).frame(width: 4, height: height)
            }
        }.frame(height: 26)
    }
}

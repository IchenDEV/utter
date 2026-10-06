import SwiftUI
import UtterKeyboardBridge

@MainActor
final class KeyboardState: ObservableObject {
    @Published var status: VoiceStatus?
    @Published var lease: KeyboardLease?
    @Published var errorKey: String?
    @Published var pending = false
    @Published var standbyLive = false
}

@MainActor
struct KeyboardView: View {
    @ObservedObject var state: KeyboardState
    let prepare: (UUID, VoiceAction, KeyboardLease) -> Bool
    let insert: () -> Void
    let edit: (String?) -> Void
    private var busy: Bool { state.status?.isBusy == true || state.pending }
    private var hasResult: Bool {
        state.status?.phase == .result && state.status?.leaseID == state.lease?.id && state.status?.text.isEmpty == false
    }
    private var statusKey: String {
        if let key = state.errorKey ?? state.status?.errorKey { return key }
        if state.pending { return "ios.phase.preparing" }
        if !state.standbyLive { return "ios.standby.off" }
        return "ios.phase.\(state.status?.phase.rawValue ?? "disabled")"
    }
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var recording: Bool { state.status?.phase == .recording }
    private var available: Bool { state.standbyLive && state.lease != nil && state.status?.phase != .disabled }
    private var statusColor: Color {
        if state.errorKey != nil || state.status?.errorKey != nil || !available { return .secondary }
        if recording { return .red }
        return busy || hasResult ? .blue : .green
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 7) {
                        Circle().fill(statusColor).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(L(statusKey)).font(.subheadline).multilineTextAlignment(.center)
                            .accessibilityIdentifier("keyboard.status")
                            .accessibilityValue(state.pending ? "preparing" : state.standbyLive ? state.status?.phase.rawValue ?? "disabled" : "standby_off")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    if hasResult {
                        Text(state.status?.text ?? "").font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity).accessibilityIdentifier("keyboard.result")
                    } else {
                        if recording { recordingActivity }
                        else if busy {
                            if reduceMotion { Image(systemName: "hourglass").accessibilityHidden(true) }
                            else { ProgressView().accessibilityHidden(true) }
                        }
                        microphone
                        if available && !busy {
                            Text(L("ios.keyboard.record_hint")).font(.body)
                                .multilineTextAlignment(.center)
                        } else if recording {
                            Text(L("ios.keyboard.stop_hint")).font(.body)
                                .multilineTextAlignment(.center)
                        }
                    }
                    if !state.standbyLive, state.errorKey != "ios.error.full_access", let url = URL(string: "utter://standby") {
                        Link(destination: url) {
                            Text(L("ios.standby.activate")).font(.body.weight(.semibold))
                                .multilineTextAlignment(.center).padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                        }.accessibilityIdentifier("keyboard.activate")
                    }
                }
                .frame(maxWidth: 580).frame(maxWidth: .infinity)
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            }.scrollEdgeEffectHidden()
            editingKeys.padding(.horizontal, 20).padding(.bottom, 8)
        }
        .background(Color(uiColor: Self.surfaceColor)).tint(.primary).buttonStyle(.plain)
    }

    static let surfaceColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.247, green: 0.263, blue: 0.290, alpha: 1)
            : UIColor(red: 0.820, green: 0.831, blue: 0.855, alpha: 1)
    }
    private var editingKeys: some View {
        VStack(spacing: 8) {
            if textSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    editKey("delete.left", label: "ios.action.delete", id: "delete", text: nil)
                    spaceKey
                    editKey("return", label: "ios.action.return", id: "return", text: "\n")
                }
                supplementalKey
            } else {
                HStack(spacing: 8) {
                    editKey("delete.left", label: "ios.action.delete", id: "delete", text: nil)
                    spaceKey
                    editKey("return", label: "ios.action.return", id: "return", text: "\n")
                    supplementalKey
                }
            }
        }.frame(maxWidth: 580).frame(maxWidth: .infinity)
    }
    private var spaceKey: some View {
        Button { edit(" ") } label: {
            Text(L("ios.action.space")).font(.body)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(keyColor, in: RoundedRectangle(cornerRadius: 10))
        }.accessibilityIdentifier("keyboard.space")
    }
    @ViewBuilder private var supplementalKey: some View {
        if hasResult {
            Button(action: insert) {
                Text(L("ios.action.insert")).font(.body.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 8).frame(minHeight: 44)
                    .foregroundStyle(.white).background(voiceBlue, in: RoundedRectangle(cornerRadius: 10))
            }.accessibilityIdentifier("keyboard.insert")
        } else if busy, let lease = state.lease {
            action(.cancel, lease: lease) {
                Image(systemName: "xmark").font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(keyColor, in: RoundedRectangle(cornerRadius: 10))
            }.accessibilityLabel(L("ios.action.cancel"))
        }
    }
    private var keyColor: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    private var voiceBlue: Color { Color(red: 0, green: 0.34, blue: 0.76) }
    private var voiceRed: Color { Color(red: 0.78, green: 0.14, blue: 0.12) }

    @ViewBuilder private var microphone: some View {
        if state.standbyLive, let lease = state.lease, state.status?.phase != .disabled {
            action(busy ? .stop : .start, lease: lease) { micLabel }
                .disabled(busy && state.status?.phase != .recording)
                .accessibilityLabel(L(busy ? "ios.action.stop" : "ios.action.record"))
        } else {
            Button {} label: { micLabel }.disabled(true)
                .accessibilityLabel(L("ios.action.record")).accessibilityHint(L("ios.keyboard_enable_notice"))
        }
    }
    private var micLabel: some View {
        Image(systemName: busy ? "stop.fill" : "mic.fill")
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(available ? Color.white : Color(uiColor: .secondaryLabel))
            .frame(width: 64, height: 64)
            .background(available ? (recording ? voiceRed : voiceBlue) : .clear, in: Circle())
            .overlay { if !available { Circle().strokeBorder(Color(uiColor: .secondaryLabel), lineWidth: 2) } }
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
                let height = 7 + 17 * (1 + sin(time * 5.7 + Double(index) * 0.8)) / 2
                Capsule().fill(voiceRed).frame(width: 4, height: height)
            }
        }.frame(height: 24).accessibilityHidden(true)
    }
    private func editKey(_ icon: String, label: String, id: String, text: String?) -> some View {
        Button { edit(text) } label: {
            Image(systemName: icon).font(.system(size: 20)).frame(width: 44, height: 44)
                .background(keyColor, in: RoundedRectangle(cornerRadius: 10))
        }.accessibilityLabel(L(label)).accessibilityIdentifier("keyboard.\(id)")
    }
    private func action<Label: View>(_ action: VoiceAction, lease: KeyboardLease, @ViewBuilder label: () -> Label) -> some View {
        let id = UUID()
        return Button(action: { _ = prepare(id, action, lease) }, label: label)
            .accessibilityIdentifier("keyboard.\(action.rawValue)")
    }
}

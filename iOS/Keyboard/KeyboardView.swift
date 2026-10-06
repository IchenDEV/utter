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
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(L(statusKey))
                    .font(.subheadline).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).accessibilityIdentifier("keyboard.status")
                    .accessibilityValue(state.pending ? "preparing" : state.standbyLive ? state.status?.phase.rawValue ?? "disabled" : "standby_off")
                if hasResult {
                    Text(state.status?.text ?? "").font(.body).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("keyboard.result")
                    Button(L("ios.action.insert"), action: insert).buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("keyboard.insert")
                } else {
                    HStack(spacing: 28) {
                        editKey("delete.left", label: "ios.action.delete", id: "delete", text: nil)
                        microphone
                        if busy, let lease = state.lease {
                            action(.cancel, lease: lease) {
                                Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44).contentShape(Rectangle())
                            }.accessibilityLabel(L("ios.action.cancel"))
                        } else { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }
                    }.frame(maxWidth: .infinity)
                }
                if !state.standbyLive, state.errorKey != "ios.error.full_access", let url = URL(string: "utter://standby") {
                    Link(destination: url) {
                        Text(L("ios.standby.activate")).frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    }.accessibilityIdentifier("keyboard.activate")
                }
                HStack(spacing: 16) {
                    if hasResult { editKey("delete.left", label: "ios.action.delete", id: "delete", text: nil) }
                    Button { edit(" ") } label: {
                        Text(L("ios.action.space")).frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    }
                        .accessibilityIdentifier("keyboard.space")
                    editKey("return", label: "ios.action.return", id: "return", text: "\n")
                }
            }.padding(.horizontal, 20).padding(.vertical, 16).frame(maxWidth: 580).frame(maxWidth: .infinity)
        }.scrollEdgeEffectHidden().tint(.primary).buttonStyle(.plain)
    }

    @ViewBuilder private var microphone: some View {
        if state.standbyLive, let lease = state.lease, state.status?.phase != .disabled {
            action(busy ? .stop : .start, lease: lease) { micLabel }
                .disabled(busy && state.status?.phase != .recording)
                .accessibilityLabel(L(busy ? "ios.action.stop" : "ios.action.record"))
        } else { unavailableMic }
    }
    private var unavailableMic: some View {
        Button {} label: { micLabel }.disabled(true)
            .accessibilityLabel(L("ios.action.record")).accessibilityHint(L("ios.keyboard_enable_notice"))
    }
    private var micLabel: some View {
        Image(systemName: busy ? "stop.fill" : "mic.fill")
            .font(.system(size: 32, weight: .medium))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(width: 88, height: 88).background(Color(uiColor: .label), in: Circle())
    }
    private func editKey(_ icon: String, label: String, id: String, text: String?) -> some View {
        Button { edit(text) } label: { Image(systemName: icon).font(.title3).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .accessibilityLabel(L(label)).accessibilityIdentifier("keyboard.\(id)")
    }
    private func action<Label: View>(_ action: VoiceAction, lease: KeyboardLease, @ViewBuilder label: () -> Label) -> some View {
        let id = UUID()
        return Button(action: { _ = prepare(id, action, lease) }, label: label)
            .accessibilityIdentifier("keyboard.\(action.rawValue)")
    }
}

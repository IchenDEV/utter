import SwiftUI
import UtterKeyboardBridge

@MainActor
struct KeyboardView: View {
    @ObservedObject var state: KeyboardState
    let prepare: (UUID, VoiceAction, KeyboardLease) -> Bool
    let voice: VoiceKeyHandlers
    let undo: () -> Void
    /// Called when the microphone key is about to send the user to the app.
    let leaveForApp: () -> Void
    let edit: (String?) -> Void
    @Environment(\.dynamicTypeSize) private var textSize

    private var m: KeyboardMetrics { state.metrics }
    private var busy: Bool { state.status?.isBusy == true || state.pending }
    private var recording: Bool { state.status?.phase == .recording }
    /// The rewrite runs after the raw text is already in the field.
    private var polishing: Bool { state.streaming && state.status?.polish == .pending }
    private var available: Bool { state.standbyLive && state.lease != nil && state.status?.phase != .disabled }
    private var showsActivate: Bool { !state.standbyLive && state.errorKey != "ios.error.full_access" }
    private var showsCancel: Bool { busy && state.lease != nil }
    private var showsUndo: Bool { !busy && state.undoable }
    private var statusKey: String {
        if let key = state.errorKey ?? state.status?.errorKey { return key }
        if polishing { return "ios.phase.polishing" }
        if state.pending { return "ios.phase.preparing" }
        if !state.standbyLive { return "ios.standby.off" }
        return "ios.phase.\(state.status?.phase.rawValue ?? "disabled")"
    }
    private var statusColor: Color {
        if state.errorKey != nil || state.status?.errorKey != nil || !available { return .secondary }
        if recording { return .red }
        return busy ? .blue : .green
    }
    private var look: VoiceKey.Look {
        guard available else { return .unavailable }
        if recording { return .recording }
        if polishing { return .finishing }
        if state.status?.phase == .preparing || (state.pending && state.status?.isBusy != true) { return .starting }
        return busy ? .finishing : .ready
    }

    var body: some View {
        Group { if textSize.isAccessibilitySize { largeLayout } else { gridLayout } }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .ignoresSafeArea().tint(.primary)
    }

    // Rows sit on the system keyboard's grid and hang from the bottom, so the bottom row stays where the
    // system puts it even when accessibility text sizes make the view taller.
    private var gridLayout: some View {
        let deleteX = m.width - m.sideMargin - m.deleteKeyWidth
        let cancelX = deleteX - m.gap - m.unitKeyWidth
        let statusWidth = (showsCancel || showsUndo ? cancelX : deleteX) - m.gap - m.sideMargin
        let returnX = m.width - m.sideMargin - m.sideKeyWidth
        let spaceX = m.sideMargin + m.unitKeyWidth + m.gap
        return ZStack(alignment: .topLeading) {
            place(m.sideMargin, m.rowTop(0), statusWidth, m.keyHeight) {
                statusPill.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            if showsCancel { place(cancelX, m.rowTop(0), m.unitKeyWidth, m.keyHeight) { cancelKey } }
            else if showsUndo { place(cancelX, m.rowTop(0), m.unitKeyWidth, m.keyHeight) { undoKey } }
            place(deleteX, m.rowTop(0), m.deleteKeyWidth, m.keyHeight) { deleteKey }
            place(m.sideMargin, m.rowTop(1), m.width - 2 * m.sideMargin, m.mainHeight) { mainArea }
            place(spaceX, m.rowTop(3), returnX - m.gap - spaceX, m.keyHeight) { spaceKey }
            place(returnX, m.rowTop(3), m.sideKeyWidth, m.keyHeight) { returnKey }
        }
        .frame(width: m.width, height: m.gridBottom, alignment: .topLeading)
        .padding(.bottom, m.viewHeight - m.gridBottom)
    }

    private var largeLayout: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    statusPill.frame(maxWidth: .infinity, alignment: .leading)
                    largeMain
                    if showsCancel { cancelKey.frame(height: 64) } else if showsUndo { undoKey.frame(height: 64) }
                }.padding(.horizontal, m.sideMargin).padding(.vertical, 8)
            }.scrollEdgeEffectHidden()
            HStack(spacing: m.gap) {
                Color.clear.frame(width: m.unitKeyWidth)
                deleteKey.frame(width: m.unitKeyWidth)
                spaceKey
                returnKey.frame(width: m.sideKeyWidth)
            }
            .frame(height: m.keyHeight).padding(.horizontal, m.sideMargin)
            .padding(.bottom, m.viewHeight - m.gridBottom)
        }
    }

    @ViewBuilder private var largeMain: some View {
        if showsActivate { activateKey.frame(minHeight: 96) } else { voiceKey.frame(minHeight: 96) }
    }

    @ViewBuilder private var mainArea: some View {
        if showsActivate { activateKey } else { voiceKey }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous).fill(Color(uiColor: KeyColors.cap))
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle().fill(statusColor).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(L(statusKey)).font(.subheadline).lineLimit(textSize.isAccessibilitySize ? nil : 2).minimumScaleFactor(0.8)
                .accessibilityIdentifier("keyboard.status")
                .accessibilityValue(state.pending ? "preparing" : state.standbyLive ? state.status?.phase.rawValue ?? "disabled" : "standby_off")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }

    private var voiceKey: some View {
        VoiceKey(look: look, keyDown: state.keyDown, radius: m.cornerRadius,
                 identifier: busy ? "keyboard.stop" : "keyboard.start",
                 label: L(busy ? "ios.action.stop" : "ios.action.record"),
                 enabled: !busy || recording, handlers: available ? voice : nil)
    }

    /// The microphone key while standby is off: one tap sends the user to Utter, and the keyboard that comes
    /// back starts listening by itself.
    @ViewBuilder private var activateKey: some View {
        if let url = URL(string: "utter://standby?dictate=1") {
            Link(destination: url) {
                VoiceKey(look: .activate, keyDown: false, radius: m.cornerRadius, identifier: "", label: "", enabled: true, handlers: nil).visual
            }
            .simultaneousGesture(TapGesture().onEnded { leaveForApp() })
            .accessibilityLabel(L("ios.standby.activate")).accessibilityIdentifier("keyboard.activate")
        }
    }

    private var deleteKey: some View { iconKey("delete.left", label: "ios.action.delete", id: "delete") { edit(nil) } }
    private var returnKey: some View { iconKey("return", label: "ios.action.return", id: "return") { edit("\n") } }

    @ViewBuilder private var cancelKey: some View {
        if let lease = state.lease {
            iconKey("xmark", label: "ios.action.cancel", id: "cancel") { _ = prepare(UUID(), .cancel, lease) }
        }
    }

    private var spaceKey: some View {
        Button { edit(" ") } label: {
            Text(L("ios.action.space")).font(.callout).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeyStyle(radius: m.cornerRadius)).accessibilityIdentifier("keyboard.space")
    }

    private var undoKey: some View { iconKey("arrow.uturn.backward", label: "ios.action.undo", id: "undo") { undo() } }

    private func iconKey(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20)).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeyStyle(radius: m.cornerRadius))
        .accessibilityLabel(L(label)).accessibilityIdentifier("keyboard.\(id)")
    }

    private func place<Content: View>(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        content().frame(width: width, height: height).position(x: x + width / 2, y: y + height / 2)
    }
}

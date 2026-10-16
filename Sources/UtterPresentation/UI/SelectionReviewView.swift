import AppKit
import SwiftUI
import UtterContracts
import UtterPresentationContracts

struct ReviewTextBlock: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RestoreOfferView: View {
    let restoration: SelectionEditRestoration
    let callbacks: SelectionReviewCallbacks
    let onClose: () -> Void
    @EnvironmentObject private var appState: AppState
    @State private var submitted = false
    @State private var notice: String?

    private var isRestorable: Bool { restoration.isAvailable && Date() < restoration.expiresAt }

    var body: some View {
        HStack(spacing: 8) {
            ReviewButton(title: L("common.close"), role: .quiet, shortcut: .cancelAction, action: onClose)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: notice == nil ? "checkmark" : "exclamationmark.triangle")
                    .foregroundStyle(notice == nil ? Color.white.opacity(0.76) : Color(nsColor: .systemOrange))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L(notice ?? "selection_edit.applied"))
                    if notice == nil, appState.selectionEditRestoreShortcut {
                        Text(L("selection_edit.restore_shortcut")).font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)
            ReviewButton(title: L("selection_edit.restore"), role: .primary, symbol: "arrow.uturn.backward",
                hint: appState.selectionEditRestoreShortcut ? L("selection_edit.restore_shortcut") : nil, action: restore)
                .disabled(submitted || !isRestorable)
        }
        .padding(SelectionReviewMetrics.edgePadding)
        .onAppear { callbacks.refresh() }
    }

    private func restore() {
        guard !submitted else { return }
        submitted = true
        guard isRestorable, callbacks.restore(restoration) else { notice = "selection_edit.restore_failed"; return }
    }
}

struct ReviewButton: View {
    enum Role { case primary, quiet }
    let title: String
    let role: Role
    var symbol: String?
    var shortcut: KeyboardShortcut?
    var hint: String?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol ?? (role == .primary ? "checkmark" : "xmark"))
        }
        .buttonStyle(OverlayActionButtonStyle(kind: role == .primary ? .confirm : .cancel, isHovering: hovering && isEnabled))
        .modifier(OptionalShortcut(shortcut: shortcut))
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
        .help(hint ?? title)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

private struct OptionalShortcut: ViewModifier {
    let shortcut: KeyboardShortcut?
    @ViewBuilder func body(content: Content) -> some View {
        if let shortcut { content.keyboardShortcut(shortcut) } else { content }
    }
}

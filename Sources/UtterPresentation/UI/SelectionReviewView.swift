import AppKit
import SwiftUI
import UtterContracts
import UtterPresentationContracts

struct SelectionReviewView: View {
    let proposal: SelectionEditProposal
    let callbacks: SelectionReviewCallbacks
    /// Observed so a live UI-language change (the host republishes state) re-renders these strings.
    @EnvironmentObject private var appState: AppState
    @State private var submitted = false
    @State private var notice: String?   // localization key, resolved at render so it follows language changes

    private var title: String {
        guard let pid = proposal.processIdentifier,
              let name = NSRunningApplication(processIdentifier: pid)?.localizedName else {
            return L("selection_edit.title_generic")
        }
        return String(format: L("selection_edit.title"), name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            ScrollView {
                VStack(alignment: .leading, spacing: SelectionReviewMetrics.blockSpacing) {
                    labelled("selection_edit.instruction") {
                        Text(proposal.recognizedInstruction).font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    labelled("selection_edit.original") { ReviewTextBlock(text: proposal.originalSelection) }
                    labelled("selection_edit.revised") { ReviewTextBlock(text: proposal.candidate) }
                }
                .padding(.horizontal, SelectionReviewMetrics.edgePadding)
                .padding(.bottom, SelectionReviewMetrics.edgePadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            if let notice {
                Text(L(notice)).font(.caption).foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.horizontal, .bottom], SelectionReviewMetrics.edgePadding)
            }
        }
        .onAppear {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: L("selection_edit.review"), .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ReviewButton(title: L("common.cancel"), role: .quiet, shortcut: .cancelAction) { callbacks.cancel(proposal) }
            Text(title)
                .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.88))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            ReviewButton(title: L("selection_edit.apply"), role: .primary, hint: L("selection_edit.apply_hint"), action: apply)
                .disabled(submitted || !proposal.isApplicable)
        }
        .padding(.horizontal, SelectionReviewMetrics.edgePadding)
        .frame(height: SelectionReviewMetrics.headerHeight)
    }

    private func apply() {
        guard !submitted else { return }
        submitted = true
        guard proposal.isApplicable, callbacks.apply(proposal) else { notice = "selection_edit.expired"; return }
    }

    private func labelled<Content: View>(_ key: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(key)).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                .frame(height: SelectionReviewMetrics.labelHeight, alignment: .leading)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

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
                Text(L(notice ?? "selection_edit.applied")).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)
            ReviewButton(title: L("selection_edit.restore"), role: .primary, symbol: "arrow.uturn.backward", action: restore)
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

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
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, SelectionReviewMetrics.edgePadding)
                .frame(height: SelectionReviewMetrics.headerHeight, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: SelectionReviewMetrics.blockSpacing) {
                    labelled("selection_edit.instruction") {
                        Text(proposal.recognizedInstruction).font(.callout).foregroundStyle(.secondary)
                    }
                    labelled("selection_edit.original") { ReviewTextBlock(text: proposal.originalSelection, fill: 0.04) }
                    labelled("selection_edit.revised") { ReviewTextBlock(text: proposal.candidate, fill: 0.09) }
                }
                .padding(.horizontal, SelectionReviewMetrics.edgePadding)
                .padding(.bottom, SelectionReviewMetrics.edgePadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .onAppear {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: L("selection_edit.review"), .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let notice {
                Text(L(notice)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ReviewButton(title: L("common.cancel"), role: .quiet, shortcut: .cancelAction) { callbacks.cancel(proposal) }
                ReviewButton(title: L("selection_edit.apply"), role: .primary, hint: L("selection_edit.apply_hint"), action: apply)
                    .disabled(submitted || !proposal.isApplicable)
            }
        }
        .padding(.horizontal, SelectionReviewMetrics.edgePadding)
        .frame(height: SelectionReviewMetrics.footerHeight, alignment: .center)
    }

    private func apply() {
        guard !submitted else { return }
        submitted = true
        guard proposal.isApplicable, callbacks.apply(proposal) else { notice = "selection_edit.expired"; return }
    }

    private func labelled<Content: View>(_ key: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(key)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(height: SelectionReviewMetrics.labelHeight, alignment: .leading)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ReviewTextBlock: View {
    let text: String
    let fill: Double
    var body: some View {
        Text(text)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .padding(SelectionReviewMetrics.blockPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(fill)))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: notice == nil ? "checkmark" : "exclamationmark.triangle")
                    .foregroundStyle(notice == nil ? Color.secondary : Color(nsColor: .systemOrange))
                    .accessibilityHidden(true)
                Text(L(notice ?? "selection_edit.applied")).font(.headline).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ReviewButton(title: L("common.close"), role: .quiet, shortcut: .cancelAction, action: onClose)
                ReviewButton(title: L("selection_edit.restore"), role: .primary, action: restore)
                    .disabled(submitted || !isRestorable)
            }
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
    var shortcut: KeyboardShortcut?
    var hint: String?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title).font(.body.weight(role == .primary ? .semibold : .regular))
        }
        .buttonStyle(ReviewButtonStyle(role: role, hovering: hovering && isEnabled))
        .modifier(OptionalShortcut(shortcut: shortcut))
        .accessibilityHint(hint ?? "")
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

private struct ReviewButtonStyle: ButtonStyle {
    let role: ReviewButton.Role
    let hovering: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(role == .primary ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill(pressed: configuration.isPressed)))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
    }

    private func fill(pressed: Bool) -> Color {
        switch role {
        case .primary: return Color.primary.opacity(pressed ? 0.7 : hovering ? 0.95 : 0.85)
        case .quiet: return Color.primary.opacity(pressed ? 0.14 : hovering ? 0.08 : 0)
        }
    }
}

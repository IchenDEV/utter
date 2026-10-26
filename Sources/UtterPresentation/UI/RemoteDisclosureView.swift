import AppKit
import SwiftUI
import UtterContracts
import UtterPresentationContracts

/// Shown BEFORE recording and before anything is sent. Continue is an explicit click (no Return default);
/// the owner re-checks the retained intent, target and expiry, and one Continue can start only one session.
struct RemoteDisclosureView: View {
    let consent: SelectionEditRemoteConsent
    let intentID: UUID
    let callbacks: SelectionReviewCallbacks
    @EnvironmentObject private var appState: AppState
    @State private var submitted = false
    @State private var notice: String?   // localization key, resolved at render so it follows language changes

    private var host: String { consent.providerHost }
    private var canContinue: Bool { !host.isEmpty && !consent.selectedText.isEmpty && Date() < consent.expiresAt }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            ScrollView {
                VStack(alignment: .leading, spacing: SelectionReviewMetrics.blockSpacing) {
                    Text(host.isEmpty ? L("selection_edit.remote_no_provider") : String(format: L("selection_edit.remote_lead"), host))
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("selection_edit.remote_selected")).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                            .frame(height: SelectionReviewMetrics.labelHeight, alignment: .leading)
                        ReviewTextBlock(text: consent.selectedText)
                    }
                    .accessibilityElement(children: .combine)
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
                userInfo: [.announcement: L("selection_edit.remote_disclosure_required"),
                           .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ReviewButton(title: L("common.cancel"), role: .quiet, shortcut: .cancelAction) { callbacks.decline(intentID) }
            Text(host.isEmpty ? L("selection_edit.remote_title_generic") : String(format: L("selection_edit.remote_title"), host))
                .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.88))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            ReviewButton(title: L("common.continue"), role: .primary, hint: L("selection_edit.remote_continue_hint"), action: authorize)
                .disabled(submitted || !canContinue)
        }
        .padding(.horizontal, SelectionReviewMetrics.edgePadding)
        .frame(height: SelectionReviewMetrics.headerHeight)
    }

    private func authorize() {
        guard !submitted else { return }
        submitted = true
        guard canContinue, callbacks.authorize(intentID) else { notice = "selection_edit.remote_failed"; return }
    }
}

/// Local, non-success message for a flow that ended without a session (for example an unconfirmed disclosure).
struct ReviewNoticeView: View {
    let key: String
    let onClose: () -> Void
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            ReviewButton(title: L("common.close"), role: .quiet, shortcut: .cancelAction, action: onClose)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Color(nsColor: .systemOrange))
                    .accessibilityHidden(true)
                Text(L(key)).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.88))
                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SelectionReviewMetrics.edgePadding)
    }
}

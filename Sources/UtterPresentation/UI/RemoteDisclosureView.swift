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
            Text(host.isEmpty ? L("selection_edit.remote_title_generic") : String(format: L("selection_edit.remote_title"), host))
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, SelectionReviewMetrics.edgePadding)
                .frame(height: SelectionReviewMetrics.headerHeight, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: SelectionReviewMetrics.blockSpacing) {
                    Text(host.isEmpty ? L("selection_edit.remote_no_provider") : String(format: L("selection_edit.remote_lead"), host))
                        .font(.callout).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("selection_edit.remote_selected")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(height: SelectionReviewMetrics.labelHeight, alignment: .leading)
                        ReviewTextBlock(text: consent.selectedText, fill: 0.04)
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding(.horizontal, SelectionReviewMetrics.edgePadding)
                .padding(.bottom, SelectionReviewMetrics.edgePadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .onAppear {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: L("selection_edit.remote_disclosure_required"),
                           .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let notice {
                Text(L(notice)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ReviewButton(title: L("common.cancel"), role: .quiet, shortcut: .cancelAction) { callbacks.decline(intentID) }
                ReviewButton(title: L("common.continue"), role: .primary, hint: L("selection_edit.remote_continue_hint"), action: authorize)
                    .disabled(submitted || !canContinue)
            }
        }
        .padding(.horizontal, SelectionReviewMetrics.edgePadding)
        .frame(height: SelectionReviewMetrics.footerHeight, alignment: .center)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Color(nsColor: .systemOrange))
                    .accessibilityHidden(true)
                Text(L(key)).font(.headline).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer(minLength: 0)
                ReviewButton(title: L("common.close"), role: .primary, shortcut: .cancelAction, action: onClose)
            }
        }
        .padding(SelectionReviewMetrics.edgePadding)
    }
}

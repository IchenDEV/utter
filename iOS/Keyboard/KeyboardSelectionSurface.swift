import SwiftUI
import UtterKeyboardBridge

/// Shows a proposed selection edit for review, or the one-tap restore after a confirmed edit.
/// It only renders state and forwards taps; the parent handlers revalidate the live field every time.
@MainActor
struct KeyboardSelectionSurface<Content: View>: View {
    @ObservedObject var state: KeyboardState
    let content: Content
    let apply: () -> Void
    let cancel: () -> Void
    let restore: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize

    private var m: KeyboardMetrics { state.metrics }
    private var gutter: CGFloat { max(m.sideMargin, 16) }
    private var touchHeight: CGFloat { max(m.keyHeight, 48) }
    /// The native GlobeKey is a UIKit view above this host, on the bottom row, with a touch column of
    /// sideMargin - 3 ... sideMargin + unitKeyWidth + gap - 3 (`KeyboardController.applyMetrics`).
    /// The host is already inset by the side safe area, so the actions start at the system's next key, gutter included.
    private var globeClearance: CGFloat { max(m.sideMargin + m.unitKeyWidth + m.gap - gutter, 0) }

    var body: some View {
        // Entries at each expiry re-render the surface at that instant; nothing polls.
        TimelineView(.explicit(refreshDates)) { timeline in
            layers(at: timeline.date)
        }
        .ignoresSafeArea()
    }

    private var refreshDates: [Date] {
        let expiries = [state.selectionReview?.expiresAt, state.selectionRestoration?.expiresAt].compactMap { $0 }
        return ([Date()] + expiries).sorted()
    }

    @ViewBuilder private func layers(at now: Date) -> some View {
        if let review = state.selectionReview {
            panel(review, applicable: review.isApplicable(at: now))
                .id(review.id)
        } else {
            let restorable = state.selectionRestoration?.isValid(at: now) == true
            if textSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    if restorable {
                        restoreKey.frame(minHeight: 64).padding(.horizontal, gutter).padding(.top, 8)
                    }
                    content
                }
            } else {
                // Sits over the status row, which is idle while a confirmed edit can be restored.
                content.overlay(alignment: .bottomLeading) {
                    if restorable {
                        restoreKey
                            .frame(width: max(m.width - m.sideMargin - m.deleteKeyWidth - 2 * m.gap - m.unitKeyWidth - m.sideMargin, 120),
                                   height: touchHeight)
                            .padding(.leading, m.sideMargin)
                            .padding(.bottom, max(m.viewHeight - m.rowTop(0) - m.keyHeight, 0))
                    }
                }
            }
        }
    }

    private func panel(_ review: KeyboardSelectionReview, applicable: Bool) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    block("ios.selection.instruction", review.recognizedInstruction, id: "instruction", style: .primary)
                    block("ios.selection.original", review.target.original, id: "original", style: .secondary)
                    block("ios.selection.candidate", review.candidate, id: "candidate", style: .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, gutter).padding(.vertical, 12)
            }
            VStack(spacing: 8) {
                if let key = note(applicable: applicable) {
                    Text(L(key)).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("keyboard.selection.note")
                }
                HStack(spacing: m.gap + 4) {
                    cancelKey
                    applyKey(enabled: applicable && !state.selectionPending)
                }
                .padding(.leading, globeClearance)
            }
            .padding(.horizontal, gutter).padding(.top, 8)
            .padding(.bottom, max(m.viewHeight - m.gridBottom, 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func note(applicable: Bool) -> String? {
        if !applicable { return "ios.selection.expired" }
        if let key = state.errorKey, key.hasPrefix("ios.selection.") { return key }
        return state.selectionPending ? "ios.selection.waiting" : nil
    }

    private func block(_ title: String, _ text: String, id: String, style: HierarchicalShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(title)).font(.subheadline).foregroundStyle(.secondary)
            Text(text).font(.body).foregroundStyle(style).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L(title)).accessibilityValue(text)
        .accessibilityIdentifier("keyboard.selection.\(id)")
    }

    private var cancelKey: some View {
        Button(action: cancel) {
            Text(L("ios.selection.cancel")).font(.body).lineLimit(2).minimumScaleFactor(0.8)
                .foregroundStyle(state.selectionPending ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, minHeight: touchHeight)
        }
        .buttonStyle(KeyStyle(radius: m.cornerRadius))
        .disabled(state.selectionPending)
        .accessibilityIdentifier("keyboard.selection.cancel")
    }

    private func applyKey(enabled: Bool) -> some View {
        Button(action: apply) {
            Text(L("ios.selection.apply")).font(.body.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                .foregroundStyle(enabled ? Color.white : Color(uiColor: .tertiaryLabel))
                .frame(maxWidth: .infinity, minHeight: touchHeight)
        }
        .buttonStyle(KeyStyle(radius: m.cornerRadius, fill: enabled ? KeyColors.action : KeyColors.actionDisabled))
        .disabled(!enabled)
        .accessibilityIdentifier("keyboard.selection.apply")
    }

    private var restoreKey: some View {
        Button(action: restore) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward").accessibilityHidden(true)
                Text(L("ios.selection.restore")).lineLimit(2).minimumScaleFactor(0.8)
            }
            .font(.callout)
            .foregroundStyle(state.selectionPending ? Color(uiColor: .tertiaryLabel) : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeyStyle(radius: m.cornerRadius))
        .disabled(state.selectionPending)
        .accessibilityLabel(L("ios.selection.restore"))
        .accessibilityIdentifier("keyboard.selection.restore")
    }
}

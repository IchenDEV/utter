import AppKit
import SwiftUI
import UtterContracts
import UtterPresentationContracts

/// Error and unconfirmed-insertion notice: one calm row instead of a stacked card with distant buttons.
struct OverlayAlertView: View {
    let alert: OverlayAlert
    let onCopy: () -> Void
    let onRecover: () -> Void
    let onDismiss: () -> Void

    private var plan: OverlayAlertMetrics.Plan { OverlayAlertMetrics.plan(for: alert) }

    var body: some View {
        let plan = plan
        Group {
            switch plan.arrangement {
            case .inline:
                HStack(spacing: OverlayAlertMetrics.itemSpacing) {
                    icon
                    message(width: plan.messageWidth, plan: plan)
                    HStack(spacing: OverlayAlertMetrics.actionSpacing) {
                        actions(plan.capsuleWidths)
                        close
                    }
                }
            case .stacked:
                VStack(alignment: .leading, spacing: OverlayAlertMetrics.itemSpacing) {
                    HStack(spacing: OverlayAlertMetrics.itemSpacing) {
                        icon
                        message(width: plan.messageWidth, plan: plan)
                        close
                    }
                    HStack(spacing: OverlayAlertMetrics.actionSpacing) { actions(plan.capsuleWidths) }
                        .padding(.leading, OverlayAlertMetrics.iconWidth + OverlayAlertMetrics.itemSpacing)
                }
            }
        }
        .padding(.horizontal, OverlayAlertMetrics.horizontalPadding)
        .padding(.vertical, OverlayAlertMetrics.verticalPadding)
        .frame(width: plan.size.width, height: plan.size.height)
    }

    private var icon: some View {
        Image(systemName: alert.isUncertain ? "exclamationmark.triangle" : "exclamationmark")
            .font(.caption.weight(.medium))
            .foregroundStyle(alert.isUncertain ? Color(nsColor: .systemOrange) : Color(nsColor: .systemRed).opacity(0.88))
            .frame(width: OverlayAlertMetrics.iconWidth, height: OverlayAlertMetrics.iconWidth)
            .accessibilityHidden(true)
    }

    private func message(width: CGFloat, plan: OverlayAlertMetrics.Plan) -> some View {
        let (title, detail) = alert.parts
        return VStack(alignment: .leading, spacing: OverlayAlertMetrics.detailGap) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(plan.titleLines)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(plan.detailLines)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: width, alignment: .leading)
    }

    /// Same order as `OverlayAlert.actionTitles`, which the widths in the plan were measured from.
    private var actionItems: [(title: String, run: () -> Void)] {
        [alert.copyTitle.map { ($0, onCopy) }, alert.recoveryTitle.map { ($0, onRecover) }].compactMap { $0 }
    }

    @ViewBuilder
    private func actions(_ widths: [CGFloat]) -> some View {
        let items = actionItems
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            OverlayCapsuleButton(title: item.title, width: widths[index], action: item.run)
        }
    }

    private var close: some View {
        ReviewButton(title: L("common.close"), role: .quiet, action: onDismiss)
    }
}

struct OverlayCapsuleButton: View {
    let title: String
    let width: CGFloat
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(OverlayCapsuleButtonStyle(width: width, isHovering: isHovering))
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }
}

struct OverlayCapsuleButtonStyle: ButtonStyle {
    let width: CGFloat
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .frame(width: width, height: OverlayControlMetrics.actionButtonSize)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.22 : isHovering ? 0.16 : 0.10)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
            .contentShape(Capsule())
    }
}

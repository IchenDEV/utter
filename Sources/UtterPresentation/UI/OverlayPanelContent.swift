import UtterContracts
import UtterPresentationContracts
import SwiftUI

struct OverlayContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var systemScheme

    let onLayoutChange: (OverlayLayout) -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let onCopy: () -> Void
    let onRecover: () -> Void
    let onDismiss: () -> Void
    var review = SelectionReviewCallbacks.none
    @ObservedObject var notice = ReviewNotice()

    private var livePreview: String? {
        guard appState.isRecording else { return nil }
        let text = appState.rawTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var layout: OverlayLayout {
        OverlayLayout(appState: appState, notice: notice.key)
    }

    private var isError: Bool {
        if case .error = appState.phase { return true }
        return false
    }

    private var showsEspressoFallback: Bool {
        appState.phase == .done
            && appState.completionKind == .espressoFallback
    }

    var body: some View {
        content
            .frame(width: layout.width, height: layout.height, alignment: .center)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: layout.outerCornerRadius, style: .continuous))
            .compositingGroup()
            .environment(\.colorScheme, layout.content == .status ? .dark : systemScheme)
            .onAppear {
                onLayoutChange(layout)
            }
            .onChange(of: layout) { _, newLayout in
                onLayoutChange(newLayout)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: layout)
    }

    @ViewBuilder
    private var content: some View {
        if let consent = appState.remoteDisclosure, let intentID = appState.snapshot.id {
            RemoteDisclosureView(consent: consent, intentID: intentID, callbacks: review).id(intentID)
        } else if let proposal = appState.selectionEditProposal {
            SelectionReviewView(proposal: proposal, callbacks: review).id(proposal.id)
        } else if appState.offersRestore, let restoration = appState.selectionEditRestoration {
            RestoreOfferView(restoration: restoration, callbacks: review, onClose: onDismiss).id(restoration.operationID)
        } else if layout.content == .notice, let key = notice.key {
            ReviewNoticeView(key: key, onClose: onDismiss)
        } else {
            hud
        }
    }

    private var hud: some View {
        VStack(spacing: layout.stackSpacing) {
            if appState.isRecording {
                recordingControls
                    .padding(.top, layout.topPadding)
            } else {
                statusRow
                    .padding(.top, layout.topPadding)
                if appState.presentation.keepsVisible { recoveryControls }
            }

            if let livePreview {
                livePreviewText(livePreview)
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.bottom, layout.bottomPadding)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            statusIcon
                .font(.caption.weight(.medium))
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            Text(appState.statusMessage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(isError ? 0.94 : 0.88))
                .lineLimit(isError ? 3 : showsEspressoFallback ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)
        }
        .frame(width: layout.width - 2 * layout.horizontalPadding, alignment: .leading)
    }

    private var recoveryControls: some View {
        HStack(spacing: 10) {
            if appState.presentation.canCopy {
                Button(L("common.copy"), action: onCopy)
            }
            if let action = appState.snapshot.recoveryAction {
                Button(L(action == .models ? "hud.open_models" : "hud.open_permissions"), action: onRecover)
            }
            Spacer(minLength: 0)
            Button(L("common.close"), action: onDismiss)
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var recordingControls: some View {
        HStack(spacing: 0) {
            OverlayActionButton(kind: .cancel, action: onCancel)

            Spacer(minLength: 0)

            WaveformView(level: appState.audioLevel)
                .frame(width: 42, height: 14)
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            OverlayActionButton(kind: .confirm, action: onConfirm)
        }
        .frame(width: OverlayControlMetrics.recordingControlsWidth)
    }

    private func livePreviewText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: layout.outerCornerRadius, style: .continuous)
        let review = layout.content != .status
        return ZStack {
            if reduceTransparency {
                shape.fill(review ? Color(nsColor: .windowBackgroundColor) : Color.black.opacity(0.92))
            } else if review {
                shape.fill(.regularMaterial)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.22))
            }
        }
        .overlay {
            shape.strokeBorder(
                (review ? Color.primary : Color.white).opacity(colorSchemeContrast == .increased ? 0.28 : 0.12),
                lineWidth: colorSchemeContrast == .increased ? 1 : 0.5
            )
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.phase {
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(Color(nsColor: .systemRed).opacity(0.82))
        case .transcribing:
            Image(systemName: "waveform.badge.magnifyingglass")
                .foregroundStyle(.white.opacity(0.76))
                .symbolEffect(.pulse.byLayer, isActive: !reduceMotion)
        case .processing:
            Image(systemName: "textformat")
                .foregroundStyle(.white.opacity(0.76))
        case .inserting:
            Image(systemName: "text.cursor")
                .foregroundStyle(.white.opacity(0.76))
        case .loadingModel:
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.white.opacity(0.76))
        case .downloading:
            Image(systemName: "arrow.down")
                .foregroundStyle(.white.opacity(0.76))
        case .copied:
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.white.opacity(0.84))
        case .uncertain:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color(nsColor: .systemOrange))
        case .done:
            Image(systemName: "checkmark")
                .foregroundStyle(.white.opacity(0.84))
        case .error:
            Image(systemName: "exclamationmark")
                .foregroundStyle(Color(nsColor: .systemRed).opacity(0.88))
        default:
            Image(systemName: "mic")
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

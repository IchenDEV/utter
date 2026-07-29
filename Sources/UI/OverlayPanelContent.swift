import SwiftUI

struct OverlayLayout: Equatable {
    let width: CGFloat
    let height: CGFloat
    let outerCornerRadius: CGFloat
    let isInteractive: Bool
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let stackSpacing: CGFloat

    var panelSize: CGSize {
        CGSize(width: width, height: height)
    }

    @MainActor
    init(appState: AppState) {
        let hasPreview = appState.phase == .recording && !appState.rawTranscription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isInteractive = appState.isRecording

        switch appState.phase {
        case .recording where hasPreview:
            width = 304
            height = 80
            outerCornerRadius = 22
            horizontalPadding = 14
            topPadding = 8
            bottomPadding = 8
            stackSpacing = 6
        case .recording:
            width = 148
            height = 40
            outerCornerRadius = 20
            horizontalPadding = 7
            topPadding = 7
            bottomPadding = 7
            stackSpacing = 6
        case .transcribing, .processing, .inserting:
            width = 216
            height = 48
            outerCornerRadius = 18
            horizontalPadding = 12
            topPadding = 10
            bottomPadding = 9
            stackSpacing = 6
        case .error:
            width = 288
            height = 56
            outerCornerRadius = 18
            horizontalPadding = 12
            topPadding = 8
            bottomPadding = 8
            stackSpacing = 6
        default:
            width = 192
            height = 40
            outerCornerRadius = 20
            horizontalPadding = 12
            topPadding = 10
            bottomPadding = 10
            stackSpacing = 6
        }
    }
}

struct OverlayContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let onLayoutChange: (OverlayLayout) -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var fakeProgress: Double = 0
    @State private var progressTimer: Timer?

    private var showsProgress: Bool {
        switch appState.phase {
        case .transcribing, .processing, .inserting:
            return true
        default:
            return false
        }
    }

    private var livePreview: String? {
        guard appState.isRecording else { return nil }
        let text = appState.rawTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var layout: OverlayLayout {
        OverlayLayout(appState: appState)
    }

    private var isError: Bool {
        if case .error = appState.phase { return true }
        return false
    }

    var body: some View {
        VStack(spacing: layout.stackSpacing) {
            if layout.isInteractive {
                recordingControls
                    .padding(.top, layout.topPadding)
            } else {
                statusRow
                    .padding(.top, layout.topPadding)
            }

            if let livePreview {
                livePreviewText(livePreview)
            }

            if showsProgress {
                progressBar
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.bottom, layout.bottomPadding)
        .frame(width: layout.width, height: layout.height, alignment: .center)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: layout.outerCornerRadius, style: .continuous))
        .compositingGroup()
        .onAppear {
            handlePhaseChange(appState.phase)
            onLayoutChange(layout)
        }
        .onChange(of: appState.phase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
        .onChange(of: layout) { _, newLayout in
            onLayoutChange(newLayout)
        }
        .onDisappear {
            progressTimer?.invalidate()
            progressTimer = nil
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: layout)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: fakeProgress)
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
                .lineLimit(isError ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)
        }
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

    private var progressBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(.white.opacity(0.1))
                .frame(height: 2)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.66))
                        .frame(width: geo.size.width * fakeProgress, height: 2)
                }
        }
        .frame(height: 2)
        .padding(.leading, 24)
        .accessibilityHidden(true)
    }

    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: layout.outerCornerRadius, style: .continuous)
        return ZStack {
            if reduceTransparency {
                shape.fill(Color.black.opacity(0.92))
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.22))
            }
        }
        .overlay {
            shape.strokeBorder(
                .white.opacity(colorSchemeContrast == .increased ? 0.28 : 0.12),
                lineWidth: colorSchemeContrast == .increased ? 1 : 0.5
            )
        }
    }

    private func handlePhaseChange(_ phase: AppPhase) {
        progressTimer?.invalidate()
        progressTimer = nil

        switch phase {
        case .transcribing:
            fakeProgress = 0.08
            startProgressTimer(target: 0.34, step: 0.04, interval: 0.16)
        case .processing:
            if fakeProgress < 0.34 { fakeProgress = 0.34 }
            startProgressTimer(target: 0.92, step: 0.015, interval: 0.28)
        case .inserting:
            fakeProgress = 0.96
        case .done:
            fakeProgress = 1.0
        default:
            fakeProgress = 0
        }
    }

    private func startProgressTimer(target: Double, step: Double, interval: TimeInterval) {
        progressTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                if fakeProgress < target {
                    fakeProgress = min(fakeProgress + step, target)
                }
            }
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

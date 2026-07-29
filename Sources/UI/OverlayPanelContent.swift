import SwiftUI

struct OverlayLayout: Equatable {
    let width: CGFloat
    let height: CGFloat
    let outerCornerRadius: CGFloat
    let innerCornerRadius: CGFloat
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

        switch appState.phase {
        case .recording where hasPreview:
            width = 396
            height = 148
            outerCornerRadius = 28
            innerCornerRadius = 20
            horizontalPadding = 18
            topPadding = 18
            bottomPadding = 16
            stackSpacing = 12
        case .recording:
            let compactHeight: CGFloat = 64
            width = 324
            height = compactHeight
            outerCornerRadius = compactHeight / 2
            innerCornerRadius = 18
            horizontalPadding = 18
            topPadding = 16
            bottomPadding = 16
            stackSpacing = 10
        case .transcribing, .processing, .inserting:
            width = 348
            height = 76
            outerCornerRadius = 24
            innerCornerRadius = 18
            horizontalPadding = 18
            topPadding = 16
            bottomPadding = 14
            stackSpacing = 10
        case .error:
            width = 372
            height = 76
            outerCornerRadius = 24
            innerCornerRadius = 18
            horizontalPadding = 18
            topPadding = 16
            bottomPadding = 14
            stackSpacing = 10
        default:
            width = 324
            height = 60
            outerCornerRadius = 24
            innerCornerRadius = 18
            horizontalPadding = 18
            topPadding = 16
            bottomPadding = 16
            stackSpacing = 10
        }
    }
}

struct OverlayContentView: View {
    @EnvironmentObject var appState: AppState

    let onLayoutChange: (OverlayLayout) -> Void

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
            statusRow
                .padding(.top, layout.topPadding)

            if let livePreview {
                previewCard(text: livePreview)
            }

            if showsProgress {
                progressBar
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.bottom, layout.bottomPadding)
        .frame(width: layout.width, height: layout.height, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: layout.outerCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.34),
                            Color.black.opacity(0.18),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: layout.outerCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: layout.outerCornerRadius, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.7)
        )
        .clipShape(RoundedRectangle(cornerRadius: layout.outerCornerRadius, style: .continuous))
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 12)
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
        .animation(.easeInOut(duration: 0.24), value: layout)
        .animation(.easeInOut(duration: 0.28), value: fakeProgress)
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusAccent.opacity(0.16))
                    .frame(width: 28, height: 28)
                statusIcon
                    .font(.system(size: 14, weight: .semibold))
            }

            Text(appState.statusMessage)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(isError ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if appState.isRecording {
                WaveformView(level: appState.audioLevel)
                    .frame(width: 38, height: 18)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.08))
                    )
            }
        }
    }

    private func previewCard(text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.94))
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: layout.innerCornerRadius, style: .continuous)
                    .fill(.white.opacity(0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: layout.innerCornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 0.6)
                    )
            )
    }

    private var progressBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(.white.opacity(0.12))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.76, blue: 0.28),
                                    Color(red: 1.0, green: 0.47, blue: 0.18),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * fakeProgress, height: 5)
                }
        }
        .frame(height: 5)
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
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.34))
        case .transcribing:
            Image(systemName: "waveform.badge.magnifyingglass")
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.28))
                .symbolEffect(.pulse.byLayer)
        case .processing, .inserting:
            Image(systemName: "brain")
                .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.25))
        case .loadingModel:
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.blue)
        case .downloading:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        default:
            Image(systemName: "mic")
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var statusAccent: Color {
        switch appState.phase {
        case .recording:
            return Color(red: 1.0, green: 0.45, blue: 0.34)
        case .transcribing:
            return Color(red: 1.0, green: 0.78, blue: 0.28)
        case .processing, .inserting:
            return Color(red: 1.0, green: 0.6, blue: 0.25)
        case .done:
            return .green
        case .error:
            return .red
        default:
            return .white
        }
    }
}

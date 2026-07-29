import SwiftUI

struct WaveformView: View {
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 7
    @State private var smoothLevel: Float = 0

    var body: some View {
        Group {
            if reduceMotion {
                waveform(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    waveform(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .onChange(of: level) { _, newVal in
            smoothLevel = smoothLevel * 0.6 + newVal * 0.4
        }
    }

    private func waveform(at time: TimeInterval) -> some View {
        Canvas { context, size in
            let barWidth: CGFloat = 1.5
            let gap: CGFloat = 2.25
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
            let originX = (size.width - totalWidth) / 2
            let target = max(CGFloat(level), 0.08)
            let energy = target * 0.45 + CGFloat(smoothLevel) * 0.55

            for index in 0..<barCount {
                let distanceFromCenter = abs(CGFloat(index) - CGFloat(barCount - 1) / 2)
                let envelope = 1 - distanceFromCenter * 0.13
                let oscillation = CGFloat(sin(time * 7.5 + Double(index) * 0.9))
                let motion: CGFloat = reduceMotion ? 0.72 : 0.72 + 0.28 * oscillation
                let barHeight = max(2, energy * size.height * envelope * motion + 2)
                let rect = CGRect(
                    x: originX + CGFloat(index) * (barWidth + gap),
                    y: (size.height - barHeight) / 2,
                    width: barWidth,
                    height: barHeight
                )
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                let opacity = 0.56 + energy * 0.3
                context.fill(
                    path,
                    with: .color(Color(nsColor: .systemRed).opacity(opacity))
                )
            }
        }
    }
}

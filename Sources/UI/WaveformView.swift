import SwiftUI

struct WaveformView: View {
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var smoothedLevel: Float = 0

    var body: some View {
        let isDark = colorScheme == .dark

        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let energy = visibleEnergy(for: smoothedLevel)

                drawWave(
                    in: &context,
                    size: size,
                    time: time,
                    energy: energy * 0.54,
                    frequency: 1.55,
                    speed: -4.2,
                    phase: 1.4,
                    lineWidth: 1.05,
                    colors: isDark
                        ? [
                            Color(red: 1.0, green: 0.34, blue: 0.27).opacity(0.32),
                            Color(red: 1.0, green: 0.73, blue: 0.20).opacity(0.50),
                        ]
                        : [
                            Color(red: 0.78, green: 0.16, blue: 0.11).opacity(0.40),
                            Color(red: 0.70, green: 0.38, blue: 0.02).opacity(0.56),
                        ]
                )

                drawWave(
                    in: &context,
                    size: size,
                    time: time,
                    energy: energy * 0.72,
                    frequency: 2.15,
                    speed: 5.4,
                    phase: 2.8,
                    lineWidth: 1.15,
                    colors: isDark
                        ? [
                            Color(red: 1.0, green: 0.48, blue: 0.28).opacity(0.48),
                            Color(red: 1.0, green: 0.84, blue: 0.34).opacity(0.68),
                        ]
                        : [
                            Color(red: 0.84, green: 0.24, blue: 0.10).opacity(0.56),
                            Color(red: 0.76, green: 0.46, blue: 0.02).opacity(0.72),
                        ]
                )

                drawWave(
                    in: &context,
                    size: size,
                    time: time,
                    energy: energy,
                    frequency: 1.8,
                    speed: 7.2,
                    phase: 0,
                    lineWidth: 2.2,
                    colors: isDark
                        ? [
                            Color(red: 1.0, green: 0.32, blue: 0.25),
                            Color(red: 1.0, green: 0.68, blue: 0.16),
                            Color(red: 1.0, green: 0.88, blue: 0.42),
                        ]
                        : [
                            Color(red: 0.82, green: 0.17, blue: 0.12),
                            Color(red: 0.84, green: 0.39, blue: 0.02),
                            Color(red: 0.72, green: 0.49, blue: 0.02),
                        ]
                )
            }
        }
        .onAppear { smoothedLevel = level }
        .onChange(of: level) { _, newLevel in
            smoothedLevel = smoothedLevel * 0.6 + newLevel * 0.4
        }
        .accessibilityHidden(true)
    }

    private func visibleEnergy(for level: Float) -> CGFloat {
        let normalized = CGFloat(min(max(level, 0), 1))
        return 0.14 + pow(normalized, 0.72) * 0.86
    }

    private func drawWave(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        energy: CGFloat,
        frequency: Double,
        speed: Double,
        phase: Double,
        lineWidth: CGFloat,
        colors: [Color]
    ) {
        let path = wavePath(
            size: size,
            time: time,
            energy: energy,
            frequency: frequency,
            speed: speed,
            phase: phase
        )
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: colors),
            startPoint: CGPoint(x: 0, y: size.height / 2),
            endPoint: CGPoint(x: size.width, y: size.height / 2)
        )
        context.stroke(
            path,
            with: shading,
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func wavePath(
        size: CGSize,
        time: TimeInterval,
        energy: CGFloat,
        frequency: Double,
        speed: Double,
        phase: Double
    ) -> Path {
        let sampleCount = max(Int(size.width.rounded(.up)), 32)
        let centerY = size.height / 2
        let horizontalInset = min(2, size.width / 2)
        let drawableWidth = max(0, size.width - horizontalInset * 2)
        let maximumAmplitude = max(0, (size.height - 4) / 2)
        var path = Path()

        for sample in 0...sampleCount {
            let progress = Double(sample) / Double(sampleCount)
            let x = horizontalInset + drawableWidth * CGFloat(progress)
            let envelope = pow(sin(.pi * progress), 0.62)
            let fundamental = sin(progress * .pi * 2 * frequency + time * speed + phase)
            let harmonic = sin(progress * .pi * 2 * (frequency * 2.35) - time * speed * 0.44 + phase)
            let signal = fundamental * 0.78 + harmonic * 0.22
            let y = centerY + maximumAmplitude * energy * CGFloat(envelope * signal)

            if sample == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

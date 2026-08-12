import AppKit
import SwiftUI

struct AppUsageInsightCard: View {
    let activity: [AppInputActivity]

    var body: some View {
        let topApps = Array(activity.prefix(5))
        let maximum = max(topApps.first?.characterCount ?? 0, 1)
        VStack(alignment: .leading, spacing: 12) {
            InsightCardHeader(
                title: L("history.apps.title"),
                subtitle: L("history.apps.subtitle"),
                symbol: "square.grid.2x2"
            )

            if topApps.isEmpty {
                Text(L("history.apps.empty"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                VStack(spacing: 11) {
                    ForEach(Array(topApps.enumerated()), id: \.element.id) { index, app in
                        appRow(app, rank: index, maximum: maximum)
                    }
                }
                .frame(minHeight: 190, alignment: .top)
            }
        }
        .padding(16)
        .background(InsightCardBackground())
    }

    private func appRow(_ app: AppInputActivity, rank: Int, maximum: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                AppActivityIcon(bundleIdentifier: app.bundleIdentifier, rank: rank)
                Text(app.name ?? app.bundleIdentifier ?? L("history.apps.unknown"))
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(compactHistoryNumber(app.characterCount))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(Color.accentColor.opacity(0.85 - Double(rank) * 0.1))
                        .frame(width: proxy.size.width * CGFloat(app.characterCount) / CGFloat(maximum))
                }
            }
            .frame(height: 5)
        }
    }
}

private struct AppActivityIcon: View {
    let bundleIdentifier: String?
    let rank: Int

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: rank == 0 ? "app.fill" : "app")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(rank == 0 ? Color.accentColor : .secondary)
                    .padding(2)
            }
        }
        .frame(width: 15, height: 15)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityHidden(true)
    }

    private var icon: NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 30, height: 30)
        return image
    }
}

struct HourlyInsightCard: View {
    let activity: [HourInputActivity]

    var body: some View {
        let maximum = max(activity.map(\.inputCount).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 12) {
            InsightCardHeader(
                title: L("history.rhythm.title"),
                subtitle: L("history.rhythm.subtitle"),
                symbol: "clock"
            )
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(activity) { point in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(point.inputCount, maximum: maximum))
                        .frame(maxWidth: .infinity)
                        .frame(height: 12 + 32 * CGFloat(point.inputCount) / CGFloat(maximum))
                        .help(String(format: L("history.rhythm.hour_detail"), point.hour, point.inputCount))
                        .accessibilityLabel(String(format: L("history.rhythm.hour_detail"), point.hour, point.inputCount))
                }
            }
            HStack {
                Text("00:00")
                Spacer()
                Text("06:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("18:00")
                Spacer()
                Text("23:00")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(InsightCardBackground())
    }

    private func barColor(_ count: Int, maximum: Int) -> Color {
        let opacity = count == 0 ? 0.08 : 0.22 + 0.72 * Double(count) / Double(maximum)
        return Color.accentColor.opacity(opacity)
    }
}

struct InsightCardHeader: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 25, height: 25)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct InsightCardBackground: View {
    var body: some View {
        SettingsCardBackground()
    }
}

func compactHistoryNumber(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 10_000 { return String(format: "%.1fK", Double(value) / 1_000) }
    return value.formatted()
}

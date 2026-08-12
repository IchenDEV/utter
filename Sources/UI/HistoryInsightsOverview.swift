import Charts
import SwiftUI

struct HistoryInsightsOverview: View {
    let analytics: InputHistoryAnalytics
    @Binding var range: InputAnalyticsRange

    private let metricColumns = [GridItem(.adaptive(minimum: 155), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                rangeBar
                metrics
                chartRow
                HourlyInsightCard(activity: analytics.hourlyActivity)
            }
            .padding(20)
        }
    }

    private var rangeBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("history.overview.title"))
                    .font(.headline)
                Text(L("history.overview.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker(L("history.range.label"), selection: $range) {
                ForEach(InputAnalyticsRange.allCases) { item in
                    Text(rangeLabel(item)).tag(item)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: metricColumns, spacing: 12) {
            metricCard(
                title: L("history.metric.characters"),
                value: compactHistoryNumber(analytics.totalCharacters),
                symbol: "character.cursor.ibeam",
                color: .accentColor,
                detail: changeLabel
            )
            metricCard(
                title: L("history.metric.inputs"),
                value: compactHistoryNumber(analytics.totalInputs),
                symbol: "waveform.badge.mic",
                color: .accentColor,
                detail: String(format: L("history.metric.inputs_detail"), analytics.activeDays)
            )
            metricCard(
                title: L("history.metric.active_days"),
                value: "\(analytics.activeDays)",
                symbol: "calendar.badge.checkmark",
                color: .accentColor,
                detail: rangeLabel(range)
            )
            metricCard(
                title: L("history.metric.average"),
                value: compactHistoryNumber(analytics.averageCharacters),
                symbol: "gauge.with.dots.needle.67percent",
                color: .accentColor,
                detail: L("history.metric.average_detail")
            )
        }
    }

    private func metricCard(
        title: String,
        value: String,
        symbol: String,
        color: Color,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var chartRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                trendCard.frame(minWidth: 460)
                AppUsageInsightCard(activity: analytics.appActivity).frame(width: 280)
            }
            VStack(spacing: 16) {
                trendCard
                AppUsageInsightCard(activity: analytics.appActivity)
            }
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartHeader(L("history.chart.title"), subtitle: L("history.chart.subtitle"), symbol: "chart.xyaxis.line")

            if analytics.totalInputs == 0 {
                chartEmptyState
            } else {
                Chart(analytics.dailyActivity) { point in
                    AreaMark(
                        x: .value(L("history.chart.day"), point.day),
                        y: .value(L("history.chart.characters"), point.characterCount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.32), Color.accentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value(L("history.chart.day"), point.day),
                        y: .value(L("history.chart.characters"), point.characterCount)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.accentColor)

                    if point.characterCount > 0 {
                        PointMark(
                            x: .value(L("history.chart.day"), point.day),
                            y: .value(L("history.chart.characters"), point.characterCount)
                        )
                        .symbolSize(range == .sevenDays ? 28 : 12)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: range == .sevenDays ? 7 : 6)) { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(shortDate(date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel()
                    }
                }
                .frame(height: 190)
                .accessibilityLabel(L("history.chart.accessibility"))
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func chartHeader(_ title: String, subtitle: String, symbol: String) -> some View {
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

    private var chartEmptyState: some View {
        HStack(spacing: 12) {
            SettingsPageIllustration(kind: .activity, size: 64)
            Text(L("history.empty"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
            }
    }

    private var changeLabel: String {
        guard let change = analytics.characterChange else { return L("history.change.new") }
        if abs(change) < 0.005 { return L("history.change.flat") }
        return String(format: change > 0 ? L("history.change.up") : L("history.change.down"), abs(change) * 100)
    }

    private func rangeLabel(_ range: InputAnalyticsRange) -> String {
        L("history.range.\(range.rawValue)")
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = range == .sevenDays ? "E" : "M/d"
        return formatter.string(from: date)
    }
}

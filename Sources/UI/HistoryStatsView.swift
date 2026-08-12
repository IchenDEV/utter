import SwiftUI

private enum HistorySection: String, CaseIterable, Identifiable {
    case insights
    case records

    var id: Self { self }
    var label: String { L("history.section.\(rawValue)") }
}

struct HistoryStatsView: View {
    @StateObject private var history = InputHistory.shared
    @State private var section: HistorySection = .insights
    @State private var range: InputAnalyticsRange = .sevenDays

    var body: some View {
        VStack(spacing: 0) {
            SettingsPageHeader(
                kind: .activity,
                title: L("history.title"),
                subtitle: L("history.subtitle")
            ) {
                Picker(L("history.section.label"), selection: $section) {
                    ForEach(HistorySection.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
            Divider()

            switch section {
            case .insights:
                HistoryInsightsOverview(
                    analytics: .make(records: history.records, range: range),
                    range: $range
                )
            case .records:
                HistoryRecordsView(history: history)
            }
        }
        .settingsPageSurface()
    }
}

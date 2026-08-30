import SwiftUI

enum HistorySection: String, CaseIterable, Identifiable {
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
        Group {
            switch section {
            case .insights:
                HistoryInsightsOverview(
                    analytics: .make(records: history.records, range: range),
                    range: $range,
                    section: $section
                )
            case .records:
                HistoryRecordsView(history: history, section: $section)
            }
        }
        .settingsPageSurface()
    }
}

struct HistoryModePicker: View {
    @Binding var selection: HistorySection

    var body: some View {
        Picker(L("history.section.label"), selection: $selection) {
            ForEach(HistorySection.allCases) { item in
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .frame(width: 140)
    }
}

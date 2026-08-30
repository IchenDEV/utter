import AppKit
import SwiftUI

struct HistoryRecordsView: View {
    @ObservedObject var history: InputHistory
    @Binding var section: HistorySection
    @ObservedObject private var settings = AppSettings.shared
    @State private var searchText = ""
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField(L("history.search"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 260)

            Text(String(format: L("history.records_count"), filteredRecords.count))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HistoryModePicker(selection: $section)

            Picker(L("settings.history_retention"), selection: $settings.historyRetention) {
                ForEach(HistoryRetention.allCases, id: \.self) { Text($0.label) }
            }
            .labelsHidden()
            .frame(width: 110)
            .controlSize(.small)

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label(L("history.clear_all"), systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(history.records.isEmpty)
            .help(L("history.clear_all"))
            .accessibilityLabel(L("history.clear_all"))
            .alert(L("history.clear_confirm"), isPresented: $showClearConfirm) {
                Button(L("common.cancel"), role: .cancel) {}
                Button(L("common.clear"), role: .destructive) { history.clearAll() }
            } message: {
                Text(L("common.cannot_undo"))
            }
        }
        .padding(.horizontal, SettingsPageLayout.contentInset)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if filteredRecords.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredRecords) { record in
                        recordCard(record)
                    }
                }
                .padding(SettingsPageLayout.contentInset)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text(searchText.isEmpty ? L("history.empty") : L("history.no_match"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredRecords: [InputRecord] {
        searchText.isEmpty ? history.records : history.records.filter { $0.matchesSearch(searchText) }
    }

    private func recordCard(_ record: InputRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.displayText)
                    .font(.body)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(formatDate(record.date))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if record.wasProcessed && record.rawText != record.processedText {
                Label {
                    Text(record.rawText)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "quote.bubble")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Label(metadataText(for: record), systemImage: "app")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if record.wasProcessed && record.rawCharCount != record.processedCharCount {
                    let delta = record.rawCharCount - record.processedCharCount
                    Text(delta > 0
                         ? String(format: L("history.chars_saved_fmt"), delta)
                         : String(format: L("history.chars_added_fmt"), abs(delta)))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(delta > 0 ? .green : .orange)
                }

                Spacer()

                Button { copy(record) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(L("common.copy"))
                .accessibilityLabel(L("common.copy"))

                Button(role: .destructive) { history.deleteRecord(record.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L("common.delete"))
                .accessibilityLabel(L("common.delete"))
            }
        }
        .padding(12)
        .background(SettingsCardBackground(cornerRadius: 10))
        .contextMenu {
            Button(L("common.copy")) { copy(record) }
            Divider()
            Button(L("common.delete"), role: .destructive) { history.deleteRecord(record.id) }
        }
    }

    private func copy(_ record: InputRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.displayText, forType: .string)
    }

    private func metadataText(for record: InputRecord) -> String {
        var parts: [String] = []
        if let context = record.context {
            parts.append(context.appName ?? context.bundleIdentifier ?? L("history.apps.unknown"))
            parts.append(context.outputMode.label)
            if let title = context.windowTitle { parts.append(title) }
        } else {
            parts.append(L("history.apps.unknown"))
        }
        return parts.joined(separator: " · ")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return L("history.date_today") + " " + formatter.string(from: date)
        }
        if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return L("history.date_yesterday") + " " + formatter.string(from: date)
        }
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

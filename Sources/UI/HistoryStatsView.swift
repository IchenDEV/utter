import SwiftUI

struct HistoryStatsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var history = InputHistory.shared
    @State private var searchText = ""
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            statsRow
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            historyContent
        }
    }

    // MARK: - Top bar with search

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField(L("history.search"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Picker("", selection: $settings.historyRetention) {
                ForEach(HistoryRetention.allCases, id: \.self) { Text($0.label) }
            }
            .labelsHidden()
            .frame(width: 110)
            .controlSize(.small)

            if !history.records.isEmpty {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("history.clear_all"))
                .alert(L("history.clear_confirm"), isPresented: $showClearConfirm) {
                    Button(L("common.cancel"), role: .cancel) {}
                    Button(L("common.clear"), role: .destructive) { history.clearAll() }
                } message: {
                    Text(L("common.cannot_undo"))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Compact stats

    private var statsRow: some View {
        let s = history.stats
        return HStack(spacing: 0) {
            statPill(value: "\(s.totalInputs)", label: L("history.total"), icon: "text.bubble")
            Spacer()
            statPill(value: "\(s.todayInputs)", label: L("history.today"), icon: "calendar")
            Spacer()
            statPill(value: formatChars(s.totalProcessedChars), label: L("history.chars"), icon: "character.cursor.ibeam")
            Spacer()
            statPill(
                value: s.totalRawChars > 0 ? "\(Int(s.efficiencyRatio * 100))%" : "—",
                label: L("history.saved"), icon: "bolt"
            )
        }
    }

    private func statPill(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.tint)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func formatChars(_ count: Int) -> String {
        if count >= 10_000 { return String(format: "%.1fk", Double(count) / 1000) }
        return "\(count)"
    }

    // MARK: - History content

    private var historyContent: some View {
        Group {
            if filteredRecords.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "clock" : "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text(searchText.isEmpty ? L("history.empty") : L("history.no_match"))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredRecords) { record in
                    recordCard(record)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var filteredRecords: [InputRecord] {
        if searchText.isEmpty { return history.records }
        return history.records.filter { $0.matchesSearch(searchText) }
    }

    // MARK: - Record card

    private func recordCard(_ record: InputRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.displayText)
                .font(.system(size: 12))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if record.wasProcessed && record.rawText != record.processedText {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                        .padding(.top, 1)
                    Text(record.rawText)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Text(metadataText(for: record))
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .lineLimit(1)

            HStack(spacing: 6) {
                if record.wasProcessed && record.rawCharCount != record.processedCharCount {
                    let delta = record.rawCharCount - record.processedCharCount
                    Text(delta > 0
                         ? String(format: L("history.chars_saved_fmt"), delta)
                         : String(format: L("history.chars_added_fmt"), abs(delta)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(delta > 0 ? .green : .orange)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.displayText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(L("common.copy"))

                Button {
                    history.deleteRecord(record.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
                .help(L("common.delete"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func metadataText(for record: InputRecord) -> String {
        var parts = [formatDate(record.date)]
        if let context = record.context {
            parts.append(context.outputMode.label)
            if let appName = context.appName ?? context.bundleIdentifier {
                parts.append(appName)
            }
            if let windowTitle = context.windowTitle {
                parts.append(windowTitle)
            }
        }
        return parts.joined(separator: " / ")
    }

    // MARK: - Date formatting

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return L("history.date_today") + " " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return L("history.date_yesterday") + " " + formatter.string(from: date)
        } else {
            formatter.dateFormat = "MM/dd HH:mm"
            return formatter.string(from: date)
        }
    }
}

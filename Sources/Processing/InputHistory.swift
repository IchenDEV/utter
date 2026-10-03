import Foundation
import UtterContracts

@MainActor
final class InputHistory: ObservableObject {
    static let shared = InputHistory()

    @Published private(set) var records: [InputRecord] = []

    private let fileURL: URL
    private static let maxRecords = 500

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(ProductBrand.applicationSupportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("input_history.json")
        load()
        pruneExpired()
    }

    @discardableResult
    func addRecord(
        rawText: String,
        processedText: String,
        wasProcessed: Bool,
        context: InputContext? = nil,
        formatKind: TextFormatKind? = nil
    ) -> UUID {
        let record = InputRecord(
            rawText: rawText,
            processedText: processedText,
            wasProcessed: wasProcessed,
            context: context,
            formatKind: formatKind
        )
        records.insert(record, at: 0)
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }
        pruneExpired()
        save()
        return record.id
    }

    @discardableResult
    func replaceLatestRecord(
        rawText: String,
        processedText: String,
        wasProcessed: Bool,
        context: InputContext? = nil,
        formatKind: TextFormatKind? = nil
    ) -> UUID {
        guard let latest = records.first, latest.rawText == rawText else {
            return addRecord(
                rawText: rawText,
                processedText: processedText,
                wasProcessed: wasProcessed,
                context: context,
                formatKind: formatKind
            )
        }

        records[0] = InputRecord(
            id: latest.id,
            date: latest.date,
            rawText: rawText,
            processedText: processedText,
            wasProcessed: wasProcessed,
            context: context ?? latest.context,
            formatKind: formatKind ?? latest.formatKind
        )
        save()
        return latest.id
    }

    func updateUserFinalText(recordID: UUID, text: String) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        let record = records[index]
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = normalized.isEmpty || normalized == record.processedText ? nil : normalized
        records[index] = InputRecord(
            id: record.id,
            date: record.date,
            rawText: record.rawText,
            processedText: record.processedText,
            wasProcessed: record.wasProcessed,
            context: record.context,
            userFinalText: finalText,
            formatKind: record.formatKind
        )
        save()
    }

    func deleteRecord(_ id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    var stats: InputStats {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        let todayRecords = records.filter { $0.date >= todayStart }
        let totalRaw = records.reduce(0) { $0 + $1.rawCharCount }
        let totalProcessed = records.reduce(0) { $0 + $1.processedCharCount }

        let uniqueDays = Set(records.map { calendar.startOfDay(for: $0.date) })
        var streak = 0
        var checkDate = todayStart
        while uniqueDays.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }

        return InputStats(
            totalInputs: records.count,
            totalRawChars: totalRaw,
            totalProcessedChars: totalProcessed,
            charsSaved: max(0, totalRaw - totalProcessed),
            todayInputs: todayRecords.count,
            todayChars: todayRecords.reduce(0) { $0 + $1.displayText.count },
            streakDays: streak
        )
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([InputRecord].self, from: data) {
            records = decoded
        }
    }

    private func pruneExpired() {
        guard let interval = AppSettings.shared.historyRetention.timeInterval else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        let before = records.count
        records.removeAll { $0.date < cutoff }
        if records.count < before { save() }
    }
}

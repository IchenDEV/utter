import Foundation
import UtterContracts

@MainActor
package final class HistoryStore: HistoryService {
    package private(set) var records: [InputRecord] = []
    package private(set) var storageAvailable = true
    private static let maxRecords = 500
    private let fileURL: URL
    private let retention: @MainActor () -> HistoryRetention
    private let reportError: (String) -> Void
    private var acceptedIDs: Set<UUID> = []
    private var observers: [UUID: @MainActor () -> Void] = [:]

    package init(directoryURL: URL, retention: @escaping @MainActor () -> HistoryRetention, reportError: @escaping (String) -> Void) {
        self.retention = retention
        self.reportError = reportError
        fileURL = directoryURL.appendingPathComponent("input_history.json")
        do { try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true) }
        catch { storageAvailable = false; reportError("Cannot create history directory: \(error.localizedDescription)") }
        load()
        let count = records.count
        pruneExpired()
        if records.count != count { save() }
    }

    @discardableResult
    package func addRecord(_ record: InputRecord) -> UUID {
        guard !acceptedIDs.contains(record.id), !records.contains(where: { $0.id == record.id }) else {
            return record.id
        }
        acceptedIDs.insert(record.id)
        records.insert(record, at: 0)
        if records.count > Self.maxRecords { records = Array(records.prefix(Self.maxRecords)) }
        pruneExpired()
        save()
        return record.id
    }

    @discardableResult
    package func replaceRecord(recordID: UUID, processedText: String, context: InputContext?, formatKind: TextFormatKind?) -> UUID? {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return nil }
        let previous = records[index]
        records[index] = InputRecord(
            id: previous.id, date: previous.date, rawText: previous.rawText,
            processedText: processedText, wasProcessed: true,
            context: context ?? previous.context, userFinalText: previous.userFinalText,
            formatKind: formatKind ?? previous.formatKind
        )
        save()
        return previous.id
    }

    package func updateUserFinalText(recordID: UUID, text: String) {
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

    package func deleteRecord(_ id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    package func clearAll() {
        records.removeAll()
        save()
    }

    package var stats: InputStats {
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

    package func observe(_ callback: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }

    package func removeObserver(_ id: UUID) { observers[id] = nil }

    private func save() {
        if storageAvailable {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                try encoder.encode(records).write(to: fileURL, options: .atomic)
            } catch {
                reportError("Cannot save history: \(error.localizedDescription)")
            }
        } else {
            reportError("Stored history is unavailable; its original file was preserved")
        }
        for id in observers.keys.sorted(by: { $0.uuidString < $1.uuidString }) { observers[id]?() }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([InputRecord].self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        } catch {
            storageAvailable = false
            reportError("Cannot load history: \(error.localizedDescription)")
        }
    }

    private func pruneExpired() {
        guard let interval = retention().timeInterval else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        records.removeAll { $0.date < cutoff }
    }
}

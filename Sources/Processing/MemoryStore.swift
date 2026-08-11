import Foundation

@MainActor
enum MemoryStore {
    static func recentContext(
        limit: Int = 5,
        windowMinutes: Int = 30,
        currentContext: InputContext? = nil
    ) -> String {
        recentContext(
            records: InputHistory.shared.records,
            currentContext: currentContext,
            limit: limit,
            windowMinutes: windowMinutes
        )
    }

    static func recentContext(
        records: [InputRecord],
        currentContext: InputContext? = nil,
        limit: Int = 5,
        windowMinutes: Int = 30,
        now: Date = Date()
    ) -> String {
        let cutoff = now.addingTimeInterval(-Double(windowMinutes) * 60)

        let recent = records
            .filter { $0.date >= cutoff }
        let selected = rankedRecords(recent, currentContext: currentContext)
            .prefix(limit)
            .sorted { $0.date < $1.date }

        guard !selected.isEmpty else { return "" }

        let lines = selected.map { record in
            let text = record.userFinalText ?? (record.wasProcessed ? record.processedText : record.rawText)
            return "[\(formatTime(record.date))\(formatContext(record.context))] \(text)"
        }

        return lines.joined(separator: "\n")
    }

    private static func rankedRecords(_ records: [InputRecord], currentContext: InputContext?) -> [InputRecord] {
        records.sorted { lhs, rhs in
            let lhsScore = score(lhs.context, against: currentContext)
            let rhsScore = score(rhs.context, against: currentContext)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.date > rhs.date
        }
    }

    private static func score(_ recordContext: InputContext?, against currentContext: InputContext?) -> Int {
        guard let recordContext, let currentContext else { return 0 }

        var score = 0
        if matches(recordContext.bundleIdentifier, currentContext.bundleIdentifier) {
            score += 100
        }
        if matches(recordContext.appName, currentContext.appName) {
            score += 40
        }
        if matches(recordContext.windowTitle, currentContext.windowTitle) {
            score += 25
        }
        return score
    }

    private static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func formatContext(_ context: InputContext?) -> String {
        guard let context else { return "" }
        let app = context.appName ?? context.bundleIdentifier
        let window = context.windowTitle
        let parts = [app, window].compactMap { $0 }
        guard !parts.isEmpty else { return "" }
        return " " + parts.joined(separator: " / ")
    }
}

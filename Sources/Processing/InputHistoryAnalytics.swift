import Foundation

enum InputAnalyticsRange: String, CaseIterable, Identifiable {
    case sevenDays
    case thirtyDays
    case allTime

    var id: Self { self }

    var dayCount: Int? {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .allTime: return nil
        }
    }
}

struct DailyInputActivity: Identifiable, Equatable {
    let day: Date
    let inputCount: Int
    let characterCount: Int

    var id: Date { day }
}

struct AppInputActivity: Identifiable, Equatable {
    let name: String?
    let bundleIdentifier: String?
    let inputCount: Int
    let characterCount: Int

    var id: String { bundleIdentifier ?? name ?? "unknown" }
}

struct HourInputActivity: Identifiable, Equatable {
    let hour: Int
    let inputCount: Int

    var id: Int { hour }
}

struct InputHistoryAnalytics {
    let records: [InputRecord]
    let totalInputs: Int
    let totalCharacters: Int
    let averageCharacters: Int
    let activeDays: Int
    let characterChange: Double?
    let dailyActivity: [DailyInputActivity]
    let appActivity: [AppInputActivity]
    let hourlyActivity: [HourInputActivity]

    static func make(
        records: [InputRecord],
        range: InputAnalyticsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> InputHistoryAnalytics {
        let selected = records.filter { dateIsIncluded($0.date, in: range, now: now, calendar: calendar) }
        let totalCharacters = selected.reduce(0) { $0 + $1.displayText.count }
        let uniqueDays = Set(selected.map { calendar.startOfDay(for: $0.date) })

        return InputHistoryAnalytics(
            records: selected,
            totalInputs: selected.count,
            totalCharacters: totalCharacters,
            averageCharacters: selected.isEmpty ? 0 : totalCharacters / selected.count,
            activeDays: uniqueDays.count,
            characterChange: changeComparedWithPreviousPeriod(
                records: records,
                range: range,
                currentCharacters: totalCharacters,
                now: now,
                calendar: calendar
            ),
            dailyActivity: dailyActivity(from: selected, range: range, now: now, calendar: calendar),
            appActivity: appActivity(from: selected),
            hourlyActivity: hourlyActivity(from: selected, calendar: calendar)
        )
    }

    private static func dateIsIncluded(
        _ date: Date,
        in range: InputAnalyticsRange,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard date <= now else { return false }
        guard let dayCount = range.dayCount else { return true }
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        return date >= start
    }

    private static func dailyActivity(
        from records: [InputRecord],
        range: InputAnalyticsRange,
        now: Date,
        calendar: Calendar
    ) -> [DailyInputActivity] {
        let today = calendar.startOfDay(for: now)
        let start: Date
        if let dayCount = range.dayCount {
            start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        } else {
            start = records.map { calendar.startOfDay(for: $0.date) }.min() ?? today
        }

        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
        var points: [DailyInputActivity] = []
        var day = start
        while day <= today {
            let dayRecords = grouped[day] ?? []
            points.append(DailyInputActivity(
                day: day,
                inputCount: dayRecords.count,
                characterCount: dayRecords.reduce(0) { $0 + $1.displayText.count }
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    private static func appActivity(from records: [InputRecord]) -> [AppInputActivity] {
        let grouped = Dictionary(grouping: records) { record in
            record.context?.bundleIdentifier ?? record.context?.appName ?? ""
        }
        return grouped.map { _, appRecords in
            AppInputActivity(
                name: appRecords.compactMap(\.context?.appName).first,
                bundleIdentifier: appRecords.compactMap(\.context?.bundleIdentifier).first,
                inputCount: appRecords.count,
                characterCount: appRecords.reduce(0) { $0 + $1.displayText.count }
            )
        }
        .sorted {
            $0.characterCount == $1.characterCount
                ? $0.inputCount > $1.inputCount
                : $0.characterCount > $1.characterCount
        }
    }

    private static func hourlyActivity(from records: [InputRecord], calendar: Calendar) -> [HourInputActivity] {
        let counts = Dictionary(grouping: records) { calendar.component(.hour, from: $0.date) }
        return (0..<24).map { HourInputActivity(hour: $0, inputCount: counts[$0]?.count ?? 0) }
    }

    private static func changeComparedWithPreviousPeriod(
        records: [InputRecord],
        range: InputAnalyticsRange,
        currentCharacters: Int,
        now: Date,
        calendar: Calendar
    ) -> Double? {
        guard let dayCount = range.dayCount else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let currentStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today),
              let previousStart = calendar.date(byAdding: .day, value: -dayCount, to: currentStart) else {
            return nil
        }
        let previousCharacters = records
            .filter { $0.date >= previousStart && $0.date < currentStart }
            .reduce(0) { $0 + $1.displayText.count }
        guard previousCharacters > 0 else { return nil }
        return Double(currentCharacters - previousCharacters) / Double(previousCharacters)
    }
}

import Foundation
import XCTest
@testable import OpenType

final class InputHistoryTests: XCTestCase {
    func testInputRecordDecodesOldHistoryShape() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "date": "2026-06-13T00:00:00Z",
          "rawText": "open type",
          "processedText": "OpenType",
          "wasProcessed": true
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let record = try decoder.decode(InputRecord.self, from: Data(json.utf8))

        XCTAssertEqual(record.rawCharCount, 9)
        XCTAssertEqual(record.processedCharCount, 8)
        XCTAssertNil(record.context)
        XCTAssertNil(record.userFinalText)
        XCTAssertNil(record.formatKind)
    }

    func testInputRecordSearchMatchesContextFields() {
        let context = InputContext(
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Gmail Inbox",
            screenContext: "Project Orion notes",
            outputMode: .processed,
            inputLanguage: .english,
            source: .menuBar
        )
        let record = InputRecord(rawText: "raw", processedText: "final", wasProcessed: true, context: context)

        XCTAssertTrue(record.matchesSearch("gmail"))
        XCTAssertTrue(record.matchesSearch("safari"))
        XCTAssertTrue(record.matchesSearch("orion"))
        XCTAssertFalse(record.matchesSearch("calendar"))
    }

    func testInputContextTruncatesScreenContext() {
        let context = InputContext(
            appName: "Notes",
            screenContext: String(repeating: "x", count: 1_500),
            outputMode: .command,
            inputLanguage: .chinese,
            source: .menuBar
        )

        XCTAssertEqual(context.screenContext?.count, 1_200)
    }

    func testInputContextTruncatesFocusedTextContext() {
        let context = InputContext(
            textBeforeSelection: String(repeating: "a", count: 700),
            selectedText: String(repeating: "b", count: 700),
            textAfterSelection: String(repeating: "c", count: 700),
            outputMode: .processed,
            inputLanguage: .english,
            source: .menuBar
        )

        XCTAssertEqual(context.textBeforeSelection?.count, 500)
        XCTAssertEqual(context.selectedText?.count, 500)
        XCTAssertEqual(context.textAfterSelection?.count, 500)
    }

    @MainActor
    func testCapturedSelectionOverrideDoesNotBecomeScreenContext() {
        let context = InputContext.capture(
            targetApp: nil,
            screenContext: "",
            selectedTextOverride: "Selected customer note",
            outputMode: .command,
            inputLanguage: .english,
            source: .menuBar
        )

        XCTAssertEqual(context.selectedText, "Selected customer note")
        XCTAssertNil(context.screenContext)
    }

    @MainActor
    func testMemoryStorePrioritizesSameAppContext() {
        let now = Date(timeIntervalSince1970: 10_000)
        let safari = InputContext(
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Gmail",
            outputMode: .processed,
            inputLanguage: .english,
            source: .menuBar
        )
        let notes = InputContext(
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Draft",
            outputMode: .processed,
            inputLanguage: .english,
            source: .menuBar
        )
        let records = [
            InputRecord(id: UUID(), date: now, rawText: "latest notes", processedText: "Latest notes", wasProcessed: true, context: notes),
            InputRecord(id: UUID(), date: now.addingTimeInterval(-60), rawText: "older safari", processedText: "Older Safari", wasProcessed: true, context: safari),
        ]

        let context = MemoryStore.recentContext(
            records: records,
            currentContext: safari,
            limit: 1,
            windowMinutes: 30,
            now: now
        )

        XCTAssertTrue(context.contains("Older Safari"))
        XCTAssertFalse(context.contains("Latest notes"))
        XCTAssertTrue(context.contains("Safari"))
        XCTAssertTrue(context.contains("Gmail"))
    }

    @MainActor
    func testMemoryStorePrefersUserFinalText() {
        let now = Date(timeIntervalSince1970: 10_000)
        let record = InputRecord(
            id: UUID(),
            date: now,
            rawText: "open tape",
            processedText: "OpenTape",
            wasProcessed: true,
            userFinalText: "OpenType",
            formatKind: .plainParagraph
        )

        let context = MemoryStore.recentContext(
            records: [record],
            limit: 1,
            windowMinutes: 30,
            now: now
        )

        XCTAssertTrue(context.contains("OpenType"))
        XCTAssertFalse(context.contains("OpenTape"))
    }

    func testAnalyticsBuildsCompleteDailySeriesAndAppRanking() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 12, hour: 18
        )))
        let notes = InputContext(
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            outputMode: .processed,
            inputLanguage: .english,
            source: .menuBar
        )
        let safari = InputContext(
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            outputMode: .direct,
            inputLanguage: .english,
            source: .menuBar
        )
        let records = [
            analyticsRecord(daysAgo: 0, hour: 9, text: "123456", context: notes, now: now, calendar: calendar),
            analyticsRecord(daysAgo: 1, hour: 14, text: "1234", context: safari, now: now, calendar: calendar),
            analyticsRecord(daysAgo: 8, hour: 12, text: "12345", context: safari, now: now, calendar: calendar),
        ]

        let analytics = InputHistoryAnalytics.make(
            records: records,
            range: .sevenDays,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(analytics.totalInputs, 2)
        XCTAssertEqual(analytics.totalCharacters, 10)
        XCTAssertEqual(analytics.averageCharacters, 5)
        XCTAssertEqual(analytics.activeDays, 2)
        XCTAssertEqual(analytics.dailyActivity.count, 7)
        XCTAssertEqual(analytics.dailyActivity.reduce(0) { $0 + $1.inputCount }, 2)
        XCTAssertEqual(analytics.appActivity.map(\.name), ["Notes", "Safari"])
        XCTAssertEqual(analytics.hourlyActivity[9].inputCount, 1)
        XCTAssertEqual(analytics.hourlyActivity[14].inputCount, 1)
        XCTAssertEqual(try XCTUnwrap(analytics.characterChange), 1, accuracy: 0.001)
    }

    func testAllTimeAnalyticsStartsAtOldestRecord() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 12, hour: 18
        )))
        let records = [
            analyticsRecord(daysAgo: 2, hour: 9, text: "one", now: now, calendar: calendar),
            analyticsRecord(daysAgo: 0, hour: 10, text: "two", now: now, calendar: calendar),
        ]

        let analytics = InputHistoryAnalytics.make(
            records: records,
            range: .allTime,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(analytics.dailyActivity.count, 3)
        XCTAssertNil(analytics.characterChange)
    }

    private func analyticsRecord(
        daysAgo: Int,
        hour: Int,
        text: String,
        context: InputContext? = nil,
        now: Date,
        calendar: Calendar
    ) -> InputRecord {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        let date = calendar.date(byAdding: .hour, value: hour, to: day)!
        return InputRecord(
            id: UUID(),
            date: date,
            rawText: text,
            processedText: text,
            wasProcessed: context?.outputMode == .processed,
            context: context
        )
    }
}

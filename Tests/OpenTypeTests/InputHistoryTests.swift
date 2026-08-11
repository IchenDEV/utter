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
}

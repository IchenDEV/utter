import Foundation
import XCTest
import UtterContracts
@testable import UtterData

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testReplacementUpdatesItsRecordWhenAnotherSessionHasCommitted() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directoryURL: directory, retention: { .forever }, reportError: { _ in })
        let first = InputRecord(rawText: "same raw", processedText: "initial", wasProcessed: false)
        let newer = InputRecord(rawText: "same raw", processedText: "newer", wasProcessed: false)
        store.addRecord(first)
        store.addRecord(newer)
        XCTAssertEqual(store.replaceRecord(recordID: first.id, processedText: "formatted", context: nil, formatKind: nil), first.id)
        XCTAssertEqual(store.records.map(\.id), [newer.id, first.id])
        XCTAssertEqual(store.records.map(\.processedText), ["newer", "formatted"])
        let reopened = HistoryStore(directoryURL: directory, retention: { .forever }, reportError: { _ in })
        XCTAssertEqual(reopened.records.map(\.processedText), ["newer", "formatted"])
        XCTAssertEqual(reopened.records.last?.date.timeIntervalSince1970 ?? 0, first.date.timeIntervalSince1970, accuracy: 1)
    }

    func testDeletedRecordDoesNotReappearOnReplacementOrRepeatedCommit() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directoryURL: directory, retention: { .forever }, reportError: { _ in })
        let record = InputRecord(rawText: "raw", processedText: "initial", wasProcessed: false)
        store.addRecord(record)
        store.addRecord(record)
        XCTAssertEqual(store.records.count, 1)
        store.deleteRecord(record.id)
        store.addRecord(record)
        XCTAssertNil(store.replaceRecord(recordID: record.id, processedText: "formatted", context: nil, formatKind: nil))
        XCTAssertTrue(store.records.isEmpty)
    }

    func testCorruptStoredHistoryIsPreservedWhenNewInputArrives() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("input_history.json")
        let original = Data("corrupt synthetic history".utf8)
        try original.write(to: url)
        var errors: [String] = []
        let store = HistoryStore(directoryURL: directory, retention: { .forever }, reportError: { errors.append($0) })
        store.addRecord(InputRecord(rawText: "raw", processedText: "valid", wasProcessed: false))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertFalse(errors.isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

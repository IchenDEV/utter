import Foundation
import XCTest
import UtterContracts
@testable import UtterData

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testDeliveryEvidenceSurvivesReloadCorrectionAndReplacement() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directoryURL: directory, retention: { .forever }, reportError: { _ in })
        for status in [DeliveryStatus.inserted, .copied, .uncertain, .notDelivered] {
            let record = InputRecord(rawText: "raw", processedText: "text", wasProcessed: false, deliveryStatus: status)
            store.addRecord(record)
            store.updateUserFinalText(recordID: record.id, text: "edited")
            store.replaceRecord(recordID: record.id, processedText: "formatted", context: nil, formatKind: nil)
        }
        let reopened = HistoryStore(directoryURL: directory, retention: { .forever }, reportError: { _ in })
        XCTAssertEqual(reopened.records.map(\.deliveryStatus), [.notDelivered, .uncertain, .copied, .inserted])
        XCTAssertEqual(reopened.stats.totalInputs, 1)
    }

    func testLegacyRecordDecodesWithoutInventingDeliveryProof() throws {
        let record = InputRecord(rawText: "raw", processedText: "text", wasProcessed: false)
        let encoded = try JSONEncoder().encode(record)
        let old = try JSONDecoder().decode(InputRecord.self, from: encoded)
        XCTAssertNil(old.deliveryStatus)
    }

    func testRemovedObserverDoesNotReceiveAnAlreadyQueuedCommit() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notifications = StateNotifications()
        let store = HistoryStore(directoryURL: directory, retention: { .forever }, reportError: { _ in }, notifications: notifications)
        var calls = 0
        let id = store.observe { calls += 1 }
        notifications.settle {
            store.addRecord(InputRecord(rawText: "raw", processedText: "final", wasProcessed: true))
            store.removeObserver(id)
        }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(store.records.count, 1)
    }

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

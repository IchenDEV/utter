import Foundation
import XCTest
import UtterContracts
@testable import UtterData

final class DictionaryStorageRecoveryTests: XCTestCase {
    func testCorruptDictionarySurvivesMutationsAndReopening() throws {
        try withDirectory { directory in
            let file = directory.appendingPathComponent("dictionary.json")
            let original = Data("{invalid dictionary".utf8)
            try original.write(to: file)
            let store = DictionaryStore(directoryURL: directory)
            XCTAssertFalse(store.storageAvailable)
            store.addEntry(original: "wrong", replacement: "right")
            store.addRule(description: "Keep abbreviations")
            store.save()
            XCTAssertEqual(try Data(contentsOf: file), original)
            let reopened = DictionaryStore(directoryURL: directory)
            XCTAssertTrue(reopened.entries.isEmpty)
            XCTAssertEqual(reopened.editRules.map(\.description), ["Keep abbreviations"])
        }
    }

    func testCorruptRulesDoNotBlockHealthyDictionaryPersistence() throws {
        try withDirectory { directory in
            let file = directory.appendingPathComponent("edit_rules.json")
            let original = Data("[invalid rule".utf8)
            try original.write(to: file)
            let store = DictionaryStore(directoryURL: directory)
            XCTAssertFalse(store.storageAvailable)
            store.addRule(description: "New rule")
            store.addEntry(original: "wrong", replacement: "right")
            XCTAssertEqual(try Data(contentsOf: file), original)
            let reopened = DictionaryStore(directoryURL: directory)
            XCTAssertTrue(reopened.editRules.isEmpty)
            XCTAssertEqual(reopened.entries.first?.replacement, "right")
        }
    }

    func testUnreadableStorageIsPreserved() throws {
        try withDirectory { directory in
            let file = directory.appendingPathComponent("dictionary.json")
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            let marker = file.appendingPathComponent("original")
            try Data("preserve".utf8).write(to: marker)
            let store = DictionaryStore(directoryURL: directory)
            XCTAssertFalse(store.storageAvailable)
            store.addEntry(original: "wrong", replacement: "right")
            XCTAssertEqual(try Data(contentsOf: marker), Data("preserve".utf8))
        }
    }

    private func withDirectory(_ operation: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(directory)
    }
}

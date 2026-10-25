import XCTest
@testable import UtterRemoteMic

final class RemoteButtonMappingPolicyTests: XCTestCase {
    private let f5 = RemoteKeyMappingPolicy.ours
    private let right = KeyMappingEntry(source: RemoteButton.right.hidSource, destination: 0)
    private let home = KeyMappingEntry(source: RemoteButton.home.hidSource, destination: 0)
    private let foreignRight = KeyMappingEntry(source: RemoteButton.right.hidSource, destination: 0x7_0000_0041)
    private let capsToEscape = KeyMappingEntry(source: 0x7_0000_0039, destination: 0x7_0000_0029)
    private let unrelatedToNothing = KeyMappingEntry(source: 0x7_0000_0004, destination: 0)

    // MARK: desired set

    func testDesiredSetStartsWithTheVoiceKeyAndListsEachButtonOnce() {
        let sources = [RemoteButton.right.hidSource, RemoteButton.home.hidSource, RemoteButton.right.hidSource]
        XCTAssertEqual(RemoteKeyMappingPolicy.desiredEntries(owning: sources), [f5, right, home])
    }

    func testDesiredSetDropsUnknownSourcesAndAVoiceKeyDuplicate() {
        let sources = [0x7_0000_0004, RemoteKeyMappingPolicy.voiceKeySource, 0xC_0000_00E9, RemoteButton.ok.hidSource]
        XCTAssertEqual(
            RemoteKeyMappingPolicy.desiredEntries(owning: sources),
            [f5, KeyMappingEntry(source: RemoteButton.ok.hidSource, destination: 0)]
        )
    }

    func testNothingOwnedIsJustTheVoiceKey() {
        XCTAssertEqual(RemoteKeyMappingPolicy.desiredEntries(owning: []), [f5])
    }

    // MARK: ownership is by source and destination

    func testOnlyAKnownKeyMappedToNothingIsOurs() {
        XCTAssertTrue(RemoteKeyMappingPolicy.isOurs(f5))
        XCTAssertTrue(RemoteKeyMappingPolicy.isOurs(right))
        XCTAssertFalse(RemoteKeyMappingPolicy.isOurs(foreignRight), "another tool's mapping of the same key")
        XCTAssertFalse(RemoteKeyMappingPolicy.isOurs(unrelatedToNothing), "another key mapped to nothing")
        XCTAssertFalse(RemoteKeyMappingPolicy.isOurs(capsToEscape))
    }

    // MARK: applying

    func testApplyingAddsEveryDesiredEntryAndKeepsOthersInPlace() {
        let result = RemoteKeyMappingPolicy.applying(existing: [capsToEscape], desired: [f5, right, home])
        XCTAssertEqual(result, [capsToEscape, f5, right, home])
    }

    func testApplyingReplacesAnotherToolsEntryForAnOwnedKey() {
        let result = RemoteKeyMappingPolicy.applying(existing: [foreignRight, capsToEscape], desired: [f5, right])
        XCTAssertEqual(result, [capsToEscape, f5, right])
    }

    func testApplyingIsIdempotentWhateverTheOrderOfOurEntries() {
        let existing = [right, capsToEscape, f5]
        XCTAssertEqual(RemoteKeyMappingPolicy.applying(existing: existing, desired: [f5, right]), existing)
    }

    func testApplyingDropsAReleasedKeyAndLeavesAnotherKeyMappedToNothingAlone() {
        let result = RemoteKeyMappingPolicy.applying(existing: [f5, right, unrelatedToNothing], desired: [f5])
        XCTAssertEqual(result, [unrelatedToNothing, f5])
    }

    func testApplyingPutsBackWhatAnotherToolHadOnAReleasedKey() {
        let result = RemoteKeyMappingPolicy.applying(
            existing: [capsToEscape, f5, right], desired: [f5],
            original: [capsToEscape, foreignRight], previous: [f5, right]
        )
        XCTAssertEqual(result, [capsToEscape, foreignRight, f5])
    }

    func testApplyingDoesNotResurrectAnOriginalEntryThatAnotherToolRemovedMeanwhile() {
        let result = RemoteKeyMappingPolicy.applying(
            existing: [f5, right], desired: [f5], original: [capsToEscape], previous: [f5, right]
        )
        XCTAssertEqual(result, [f5], "an original entry for a key we never owned is not ours to restore")
    }

    func testApplyingDoesNotOverrideAnotherToolsNewerEntryOnAReleasedKey() {
        let newer = KeyMappingEntry(source: RemoteButton.right.hidSource, destination: 0x7_0000_0042)
        let result = RemoteKeyMappingPolicy.applying(
            existing: [f5, newer], desired: [f5], original: [foreignRight], previous: [f5, right]
        )
        XCTAssertEqual(result, [f5, newer], "already in the wanted state, so returned as it was")
    }

    // MARK: sync

    func testSyncNeedsEverythingDesiredAndNothingStaleOfOurs() {
        XCTAssertTrue(RemoteKeyMappingPolicy.isSynced([capsToEscape, f5, right], with: [f5, right]))
        XCTAssertFalse(RemoteKeyMappingPolicy.isSynced([f5], with: [f5, right]), "missing")
        XCTAssertFalse(RemoteKeyMappingPolicy.isSynced([f5, right, home], with: [f5, right]), "stale home")
        XCTAssertTrue(RemoteKeyMappingPolicy.isSynced([f5, foreignRight], with: [f5]), "foreign entries are not ours")
    }

    // MARK: snapshot and restoring

    func testSnapshotDropsEveryLeftoverOfOursFromAnyEarlyProfile() {
        XCTAssertEqual(RemoteKeyMappingPolicy.snapshot(of: [f5, right, home, capsToEscape, foreignRight]), [capsToEscape, foreignRight])
    }

    func testRestoringRemovesAllOursAndReturnsForeignEntriesOnlyForOwnedKeys() {
        let result = RemoteKeyMappingPolicy.restoring(
            original: [capsToEscape, foreignRight], current: [capsToEscape, f5, right], owned: [f5, right]
        )
        XCTAssertEqual(result, [capsToEscape, foreignRight])
    }

    func testRestoringDoesNotBringBackAnEntryForAKeyWeDidNotOwn() {
        let result = RemoteKeyMappingPolicy.restoring(original: [foreignRight], current: [f5], owned: [f5])
        XCTAssertEqual(result, [])
    }

    func testRestoringKeepsAnotherToolsNewerEntryForAnOwnedKey() {
        let newer = KeyMappingEntry(source: RemoteButton.right.hidSource, destination: 0x7_0000_0042)
        let result = RemoteKeyMappingPolicy.restoring(original: [foreignRight], current: [f5, right, newer], owned: [f5, right])
        XCTAssertEqual(result, [newer])
    }

    func testRestoringALeftoverNeverResurrectsAnyEntryOfOurs() {
        let original = RemoteKeyMappingPolicy.snapshot(of: [f5, right])
        XCTAssertEqual(RemoteKeyMappingPolicy.restoring(original: original, current: [f5, right], owned: [f5, right]), [])
    }
}

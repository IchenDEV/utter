import XCTest
@testable import UtterRemoteMic

final class RemoteKeyMappingPolicyTests: XCTestCase {
    private let ours = RemoteKeyMappingPolicy.ours
    private let capsToEscape = KeyMappingEntry(source: 0x7_0000_0039, destination: 0x7_0000_0029)
    private let swapA = KeyMappingEntry(source: 0x7_0000_0004, destination: 0x7_0000_0005)
    private let foreignF5 = KeyMappingEntry(source: RemoteKeyMappingPolicy.voiceKeySource, destination: 0x7_0000_0041)

    func testOurEntryMapsF5ToNothing() {
        XCTAssertEqual(ours.source, 30_064_771_134)
        XCTAssertEqual(ours.destination, 0)
    }

    func testOnlyTheRemotesVendorAndProductMatch() {
        XCTAssertTrue(RemoteKeyMappingPolicy.matches(vendorID: 0x2717, productID: 0x32B8))
        XCTAssertFalse(RemoteKeyMappingPolicy.matches(vendorID: 0x2717, productID: 0x32B9))
        XCTAssertFalse(RemoteKeyMappingPolicy.matches(vendorID: 0x05AC, productID: 0x32B8))
        XCTAssertFalse(RemoteKeyMappingPolicy.matches(vendorID: nil, productID: 0x32B8))
        XCTAssertFalse(RemoteKeyMappingPolicy.matches(vendorID: 0x2717, productID: nil))
    }

    func testApplyingToEmptyListAddsOnlyOurEntry() {
        XCTAssertEqual(RemoteKeyMappingPolicy.applying(existing: []), [ours])
    }

    func testApplyingKeepsUnrelatedEntriesInPlaceAndAppendsOurs() {
        let result = RemoteKeyMappingPolicy.applying(existing: [capsToEscape, swapA])
        XCTAssertEqual(result, [capsToEscape, swapA, ours])
    }

    func testApplyingReplacesAnotherToolsF5EntryWithoutReorderingTheRest() {
        let result = RemoteKeyMappingPolicy.applying(existing: [capsToEscape, foreignF5, swapA])
        XCTAssertEqual(result, [capsToEscape, swapA, ours])
    }

    func testApplyingIsIdempotentAndDoesNotReorderAnExistingOurEntry() {
        let existing = [ours, capsToEscape]
        XCTAssertEqual(RemoteKeyMappingPolicy.applying(existing: existing), existing)
        let once = RemoteKeyMappingPolicy.applying(existing: [capsToEscape])
        XCTAssertEqual(RemoteKeyMappingPolicy.applying(existing: once), once)
    }

    func testApplyingCollapsesDuplicateF5EntriesToOne() {
        let result = RemoteKeyMappingPolicy.applying(existing: [ours, foreignF5, ours])
        XCTAssertEqual(result, [ours])
    }

    func testOurEntryIsDetectedExactlyNotByUsageAlone() {
        XCTAssertTrue(RemoteKeyMappingPolicy.containsOurs([capsToEscape, ours]))
        XCTAssertFalse(RemoteKeyMappingPolicy.containsOurs([foreignF5]))
        XCTAssertFalse(RemoteKeyMappingPolicy.containsOurs([]))
    }

    func testSnapshotExcludesOurOwnLeftoverEntryButKeepsForeignOnes() {
        XCTAssertEqual(RemoteKeyMappingPolicy.snapshot(of: [ours, capsToEscape]), [capsToEscape])
        XCTAssertEqual(RemoteKeyMappingPolicy.snapshot(of: [foreignF5, swapA]), [foreignF5, swapA])
    }

    func testRestoringRemovesOursAndReturnsTheForeignF5() {
        let original = [capsToEscape, foreignF5]
        let current = RemoteKeyMappingPolicy.applying(existing: original)
        XCTAssertEqual(RemoteKeyMappingPolicy.restoring(original: original, current: current), [capsToEscape, foreignF5])
    }

    func testRestoringWithNothingBeforeLeavesAnEmptyList() {
        let current = RemoteKeyMappingPolicy.applying(existing: [])
        XCTAssertEqual(RemoteKeyMappingPolicy.restoring(original: [], current: current), [])
    }

    func testRestoringKeepsEntriesAnotherToolAddedAfterUs() {
        let current = [capsToEscape, ours, swapA]
        XCTAssertEqual(RemoteKeyMappingPolicy.restoring(original: [capsToEscape], current: current), [capsToEscape, swapA])
    }

    func testRestoringDoesNotClobberANewerForeignF5() {
        let newer = KeyMappingEntry(source: RemoteKeyMappingPolicy.voiceKeySource, destination: 0x7_0000_0042)
        let result = RemoteKeyMappingPolicy.restoring(original: [foreignF5], current: [newer])
        XCTAssertEqual(result, [newer])
    }

    func testRestoringALeftoverOursSnapshotNeverResurrectsOurEntry() {
        let original = RemoteKeyMappingPolicy.snapshot(of: [ours])
        XCTAssertEqual(RemoteKeyMappingPolicy.restoring(original: original, current: [ours]), [])
    }
}

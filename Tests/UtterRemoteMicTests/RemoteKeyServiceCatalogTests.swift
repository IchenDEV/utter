import XCTest
@testable import UtterRemoteMic

final class RemoteKeyServiceCatalogTests: XCTestCase {
    private struct Fake {
        let id: UInt64?
        var vendorID: Int?
        var productID: Int?
    }

    private let remote = Fake(id: 1, vendorID: 0x2717, productID: 0x32B8)
    private let keyboard = Fake(id: 2, vendorID: 0x05AC, productID: 0x0342)
    private let sameVendorOtherProduct = Fake(id: 3, vendorID: 0x2717, productID: 0x0001)

    private func select(_ catalog: inout RemoteKeyServiceCatalog, _ items: [Fake], lookups: inout Int) -> [UInt64] {
        var count = 0
        let ids = catalog.select(from: items, id: { $0.id }, identity: { item in
            count += 1
            return (item.vendorID, item.productID)
        }).compactMap(\.id)
        lookups += count
        return ids
    }

    func testOnlyTheRemoteIsSelectedAmongOtherDevices() {
        var catalog = RemoteKeyServiceCatalog()
        var lookups = 0
        XCTAssertEqual(select(&catalog, [keyboard, remote, sameVendorOtherProduct], lookups: &lookups), [1])
    }

    func testAnIdentityIsReadOnceNotOnEveryPoll() {
        var catalog = RemoteKeyServiceCatalog()
        var lookups = 0
        let items = [keyboard, remote, sameVendorOtherProduct]
        for _ in 0..<5 { XCTAssertEqual(select(&catalog, items, lookups: &lookups), [1]) }
        XCTAssertEqual(lookups, 3)
    }

    func testAServiceWithoutAnIdIsSkipped() {
        var catalog = RemoteKeyServiceCatalog()
        var lookups = 0
        XCTAssertEqual(select(&catalog, [Fake(id: nil, vendorID: 0x2717, productID: 0x32B8)], lookups: &lookups), [])
        XCTAssertEqual(lookups, 0)
    }

    func testAnUnreadableIdentityIsRetriedNextPollAndThenSelected() {
        var catalog = RemoteKeyServiceCatalog()
        var lookups = 0
        let notYetPopulated = Fake(id: 1, vendorID: nil, productID: nil)
        XCTAssertEqual(select(&catalog, [notYetPopulated], lookups: &lookups), [])
        XCTAssertEqual(select(&catalog, [remote], lookups: &lookups), [1])
        XCTAssertEqual(lookups, 2)
    }

    func testAHalfReadIdentityIsNotRemembered() {
        var catalog = RemoteKeyServiceCatalog()
        var lookups = 0
        let half = Fake(id: 1, vendorID: 0x2717, productID: nil)
        XCTAssertEqual(select(&catalog, [half], lookups: &lookups), [])
        XCTAssertEqual(select(&catalog, [remote], lookups: &lookups), [1])
    }

    func testAReconnectedRemoteWithANewIdIsFoundAndTheOldVerdictIsForgotten() {
        var catalog = RemoteKeyServiceCatalog()
        var lookups = 0
        XCTAssertEqual(select(&catalog, [remote], lookups: &lookups), [1])
        XCTAssertEqual(select(&catalog, [], lookups: &lookups), [])
        let reconnected = Fake(id: 9, vendorID: 0x2717, productID: 0x32B8)
        XCTAssertEqual(select(&catalog, [reconnected], lookups: &lookups), [9])
        XCTAssertEqual(select(&catalog, [remote], lookups: &lookups), [1], "an id that vanished is judged again")
        XCTAssertEqual(lookups, 3)
    }
}

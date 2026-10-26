import Foundation

/// Picks the supported remote's services out of every HID service on the machine
/// (hundreds on a typical Mac) without re-reading their properties on each poll.
/// A service's vendor and product never change, so a definite answer is remembered
/// until the service disappears. An unreadable identity is never remembered, so a
/// service whose properties are not populated yet is looked at again next poll.
struct RemoteKeyServiceCatalog {
    private var verdicts: [UInt64: Bool] = [:]

    mutating func select<Item>(
        from items: [Item],
        id: (Item) -> UInt64?,
        identity: (Item) -> (vendorID: Int?, productID: Int?)
    ) -> [Item] {
        var present = Set<UInt64>()
        var selected: [Item] = []
        for item in items {
            guard let itemID = id(item) else { continue }
            present.insert(itemID)
            if let known = verdicts[itemID] {
                if known { selected.append(item) }
                continue
            }
            let (vendorID, productID) = identity(item)
            let matches = RemoteKeyMappingPolicy.matches(vendorID: vendorID, productID: productID)
            if vendorID != nil, productID != nil { verdicts[itemID] = matches }
            if matches { selected.append(item) }
        }
        verdicts = verdicts.filter { present.contains($0.key) }
        return selected
    }
}

import Foundation

/// One `UserKeyMapping` entry: HID usage `source` is reported as `destination`
/// (`0` means the key produces nothing).
package struct KeyMappingEntry: Equatable, Sendable {
    package let source: UInt64
    package let destination: UInt64

    package init(source: UInt64, destination: UInt64) {
        self.source = source
        self.destination = destination
    }
}

/// Pure rules for remapping the Xiaomi remote's voice key (HID keyboard F5).
/// The remote's other keys, other devices and other tools' mappings are never touched.
package enum RemoteKeyMappingPolicy {
    package static let vendorID = 0x2717
    package static let productID = 0x32B8
    /// Usage page 7 (keyboard), usage 0x3E (F5), as `UserKeyMapping` encodes it.
    package static let voiceKeySource: UInt64 = 0x7_0000_003E
    package static let ours = KeyMappingEntry(source: voiceKeySource, destination: 0)

    package static func matches(vendorID: Int?, productID: Int?) -> Bool {
        vendorID == Self.vendorID && productID == Self.productID
    }

    /// Exact match only: an F5 entry that maps somewhere else belongs to another tool.
    package static func containsOurs(_ entries: [KeyMappingEntry]) -> Bool {
        entries.contains(ours)
    }

    /// What was there before us, excluding our own entry, so a leftover mapping
    /// from a crashed run is treated as ours instead of being restored later.
    package static func snapshot(of existing: [KeyMappingEntry]) -> [KeyMappingEntry] {
        existing.filter { $0 != ours }
    }

    /// Replaces any F5 entry with ours and keeps every other entry in place.
    /// Returns the input unchanged when ours is already the only F5 entry.
    package static func applying(existing: [KeyMappingEntry]) -> [KeyMappingEntry] {
        let f5 = existing.filter { $0.source == voiceKeySource }
        if f5 == [ours] { return existing }
        return existing.filter { $0.source != voiceKeySource } + [ours]
    }

    /// Removes our entry and puts back the F5 entry another tool had before us,
    /// unless that tool has written a newer F5 entry since.
    package static func restoring(original: [KeyMappingEntry], current: [KeyMappingEntry]) -> [KeyMappingEntry] {
        var result = current.filter { $0 != ours }
        if !result.contains(where: { $0.source == voiceKeySource }) {
            result += original.filter { $0.source == voiceKeySource && $0 != ours }
        }
        return result
    }
}

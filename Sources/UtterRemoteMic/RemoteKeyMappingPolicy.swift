import Foundation
import UtterContracts

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

/// Pure rules for the Xiaomi remote's `UserKeyMapping`: the voice key (HID keyboard F5) is always
/// mapped to nothing, and so is every button the user has given an action of their own.
/// Other keys of the remote, other devices and other tools' mappings are never touched.
///
/// An entry is ours when it maps a key we may own (F5 or a `RemoteButton`) to nothing. That is
/// source-based, so a leftover from a crashed run is recognized and repaired even if the profile
/// has changed since. An entry that maps one of those keys somewhere else belongs to another tool.
package enum RemoteKeyMappingPolicy {
    package static let vendorID = 0x2717
    package static let productID = 0x32B8
    /// Usage page 7 (keyboard), usage 0x3E (F5), as `UserKeyMapping` encodes it.
    package static let voiceKeySource: UInt64 = 0x7_0000_003E
    package static let ours = KeyMappingEntry(source: voiceKeySource, destination: 0)

    private static let buttonSources = Set(RemoteButton.allCases.map(\.hidSource))
    private static let ownableSources = buttonSources.union([voiceKeySource])

    package static func matches(vendorID: Int?, productID: Int?) -> Bool {
        vendorID == Self.vendorID && productID == Self.productID
    }

    package static func isOurs(_ entry: KeyMappingEntry) -> Bool {
        entry.destination == 0 && ownableSources.contains(entry.source)
    }

    /// F5 first, then each requested button source once. A source that is not a known button is
    /// dropped, so a plan can never silence a key we have not measured.
    package static func desiredEntries(owning sources: [UInt64]) -> [KeyMappingEntry] {
        var seen: Set<UInt64> = [voiceKeySource]
        var entries = [ours]
        for source in sources where buttonSources.contains(source) && seen.insert(source).inserted {
            entries.append(KeyMappingEntry(source: source, destination: 0))
        }
        return entries
    }

    /// Exact match only: an F5 entry that maps somewhere else belongs to another tool.
    package static func containsOurs(_ entries: [KeyMappingEntry]) -> Bool {
        entries.contains(ours)
    }

    package static func containsAll(_ desired: [KeyMappingEntry], in entries: [KeyMappingEntry]) -> Bool {
        desired.allSatisfy(entries.contains)
    }

    /// Holds all of `desired` and no entry of ours beyond it, so a key we meant to release is not
    /// left silenced.
    package static func isSynced(_ entries: [KeyMappingEntry], with desired: [KeyMappingEntry]) -> Bool {
        containsAll(desired, in: entries) && entries.filter(isOurs).allSatisfy(desired.contains)
    }

    /// What was there before us, excluding every entry of ours, so a leftover mapping
    /// from a crashed run is treated as ours instead of being restored later.
    package static func snapshot(of existing: [KeyMappingEntry]) -> [KeyMappingEntry] {
        existing.filter { !isOurs($0) }
    }

    /// Replaces any entry for a source in `desired` with ours, drops our entries for keys no longer
    /// desired (putting back what `original` held for a key we `previous`ly owned when nothing else is
    /// there), and keeps every other entry in place. Returns the input unchanged when it already holds
    /// exactly `desired` as our entries and nothing foreign on those sources.
    package static func applying(
        existing: [KeyMappingEntry], desired: [KeyMappingEntry] = [ours],
        original: [KeyMappingEntry] = [], previous: [KeyMappingEntry] = []
    ) -> [KeyMappingEntry] {
        let desiredSources = Set(desired.map(\.source))
        let releasedSources = Set(previous.map(\.source)).subtracting(desiredSources)
        let kept = existing.filter { !isOurs($0) && !desiredSources.contains($0.source) }
        let present = Set(kept.map(\.source))
        let released = original.filter {
            !isOurs($0) && releasedSources.contains($0.source) && !present.contains($0.source)
        }
        let result = kept + released + desired
        return sameEntries(result, existing) ? existing : result
    }

    /// Removes every entry of ours and puts back the entry another tool had before us for each key
    /// in `owned`, unless that tool has written a newer entry for it since.
    package static func restoring(
        original: [KeyMappingEntry], current: [KeyMappingEntry], owned: [KeyMappingEntry] = [ours]
    ) -> [KeyMappingEntry] {
        let ownedSources = Set(owned.map(\.source))
        var result = current.filter { !isOurs($0) }
        let present = Set(result.map(\.source))
        result += original.filter { !isOurs($0) && ownedSources.contains($0.source) && !present.contains($0.source) }
        return result
    }

    private static func sameEntries(_ a: [KeyMappingEntry], _ b: [KeyMappingEntry]) -> Bool {
        a.count == b.count && a.allSatisfy(b.contains)
    }
}

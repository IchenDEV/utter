import Foundation

/// Converts between `KeyMappingEntry` and the property list the HID system stores
/// under `UserKeyMapping`.
enum RemoteKeyMappingCodec {
    static let sourceKey = "HIDKeyboardModifierMappingSrc"
    static let destinationKey = "HIDKeyboardModifierMappingDst"

    /// `nil` property means no mapping is set. Anything that is not a list of exactly
    /// source/destination number pairs returns `nil`, so the caller never rewrites a
    /// list that holds entries it cannot represent.
    static func decode(_ property: Any?) -> [KeyMappingEntry]? {
        guard let property else { return [] }
        guard let array = property as? [Any] else { return nil }
        var entries: [KeyMappingEntry] = []
        for element in array {
            guard let dictionary = element as? [String: Any], dictionary.count == 2,
                  let source = dictionary[sourceKey] as? NSNumber,
                  let destination = dictionary[destinationKey] as? NSNumber else { return nil }
            entries.append(KeyMappingEntry(source: source.uint64Value, destination: destination.uint64Value))
        }
        return entries
    }

    static func encode(_ entries: [KeyMappingEntry]) -> [[String: NSNumber]] {
        entries.map { [sourceKey: NSNumber(value: $0.source), destinationKey: NSNumber(value: $0.destination)] }
    }
}

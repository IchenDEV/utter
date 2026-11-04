import Foundation

/// Describes why a delivery could not be confirmed using counts and flags only. No part of the observed, expected or
/// original text can appear in the result.
enum DeliveryShapeDiagnostic {
    static func summary(observed: String?, expected: String, original: String?) -> String {
        guard let observed else {
            return "readable=false expectedUnits=\(expected.utf16.count) originalUnits=\(original?.utf16.count ?? -1)"
        }
        let a = Array(observed.utf16), b = Array(expected.utf16)
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        return [
            "readable=true",
            "observedUnits=\(a.count)", "expectedUnits=\(b.count)", "originalUnits=\(original?.utf16.count ?? -1)",
            "commonPrefix=\(prefix)", "commonSuffix=\(suffix)",
            "observedLineFeeds=\(a.filter { $0 == 0x0A }.count)", "expectedLineFeeds=\(b.filter { $0 == 0x0A }.count)",
            "observedNoBreakSpaces=\(a.filter { $0 == 0xA0 }.count)",
            "equalsOriginal=\(observed == original)",
        ].joined(separator: " ")
    }
}

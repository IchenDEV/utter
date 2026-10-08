import Foundation

package enum FactSupportVerdict {
    package static func accepts(_ text: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              Set(object.keys) == Set(["decision", "added_facts"]),
              object["decision"] as? String == "supported",
              let additions = object["added_facts"] as? [String] else { return false }
        return additions.isEmpty
    }
}

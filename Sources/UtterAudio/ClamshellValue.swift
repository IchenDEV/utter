import Foundation

package enum ClamshellValue {
    package static func isClosed(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let flag = value as? Bool { return flag }
        return false
    }
}

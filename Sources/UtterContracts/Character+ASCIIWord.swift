import Foundation

extension Character {
    package var isASCIIWord: Bool {
        guard unicodeScalars.count == 1,
              let value = unicodeScalars.first?.value else {
            return false
        }
        return (48...57).contains(value)
            || (65...90).contains(value)
            || value == 95
            || (97...122).contains(value)
    }
}

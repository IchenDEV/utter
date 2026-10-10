import Foundation

package enum NoSpaceScript {
    package static func contains(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3005,
             0x303B,
             0x3040...0x309F,
             0x30A0...0x30FF,
             0x31F0...0x31FF,
             0x3400...0x9FFF,
             0xF900...0xFAFF,
             0xFF66...0xFF9F,
             0x20000...0x2EBEF:
            return true
        default:
            return false
        }
    }
}

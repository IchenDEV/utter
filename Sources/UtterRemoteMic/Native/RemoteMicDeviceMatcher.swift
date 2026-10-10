import CoreBluetooth
import Foundation

/// Recognises the Xiaomi Bluetooth Remote 2 / 2 Pro among everything CoreBluetooth
/// can see, and knows the firmware quirks that depend on the reported model.
///
/// Matching is deliberately exact (not "contains Xiaomi") so another vendor's
/// Android TV remote that also speaks ATVV is never adopted by name alone.
package enum RemoteMicDeviceMatcher {
    package static let hidServiceUUID = CBUUID(string: "1812")
    package static let deviceInformationServiceUUID = CBUUID(string: "180A")
    package static let modelNumberUUID = CBUUID(string: "2A24")

    private static let approvedNames: Set<String> = [
        "mi rc",
        "xiaomi bluetooth remote 2",
        "xiaomi bluetooth remote 2 pro",
        "小米蓝牙语音遥控器",
        "小米蓝牙遥控器2",
        "小米蓝牙遥控器2 pro",
        "arn9",
    ]

    package static func matches(name: String?) -> Bool {
        guard let name else { return false }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return approvedNames.contains(normalized)
    }

    /// A discovered peripheral is a candidate when it advertises the ATVV
    /// service, or when either of its names is an approved remote name.
    package static func isCandidate(
        peripheralName: String?,
        advertisedName: String?,
        advertisedServiceUUIDs: [CBUUID]?
    ) -> Bool {
        if advertisedServiceUUIDs?.contains(CBUUID(string: RemoteMicProtocol.serviceUUID)) == true {
            return true
        }
        return matches(name: peripheralName) || matches(name: advertisedName)
    }

    /// The Remote 2 / 2 Pro (model `ARN9`) encodes each ADPCM byte
    /// low-nibble-first; the default high-first order turns its speech to noise.
    package static func usesLowNibbleFirst(modelNumber: String?) -> Bool {
        guard let modelNumber else { return false }
        return modelNumber.uppercased().contains("ARN9")
    }
}

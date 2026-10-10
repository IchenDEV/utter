import Foundation
import UtterContracts
import UtterRuntime

@MainActor
package protocol AudioDeviceService: AnyObject {
    func availableMicrophones() -> [MicrophoneDescription]
}

package struct MicrophoneDescription: Equatable, Sendable {
    package let id: String
    package let name: String
    package init(id: String, name: String) { self.id = id; self.name = name }
}

extension AudioServices {
    package static let devices = ServiceKey<any AudioDeviceService>("audio.devices")
}

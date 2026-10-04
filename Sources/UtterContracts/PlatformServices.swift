import Foundation
import UtterRuntime

@MainActor
package protocol HotkeyControlService: AnyObject {
    /// Read synchronously in callbacks; the identity stays stable through promotion and stop.
    var captureID: UUID? { get }
    func setEnabled(_ enabled: Bool)
    func setCallbacks(start: ((HotkeyAction) -> Void)?, stop: ((HotkeyAction) -> Void)?,
                      promote: ((HotkeyPromotion) -> Bool)?, cancel: (() -> Void)?)
}

@MainActor
package protocol SoundService: AnyObject {
    func playStart()
    func playStop()
}

@MainActor
package protocol LoginItemService: AnyObject {
    var isEnabled: Bool { get }
    var requiresApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
package protocol CorrectionControlService: AnyObject {
    func start(seed: CorrectionCaptureSeed, recordID: UUID)
    func finishCurrentSession()
    func cancelCurrentSession()
}

package struct TargetCaptureRequest {
    package let screenContext: String
    package let outputMode: OutputMode
    package let inputLanguage: InputLanguage
    package let source: InputSource
    package init(screenContext: String = "", outputMode: OutputMode, inputLanguage: InputLanguage, source: InputSource) {
        self.screenContext = screenContext
        self.outputMode = outputMode
        self.inputLanguage = inputLanguage
        self.source = source
    }
}

@MainActor
package protocol TargetCaptureService: AnyObject {
    func capture(_ request: TargetCaptureRequest) throws -> any OutputTargetLease
}

extension MacServices {
    package static let hotkeys = ServiceKey<any HotkeyControlService>("mac.hotkeys")
    package static let sounds = ServiceKey<any SoundService>("mac.sounds")
    package static let loginItem = ServiceKey<any LoginItemService>("mac.login-item")
    package static let correction = ServiceKey<any CorrectionControlService>("mac.correction")
    package static let target = ServiceKey<any TargetCaptureService>("mac.target")
}

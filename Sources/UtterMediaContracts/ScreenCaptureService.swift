import UtterContracts
import UtterRuntime

@MainActor
package protocol ScreenCaptureService: AnyObject {
    func capture(mode: ScreenContextMode) async throws -> ScreenContextSnapshot
    func checkPermission() async throws -> Bool
    func requestPermission()
}

extension MacServices {
    package static let screen = ServiceKey<any ScreenCaptureService>("mac.screen")
}

import Foundation
import Combine
import UtterContracts
import UtterMediaContracts

@MainActor
package final class PlatformProjection: ObservableObject {
    private let remote: (any RemoteMicControlService)?
    private let login: (any LoginItemService)?
    private let devices: (any AudioDeviceService)?
    private let screen: (any ScreenCaptureService)?
    package let log: Log
    private var observation: UUID?
    private var diagnosticsObservation: UUID?
    @Published package private(set) var remoteDiagnostics = RemoteMicDiagnostics()
    @Published package private(set) var remoteState: RemoteMicBridgeState = .idle
    package init(remote: (any RemoteMicControlService)?, login: (any LoginItemService)?,
                 devices: (any AudioDeviceService)?, screen: (any ScreenCaptureService)?, diagnostics: any DiagnosticsService) {
        self.remote = remote; self.login = login; self.devices = devices; self.screen = screen
        log = Log(service: diagnostics)
        observation = remote?.observe { [weak self] in self?.remoteState = $0 }
        diagnosticsObservation = remote?.observeDiagnostics { [weak self] in self?.remoteDiagnostics = $0 }
    }
    package var hasScreenProvider: Bool { screen != nil }
    package func reconnectRemoteMic() { remote?.reconnect() }
    package var hasRemoteProvider: Bool { remote != nil }
    package var loginEnabled: Bool { login?.isEnabled ?? false }
    package var loginRequiresApproval: Bool { login?.requiresApproval ?? false }
    package func setLoginEnabled(_ enabled: Bool) throws {
        guard let login else { throw GenerationServiceError.unsupportedOperation }
        try login.setEnabled(enabled)
    }
    package func availableMicrophones() -> [MicrophoneDescription] { devices?.availableMicrophones() ?? [] }
    package func checkScreenPermission() async -> Bool { (try? await screen?.checkPermission()) ?? false }
    package func requestScreenPermission() { screen?.requestPermission() }
    package func dispose() {
        if let observation { remote?.removeObserver(observation) }
        observation = nil
        if let diagnosticsObservation { remote?.removeObserver(diagnosticsObservation) }
        diagnosticsObservation = nil
    }
}

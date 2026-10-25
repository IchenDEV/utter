import Foundation
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts

@MainActor
private final class RecordingRemote: RemoteMicControlService {
    var state: RemoteMicBridgeState = .idle
    var diagnostics = RemoteMicDiagnostics(buttonMapping: .waitingForRemote)
    private(set) var permissionRequests = 0
    private(set) var refreshes = 0
    func reconnect() {}
    func observeDiagnostics(_ callback: @escaping (RemoteMicDiagnostics) -> Void) -> UUID {
        callback(diagnostics)
        return UUID()
    }
    func setEnabled(_ enabled: Bool) {}
    func setVoiceCallbacks(pressed: ((UInt64) -> Void)?, released: (() -> Void)?, stopped: (() -> Void)?) {}
    func observe(_ callback: @escaping (RemoteMicBridgeState) -> Void) -> UUID { UUID() }
    func removeObserver(_ id: UUID) {}
    func requestButtonMappingPermission() { permissionRequests += 1 }
    func refreshButtonMapping() { refreshes += 1 }
}

@MainActor
final class PlatformProjectionButtonMappingTests: XCTestCase {
    func testTheProjectionForwardsPermissionAndRefreshAndExposesTheState() {
        let remote = RecordingRemote()
        let platform = PlatformProjection(remote: remote, login: nil, devices: nil, screen: nil,
                                          diagnostics: RemotePluginDiagnostics())
        XCTAssertEqual(platform.remoteDiagnostics.buttonMapping, .waitingForRemote)
        platform.requestButtonMappingPermission()
        platform.refreshButtonMapping()
        platform.refreshButtonMapping()
        XCTAssertEqual(remote.permissionRequests, 1)
        XCTAssertEqual(remote.refreshes, 2)
    }

    func testWithoutARemoteProviderBothCallsAreHarmless() {
        let platform = PlatformProjection(remote: nil, login: nil, devices: nil, screen: nil,
                                          diagnostics: RemotePluginDiagnostics())
        platform.requestButtonMappingPermission()
        platform.refreshButtonMapping()
        XCTAssertEqual(platform.remoteDiagnostics.buttonMapping, .off)
    }
}

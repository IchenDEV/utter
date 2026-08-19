import ServiceManagement
import XCTest
@testable import OpenType

final class LaunchAtLoginServiceTests: XCTestCase {
    func testStatusMappingUsesEnabledAsTheOnlyActiveState() {
        XCTAssertTrue(LaunchAtLoginService.isEnabled(status: .enabled))
        XCTAssertFalse(LaunchAtLoginService.isEnabled(status: .notRegistered))
        XCTAssertFalse(LaunchAtLoginService.isEnabled(status: .requiresApproval))
        XCTAssertTrue(LaunchAtLoginService.requiresApproval(status: .requiresApproval))
    }

    func testEnablingRegistersOnlyWhenNeeded() throws {
        let disabledService = LoginItemServiceStub(status: .notRegistered)
        try LaunchAtLoginService.setEnabled(true, service: disabledService)
        XCTAssertEqual(disabledService.registerCallCount, 1)

        let enabledService = LoginItemServiceStub(status: .enabled)
        try LaunchAtLoginService.setEnabled(true, service: enabledService)
        XCTAssertEqual(enabledService.registerCallCount, 0)

        let approvalService = LoginItemServiceStub(status: .requiresApproval)
        try LaunchAtLoginService.setEnabled(true, service: approvalService)
        XCTAssertEqual(approvalService.registerCallCount, 0)
    }

    func testDisablingUnregistersOnlyWhenNeeded() throws {
        let enabledService = LoginItemServiceStub(status: .enabled)
        try LaunchAtLoginService.setEnabled(false, service: enabledService)
        XCTAssertEqual(enabledService.unregisterCallCount, 1)

        let disabledService = LoginItemServiceStub(status: .notRegistered)
        try LaunchAtLoginService.setEnabled(false, service: disabledService)
        XCTAssertEqual(disabledService.unregisterCallCount, 0)
    }
}

private final class LoginItemServiceStub: LoginItemServicing {
    var status: SMAppService.Status
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}

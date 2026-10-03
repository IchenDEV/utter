import ServiceManagement

package protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServicing {}

package enum LaunchAtLoginService {
    package static var isEnabled: Bool {
        isEnabled(status: SMAppService.mainApp.status)
    }

    package static var requiresApproval: Bool {
        requiresApproval(status: SMAppService.mainApp.status)
    }

    package static func setEnabled(_ enabled: Bool) throws {
        try setEnabled(enabled, service: SMAppService.mainApp)
    }

    package static func isEnabled(status: SMAppService.Status) -> Bool {
        status == .enabled
    }

    package static func requiresApproval(status: SMAppService.Status) -> Bool {
        status == .requiresApproval
    }

    package static func setEnabled(_ enabled: Bool, service: LoginItemServicing) throws {
        if enabled {
            guard service.status != .enabled, service.status != .requiresApproval else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
}

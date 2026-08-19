import ServiceManagement

protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServicing {}

enum LaunchAtLoginService {
    static var isEnabled: Bool {
        isEnabled(status: SMAppService.mainApp.status)
    }

    static var requiresApproval: Bool {
        requiresApproval(status: SMAppService.mainApp.status)
    }

    static func setEnabled(_ enabled: Bool) throws {
        try setEnabled(enabled, service: SMAppService.mainApp)
    }

    static func isEnabled(status: SMAppService.Status) -> Bool {
        status == .enabled
    }

    static func requiresApproval(status: SMAppService.Status) -> Bool {
        status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool, service: LoginItemServicing) throws {
        if enabled {
            guard service.status != .enabled, service.status != .requiresApproval else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
}

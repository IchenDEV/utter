import Foundation

package struct Log: Sendable {
    private let service: any DiagnosticsService

    package init(service: any DiagnosticsService) { self.service = service }
    package func info(_ message: String) { service.info(message) }
    package func sensitive(_ message: String) { service.sensitive(message) }
    package func error(_ message: String) { service.error(message) }
}

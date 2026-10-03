import UtterContracts
import UtterData

// Construction bridge retained while native consumers move to injected services.
enum Log {
    static let service: any DiagnosticsService = SystemDiagnostics()
    static func info(_ message: String) { service.info(message) }
    static func sensitive(_ message: String) { service.sensitive(message) }
    static func error(_ message: String) { service.error(message) }
}

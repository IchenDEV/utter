import os
import UtterContracts

package struct SystemDiagnostics: DiagnosticsService {
    package init() {}
    private let logger = Logger(subsystem: ProductBrand.bundleIdentifier, category: "app")

    package init() {}
    package func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    package func sensitive(_ message: String) { logger.debug("\(message, privacy: .private)") }
    package func error(_ message: String) { logger.error("\(message, privacy: .public)") }
}

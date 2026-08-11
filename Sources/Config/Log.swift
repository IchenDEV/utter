import os

/// Centralized logging with privacy-aware output.
/// In release builds, `.private` data is automatically redacted by os_log.
enum Log {
    private static let logger = Logger(subsystem: ProductBrand.bundleIdentifier, category: "app")

    /// Operational messages (model loading, phase transitions, etc.)
    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    /// Messages that may contain user-generated content (transcription, processed text).
    /// Automatically redacted in release builds.
    static func sensitive(_ message: String) {
        logger.debug("\(message, privacy: .private)")
    }

    /// Error conditions.
    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

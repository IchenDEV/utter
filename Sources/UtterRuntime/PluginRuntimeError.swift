import Foundation

package enum PluginRuntimeError: Error, Equatable {
    case invalidPluginID(String)
    case duplicatePlugin(String)
    case unknownPlugin(String)
    case duplicateService(String)
    case duplicateDependency(plugin: String, service: String)
    case missingService(plugin: String, service: String)
    case serviceTypeMismatch(String)
    case dependencyCycle([String])
    case undeclaredLookup(plugin: String, service: String)
    case undeclaredRegistration(plugin: String, service: String)
    case missingRegistration(plugin: String, service: String)
    case invalidConfiguration(String)
    case scopeClosed(String)
    case notReady
    case transitionInProgress
    case cleanupPending
}

package struct PluginDisposalFailure: Error {
    package let pluginID: String
    package let cause: Error
}

package struct PluginActivationFailure: Error {
    package let pluginID: String
    package let cause: Error
    package let cleanupFailures: [PluginDisposalFailure]
}

package struct PluginShutdownFailure: Error {
    package let failures: [PluginDisposalFailure]
}

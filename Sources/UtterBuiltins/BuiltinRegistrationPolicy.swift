import UtterRuntime

@MainActor
package enum BuiltinRegistrationPolicy {
    package static func replacing(_ registrations: [PluginRegistration],
                                  with replacements: [PluginRegistration]) throws -> [PluginRegistration] {
        let original = Set(registrations.map { $0.descriptor.id })
        var byID: [String: PluginRegistration] = [:]
        for replacement in replacements {
            let id = replacement.descriptor.id
            guard original.contains(id) else { throw PluginRuntimeError.unknownPlugin(id) }
            guard byID[id] == nil else { throw PluginRuntimeError.duplicatePlugin(id) }
            byID[id] = replacement
        }
        return registrations.map { byID[$0.descriptor.id] ?? $0 }
    }
}

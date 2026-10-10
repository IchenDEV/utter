import Foundation
import UtterContracts
import UtterRuntime

@MainActor
package struct CompositionResolver {
    private let catalog: PluginCatalog
    private let bundles: [String: CompositionLayer]
    private let providers: [String: [String: ProviderBindingDescriptor]]

    package init(catalog: PluginCatalog, bundles: [CompositionLayer], providers: [ProviderBindingDescriptor]) throws {
        self.catalog = catalog
        var indexedBundles: [String: CompositionLayer] = [:]
        for bundle in bundles {
            guard indexedBundles[bundle.id] == nil else { throw CompositionError.duplicateBundle(bundle.id) }
            try Self.validateRows(bundle)
            indexedBundles[bundle.id] = bundle
        }
        self.bundles = indexedBundles
        var indexedProviders: [String: [String: ProviderBindingDescriptor]] = [:]
        for provider in providers {
            guard indexedProviders[provider.capability]?[provider.providerID] == nil else {
                throw CompositionError.duplicateProvider(capability: provider.capability, provider: provider.providerID)
            }
            guard catalog.descriptors.contains(where: { $0.id == provider.pluginID }) else {
                throw PluginRuntimeError.unknownPlugin(provider.pluginID)
            }
            indexedProviders[provider.capability, default: [:]][provider.providerID] = provider
        }
        self.providers = indexedProviders
    }

    package func resolve(_ document: CompositionDocument, legacy: CompositionLayer = CompositionLayer("legacy")) throws -> EffectiveComposition {
        guard document.schemaVersion == CompositionDocument.currentVersion else {
            throw CompositionError.unsupportedVersion(document.schemaVersion)
        }
        var seenBundles: Set<String> = []
        var layers: [CompositionLayer] = []
        for id in document.bundles {
            guard seenBundles.insert(id).inserted else { throw CompositionError.duplicateBundle(id) }
            guard let bundle = bundles[id] else { throw CompositionError.unknownBundle(id) }
            layers.append(bundle)
        }
        layers.append(legacy)
        layers.append(CompositionLayer("user", plugins: document.plugins, bindings: document.bindings))
        var rows: [String: PluginConfigurationRow] = [:]
        var bindings: [String: String] = [:]
        for layer in layers {
            try Self.validateRows(layer)
            for row in layer.plugins {
                try catalog.validateConfiguration(PluginSelection(row.id, configuration: row.configuration))
                rows[row.id] = row
            }
            for (capability, providerID) in layer.bindings {
                guard let choices = providers[capability] else { throw CompositionError.unknownCapability(capability) }
                guard choices[providerID] != nil else {
                    throw CompositionError.unknownProvider(capability: capability, provider: providerID)
                }
                bindings[capability] = providerID
            }
        }
        let effective = EffectiveComposition(plugins: rows.values.sorted { $0.id < $1.id }, bindings: bindings)
        for capability in bindings.keys.sorted() {
            guard let providerID = bindings[capability], let pluginID = owner(capability, providerID: providerID) else { continue }
            guard effective.mountedPluginIDs.contains(pluginID) else {
                throw CompositionError.disabledProvider(capability: capability, provider: providerID, plugin: pluginID)
            }
        }
        _ = try catalog.validate(effective.selections)
        return effective
    }

    func owner(_ capability: String, providerID: String) -> String? {
        providers[capability]?[providerID]?.pluginID
    }

    private static func validateRows(_ layer: CompositionLayer) throws {
        var seen: Set<String> = []
        for row in layer.plugins {
            guard seen.insert(row.id).inserted else { throw CompositionError.duplicateRow(layer: layer.id, plugin: row.id) }
        }
    }
}

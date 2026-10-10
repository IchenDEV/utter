import Foundation
import UtterRuntime

package struct CompositionDocument: Codable, Equatable {
    package static let currentVersion = 1
    package let schemaVersion: Int
    package var bundles: [String]
    package var plugins: [PluginConfigurationRow]
    package var bindings: [String: String]

    package init(
        schemaVersion: Int = currentVersion,
        bundles: [String],
        plugins: [PluginConfigurationRow] = [],
        bindings: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.bundles = bundles
        self.plugins = plugins
        self.bindings = bindings
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, bundles, plugins, bindings
    }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownFields(CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported composition version: \(schemaVersion)")
        }
        bundles = try values.decode([String].self, forKey: .bundles)
        plugins = try values.decodeIfPresent([PluginConfigurationRow].self, forKey: .plugins) ?? []
        bindings = try values.decodeIfPresent([String: String].self, forKey: .bindings) ?? [:]
    }
}

package struct PluginConfigurationRow: Codable, Equatable {
    package let id: String
    package var enabled: Bool
    package var configuration: [String: ConfigurationValue]

    package init(_ id: String, enabled: Bool = true, configuration: [String: ConfigurationValue] = [:]) {
        self.id = id
        self.enabled = enabled
        self.configuration = configuration
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, enabled, configuration }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownFields(CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        configuration = try values.decodeIfPresent([String: ConfigurationValue].self, forKey: .configuration) ?? [:]
    }
}

private struct FieldKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private extension Decoder {
    func rejectUnknownFields<Keys: CodingKey & CaseIterable>(_ keys: Keys.Type) throws {
        let values = try container(keyedBy: FieldKey.self)
        let known = Set(Keys.allCases.map(\.stringValue))
        let unknown = values.allKeys.map(\.stringValue).filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Unknown fields: \(unknown.joined(separator: ", "))"))
        }
    }
}

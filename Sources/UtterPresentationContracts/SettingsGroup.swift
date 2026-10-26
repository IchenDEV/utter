/// A Settings tab assembled from several plugin-contributed pages.
package struct SettingsGroup: Equatable {
    package let id: String
    package let label: String
    package let symbol: String
    package let order: Int

    package static let integrations = SettingsGroup(
        id: "presentation.group.integrations", label: "settings.integrations",
        symbol: "point.3.connected.trianglepath.dotted", order: 40)

    package static let all: [SettingsGroup] = [.integrations]
}

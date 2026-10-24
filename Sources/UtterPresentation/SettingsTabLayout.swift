import UtterPresentationContracts

@MainActor
struct SettingsTab {
    let id: String
    let label: String
    let symbol: String
    let order: Int
    let members: [PresentationContribution]
    let isGroup: Bool
}

/// Turns plugin-contributed Settings pages into window tabs. Pages that name a
/// known group share one tab; a group with no registered member has no tab.
@MainActor
enum SettingsTabLayout {
    static func tabs(from contributions: [PresentationContribution]) -> [SettingsTab] {
        let known = Dictionary(uniqueKeysWithValues: SettingsGroup.all.map { ($0.id, $0) })
        var pages: [SettingsTab] = []
        var grouped: [String: [PresentationContribution]] = [:]
        for item in contributions where item.role == .settings {
            if let id = item.group, known[id] != nil {
                grouped[id, default: []].append(item)
            } else {
                pages.append(SettingsTab(id: item.id, label: item.label, symbol: item.symbol,
                                         order: item.order, members: [item], isGroup: false))
            }
        }
        let groups = grouped.compactMap { id, members in
            known[id].map {
                SettingsTab(id: $0.id, label: $0.label, symbol: $0.symbol, order: $0.order,
                            members: members.sorted { ($0.order, $0.id) < ($1.order, $1.id) }, isGroup: true)
            }
        }
        return (pages + groups).sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    /// The tab that shows `selection`, which may be a tab id or the id of a member page.
    static func tabID(for selection: String, in tabs: [SettingsTab]) -> String? {
        tabs.first { $0.id == selection || $0.members.contains { $0.id == selection } }?.id
    }

    /// Like `tabID(for:in:)`, falling back to the first tab for an unknown or removed id.
    static func selection(_ requested: String, in tabs: [SettingsTab]) -> String? {
        tabID(for: requested, in: tabs) ?? tabs.first?.id
    }
}

import XCTest
import SwiftUI
import UtterContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
final class SettingsTabLayoutTests: XCTestCase {
    private let group = SettingsGroup.integrations.id

    private func page(_ id: String, order: Int, group: String? = nil) -> PresentationContribution {
        PresentationContribution(id: id, role: .settings, order: order, label: "label." + id, symbol: "gear",
            group: group) { _ in AnyView(EmptyView()) }
    }

    private var integrations: PresentationContribution { page("presentation.integrations", order: 0, group: group) }
    private var remote: PresentationContribution { page("presentation.remote", order: 5, group: group) }
    private var configuration: PresentationContribution { page("presentation.configuration", order: 10, group: group) }

    private var shipped: [PresentationContribution] {
        [page("presentation.about", order: 50), configuration, page("presentation.models", order: 20),
         remote, integrations, page("presentation.history", order: 0), page("presentation.style", order: 30),
         page("presentation.general", order: 10)]
    }

    private func members(_ tabs: [SettingsTab]) throws -> [String] {
        try XCTUnwrap(tabs.first { $0.id == group }).members.map(\.id)
    }

    func testDefaultCompositionHasSixTabsInOrder() {
        XCTAssertEqual(SettingsTabLayout.tabs(from: shipped).map(\.id), [
            "presentation.history", "presentation.general", "presentation.models", "presentation.style",
            group, "presentation.about"])
    }

    func testGroupTabUsesTheGroupLabelAndSymbolAndOrdersMembersByTheirOwnOrder() throws {
        let tabs = SettingsTabLayout.tabs(from: shipped)
        let tab = try XCTUnwrap(tabs.first { $0.id == group })
        XCTAssertEqual(tab.label, SettingsGroup.integrations.label)
        XCTAssertEqual(tab.symbol, SettingsGroup.integrations.symbol)
        XCTAssertTrue(tab.isGroup)
        XCTAssertEqual(try members(tabs), ["presentation.integrations", "presentation.remote", "presentation.configuration"])
    }

    func testPlainTabKeepsItsOwnLabelAndSymbol() throws {
        let tab = try XCTUnwrap(SettingsTabLayout.tabs(from: shipped).first { $0.id == "presentation.models" })
        XCTAssertEqual(tab.label, "label.presentation.models")
        XCTAssertEqual(tab.symbol, "gear")
        XCTAssertFalse(tab.isGroup)
        XCTAssertEqual(tab.members.map(\.id), ["presentation.models"])
    }

    func testRecoveryLayoutKeepsOnlyTheConfigurationMember() throws {
        let tabs = SettingsTabLayout.tabs(from: [configuration])
        XCTAssertEqual(tabs.map(\.id), [group])
        XCTAssertEqual(try members(tabs), ["presentation.configuration"])
    }

    func testAnySubsetOfMembersStaysInOneTabInOrder() throws {
        let all = [integrations, remote, configuration]
        for mask in 1..<8 {
            let chosen = all.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            let tabs = SettingsTabLayout.tabs(from: [page("presentation.general", order: 10)] + chosen.reversed())
            XCTAssertEqual(tabs.map(\.id), ["presentation.general", group], "subset \(mask)")
            XCTAssertEqual(try members(tabs), chosen.map(\.id), "subset \(mask)")
        }
    }

    func testNoMembersMeansNoGroupTab() {
        let tabs = SettingsTabLayout.tabs(from: [page("presentation.general", order: 10), page("presentation.about", order: 50)])
        XCTAssertEqual(tabs.map(\.id), ["presentation.general", "presentation.about"])
        XCTAssertTrue(SettingsTabLayout.tabs(from: []).isEmpty)
    }

    func testUnknownGroupFallsBackToIndividualTabsSoNothingIsHidden() {
        let unknown = "presentation.group.unknown"
        let tabs = SettingsTabLayout.tabs(from: [page("presentation.a", order: 5, group: unknown),
                                                 page("presentation.b", order: 6, group: unknown)])
        XCTAssertEqual(tabs.map(\.id), ["presentation.a", "presentation.b"])
        XCTAssertEqual(tabs.map(\.label), ["label.presentation.a", "label.presentation.b"])
    }

    func testMemberIDsMapToTheirGroupTab() {
        let tabs = SettingsTabLayout.tabs(from: shipped)
        for id in ["presentation.configuration", "presentation.remote", "presentation.integrations", group] {
            XCTAssertEqual(SettingsTabLayout.tabID(for: id, in: tabs), group, id)
        }
        XCTAssertEqual(SettingsTabLayout.tabID(for: "presentation.models", in: tabs), "presentation.models")
    }

    func testUnknownOrRemovedSelectionMapsToNil() {
        let tabs = SettingsTabLayout.tabs(from: shipped)
        XCTAssertNil(SettingsTabLayout.tabID(for: "presentation.removed-page", in: tabs))
        XCTAssertNil(SettingsTabLayout.tabID(for: "", in: tabs))
        let recovery = SettingsTabLayout.tabs(from: [configuration])
        XCTAssertNil(SettingsTabLayout.tabID(for: "presentation.models", in: recovery))
    }

    func testSelectionFallsBackToTheFirstTab() {
        let tabs = SettingsTabLayout.tabs(from: shipped)
        XCTAssertEqual(SettingsTabLayout.selection("presentation.removed-page", in: tabs), "presentation.history")
        XCTAssertEqual(SettingsTabLayout.selection("presentation.remote", in: tabs), group)
        XCTAssertEqual(SettingsTabLayout.selection("presentation.configuration", in: tabs), group)
        XCTAssertNil(SettingsTabLayout.selection("presentation.models", in: []))
    }

    func testGroupLabelIsLocalizedInBothLanguages() {
        let key = SettingsGroup.integrations.label
        XCTAssertEqual(Loc.string(key, language: .english), "Integrations")
        XCTAssertEqual(Loc.string(key, language: .chinese), "集成")
    }

    func testRecoveryAlertNamesTheIntegrationsTabInBothLanguages() {
        for language in [UILanguage.english, .chinese] {
            let tab = Loc.string(SettingsGroup.integrations.label, language: language)
            let alert = Loc.string("plugins.recovery", language: language)
            XCTAssertTrue(alert.contains(tab), "\(language): \(alert)")
        }
    }
}

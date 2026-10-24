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

    private var integrationsMember: PresentationContribution {
        page("presentation.integrations", order: 0, group: group)
    }

    private var configurationMember: PresentationContribution {
        page("presentation.configuration", order: 10, group: group)
    }

    private var shipped: [PresentationContribution] {
        [page("presentation.about", order: 50), configurationMember, page("presentation.models", order: 20),
         integrationsMember, page("presentation.history", order: 0), page("presentation.style", order: 30),
         page("presentation.general", order: 10)]
    }

    func testDefaultCompositionHasSixTabsInOrder() {
        XCTAssertEqual(SettingsTabLayout.tabs(from: shipped).map(\.id), [
            "presentation.history", "presentation.general", "presentation.models", "presentation.style",
            group, "presentation.about"])
    }

    func testGroupTabUsesTheGroupLabelAndSymbolAndOrdersMembersByTheirOwnOrder() throws {
        let tab = try XCTUnwrap(SettingsTabLayout.tabs(from: shipped).first { $0.id == group })
        XCTAssertEqual(tab.label, SettingsGroup.integrations.label)
        XCTAssertEqual(tab.symbol, SettingsGroup.integrations.symbol)
        XCTAssertEqual(tab.members.map(\.id), ["presentation.integrations", "presentation.configuration"])
    }

    func testPlainTabKeepsItsOwnLabelAndSymbol() throws {
        let tab = try XCTUnwrap(SettingsTabLayout.tabs(from: shipped).first { $0.id == "presentation.models" })
        XCTAssertEqual(tab.label, "label.presentation.models")
        XCTAssertEqual(tab.symbol, "gear")
        XCTAssertEqual(tab.members.map(\.id), ["presentation.models"])
    }

    func testRecoveryLayoutKeepsOnlyTheConfigurationMember() throws {
        let tabs = SettingsTabLayout.tabs(from: [configurationMember])
        XCTAssertEqual(tabs.map(\.id), [group])
        XCTAssertEqual(try XCTUnwrap(tabs.first).members.map(\.id), ["presentation.configuration"])
    }

    func testTabKeepsOnlyTheIntegrationsMemberWhenConfigurationIsDisabled() throws {
        let tabs = SettingsTabLayout.tabs(from: [page("presentation.general", order: 10), integrationsMember])
        XCTAssertEqual(tabs.map(\.id), ["presentation.general", group])
        XCTAssertEqual(try XCTUnwrap(tabs.last).members.map(\.id), ["presentation.integrations"])
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
        XCTAssertEqual(SettingsTabLayout.tabID(for: "presentation.configuration", in: tabs), group)
        XCTAssertEqual(SettingsTabLayout.tabID(for: "presentation.integrations", in: tabs), group)
        XCTAssertEqual(SettingsTabLayout.tabID(for: group, in: tabs), group)
        XCTAssertEqual(SettingsTabLayout.tabID(for: "presentation.models", in: tabs), "presentation.models")
    }

    func testUnknownOrRemovedSelectionMapsToNil() {
        let tabs = SettingsTabLayout.tabs(from: shipped)
        XCTAssertNil(SettingsTabLayout.tabID(for: "presentation.remote", in: tabs))
        XCTAssertNil(SettingsTabLayout.tabID(for: "", in: tabs))
        let recovery = SettingsTabLayout.tabs(from: [configurationMember])
        XCTAssertNil(SettingsTabLayout.tabID(for: "presentation.models", in: recovery))
    }

    func testSelectionFallsBackToTheFirstTab() {
        let tabs = SettingsTabLayout.tabs(from: shipped)
        XCTAssertEqual(SettingsTabLayout.selection("presentation.remote", in: tabs), "presentation.history")
        XCTAssertEqual(SettingsTabLayout.selection("presentation.configuration", in: tabs), group)
        XCTAssertNil(SettingsTabLayout.selection("presentation.models", in: []))
    }

    func testGroupLabelIsLocalizedInBothLanguages() {
        let key = SettingsGroup.integrations.label
        XCTAssertEqual(Loc.string(key, language: .english), "Integrations")
        XCTAssertEqual(Loc.string(key, language: .chinese), "集成")
    }
}

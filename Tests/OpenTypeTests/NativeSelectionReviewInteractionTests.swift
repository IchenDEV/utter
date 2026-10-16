import AppKit
import SwiftUI
import XCTest
import UtterContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
final class NativeSelectionReviewInteractionTests: XCTestCase {
    private typealias UI = NativeSelectionReviewTestSupport
    private var previousLanguage: UILanguage = .chinese

    override func setUp() {
        super.setUp()
        previousLanguage = L("common.cancel") == "Cancel" ? .english : .chinese
    }

    override func tearDown() {
        Loc.use(previousLanguage)
        super.tearDown()
    }

    func testLongRemoteDisclosureScrollsAtNarrowSizesWithoutAnyCandidateOrApply() async throws {
        let selected = "待披露开头 e\u{301} 👩🏽‍💻 🇸🇬\n" + String(repeating: "请保留每一条完整选区与空白。\n", count: 60) + "待披露末尾-END"
        for language in [UILanguage.english, .chinese] {
            Loc.use(language)
            for width in [CGFloat(280), 320, 420] {
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    let consent = SelectionEditRemoteConsent(selectedText: selected, providerID: "generation.remote",
                        providerBaseURL: "https://example.invalid/v1")
                    let panel = try await UI.panel(RemoteDisclosureView(consent: consent, intentID: UUID(), callbacks: .none),
                        width: width, height: 360)
                    defer { panel.close() }
                    panel.appearance = NSAppearance(named: appearance)
                    try await UI.settle(panel)
                    XCTAssertEqual(panel.frame.size, NSSize(width: width, height: 360))
                    let scroll = try XCTUnwrap(UI.scrollView(in: try XCTUnwrap(panel.contentView)))
                    let start = scroll.contentView.bounds.origin
                    try await NativeE2EUI.capture("disclosure-start-\(language)-\(width)-\(appearance.rawValue)", window: panel)
                    var reachedEnd = false
                    for _ in 0..<240 {
                        if UI.endIsVisible(try UI.text("待披露末尾-END", in: panel), in: scroll) { reachedEnd = true; break }
                        try UI.scroll(by: 80, in: scroll)
                        await Task.yield()
                    }
                    XCTAssertTrue(reachedEnd)
                    XCTAssertNotEqual(start, scroll.contentView.bounds.origin)
                    UI.assertVisible(try UI.button(L("common.cancel"), in: panel), in: panel)
                    UI.assertVisible(try UI.button(L("common.continue"), in: panel), in: panel)
                    XCTAssertFalse(UI.nodes(panel).contains { $0.accessibilityRole() == .button && $0.accessibilityLabel() == L("selection_edit.apply") })
                    try await NativeE2EUI.capture("disclosure-end-\(language)-\(width)-\(appearance.rawValue)", window: panel)
                    for _ in 0..<240 { try UI.scroll(by: -80, in: scroll) }
                    XCTAssertEqual(scroll.contentView.bounds.origin.y, start.y, accuracy: 1)
                    panel.close()
                }
            }
        }
    }

    func testRestoreAccessibilityIsOneUseAndFailureRemainsReadable() async throws {
        for succeeded in [false, true] {
            Loc.use(.english)
            var calls = 0
            var closed = 0
            var callbacks = SelectionReviewCallbacks.none
            callbacks.restore = { _ in calls += 1; return succeeded }
            let receipt = SelectionEditRestoration(operationID: UUID(), originalSelection: "原文 👩🏽‍💻",
                replacement: "候选 🇸🇬", expiresAt: Date().addingTimeInterval(15), isAvailable: true)
            let panel = try await UI.panel(RestoreOfferView(restoration: receipt, callbacks: callbacks,
                onClose: { closed += 1 }), width: 280, height: SelectionReviewMetrics.restoreHeight)
            defer { panel.close() }
            let restore = try UI.button(L("selection_edit.restore"), in: panel)
            XCTAssertTrue(try restore.accessibilityPerformPress())
            try await UI.settle(panel)
            XCTAssertEqual(panel.frame.size, NSSize(width: 280, height: 80))
            _ = try UI.button(L("selection_edit.restore"), in: panel).accessibilityPerformPress()
            XCTAssertEqual(calls, 1)
            XCTAssertFalse(try UI.button(L("selection_edit.restore"), in: panel).isAccessibilityEnabled())
            UI.assertVisible(try UI.button(L("common.close"), in: panel), in: panel)
            UI.assertVisible(try UI.button(L("selection_edit.restore"), in: panel), in: panel)
            if !succeeded { UI.assertVisible(try UI.text(L("selection_edit.restore_failed"), in: panel), in: panel) }
            try await NativeE2EUI.capture("restore-result-\(succeeded)", window: panel)
            XCTAssertTrue(try UI.button(L("common.close"), in: panel).accessibilityPerformPress())
            XCTAssertEqual(closed, 1)
            panel.close()
        }
    }

}

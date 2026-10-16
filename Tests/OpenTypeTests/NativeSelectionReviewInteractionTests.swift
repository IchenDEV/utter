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

    func testLongOriginalAndCandidateScrollToTheirEndsAtNarrowSizes() async throws {
        let original = "原文开头 e\u{301} 👩🏽‍💻 🇸🇬\n" + String(repeating: "请保留每一条原文细节与空白。\n", count: 60) + "原文末尾-END"
        let candidate = "候选开头 e\u{301} 👩🏽‍💻 🇸🇬\n" + String(repeating: "请保留每一条修改后细节。\n", count: 60) + "候选末尾-END"
        for language in [UILanguage.english, .chinese] {
            Loc.use(language)
            for width in [CGFloat(280), 320, 420] {
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    let proposal = makeProposal(original: original, candidate: candidate)
                    let panel = try await UI.panel(SelectionReviewView(proposal: proposal, callbacks: .none),
                        width: width, height: 360)
                    defer { panel.close() }
                    panel.appearance = NSAppearance(named: appearance)
                    try await UI.settle(panel)
                    let content = try XCTUnwrap(panel.contentView)
                    let scroll = try XCTUnwrap(UI.scrollView(in: content))
                    _ = try UI.text("原文末尾-END", in: panel)
                    _ = try UI.text("候选末尾-END", in: panel)
                    let cancel = try UI.button(L("common.cancel"), in: panel)
                    let apply = try UI.button(L("selection_edit.apply"), in: panel)
                    UI.assertVisible(cancel, in: panel)
                    UI.assertVisible(apply, in: panel)
                    XCTAssertFalse(panel.isKeyWindow)
                    let start = scroll.contentView.bounds.origin
                    var sawOriginalEnd = false
                    var sawCandidateEnd = false
                    for _ in 0..<240 {
                        let originalEnd = UI.endIsVisible(try UI.text("原文末尾-END", in: panel), in: scroll)
                        if !sawOriginalEnd && originalEnd {
                            sawOriginalEnd = true
                            try await NativeE2EUI.capture("original-end-\(language)-\(width)-\(appearance.rawValue)", window: panel)
                        }
                        if UI.endIsVisible(try UI.text("候选末尾-END", in: panel), in: scroll) { sawCandidateEnd = true }
                        if sawOriginalEnd && sawCandidateEnd { break }
                        try UI.scroll(by: 80, in: scroll)
                        await Task.yield()
                    }
                    XCTAssertTrue(sawOriginalEnd, "Original end unreachable at \(width), \(language), \(appearance)")
                    XCTAssertTrue(sawCandidateEnd, "Candidate end unreachable at \(width), \(language), \(appearance)")
                    XCTAssertNotEqual(start, scroll.contentView.bounds.origin)
                    UI.assertVisible(try UI.button(L("common.cancel"), in: panel), in: panel)
                    UI.assertVisible(try UI.button(L("selection_edit.apply"), in: panel), in: panel)
                    try await NativeE2EUI.capture("scroll-end-\(language)-\(width)-\(appearance.rawValue)", window: panel)
                    for _ in 0..<240 { try UI.scroll(by: -80, in: scroll) }
                    XCTAssertEqual(scroll.contentView.bounds.origin.y, start.y, accuracy: 1)
                    try await NativeE2EUI.capture("scroll-start-\(language)-\(width)-\(appearance.rawValue)", window: panel)
                    try NativeE2EUI.record("scroll-driver-\(language)-\(width)-\(appearance.rawValue)",
                        ["driver": "Public NSView.scroll on the owned native scroll document",
                         "physicalWheelVerified": false, "startY": start.y,
                         "returnedY": scroll.contentView.bounds.minY])
                    panel.close()
                }
            }
        }
    }

    func testAccessibleContentOrderAndOneUseApplyInBothLanguages() async throws {
        for language in [UILanguage.english, .chinese] {
            Loc.use(language)
            var applyCount = 0
            var cancelCount = 0
            var callbacks = SelectionReviewCallbacks.none
            callbacks.apply = { _ in applyCount += 1; return true }
            callbacks.cancel = { _ in cancelCount += 1 }
            let proposal = makeProposal(original: "原文 e\u{301} 👩🏽‍💻", candidate: "候选 🇸🇬")
            let panel = try await UI.panel(SelectionReviewView(proposal: proposal, callbacks: callbacks),
                width: 280, height: 360)
            defer { panel.close() }
            let strings = UI.nodes(panel).map {
                ($0.accessibilityLabel() ?? "") + $0.textValue
            }
            let instruction = try XCTUnwrap(strings.firstIndex { $0.contains(proposal.recognizedInstruction) })
            let original = try XCTUnwrap(strings.firstIndex { $0.contains(proposal.originalSelection) })
            let candidate = try XCTUnwrap(strings.firstIndex { $0.contains(proposal.candidate) })
            XCTAssertLessThan(instruction, original)
            XCTAssertLessThan(original, candidate)
            let apply = try UI.button(L("selection_edit.apply"), in: panel)
            XCTAssertTrue(try apply.isAccessibilityEnabled())
            XCTAssertTrue(try apply.accessibilityPerformPress())
            try await UI.settle(panel)
            _ = try UI.button(L("selection_edit.apply"), in: panel).accessibilityPerformPress()
            XCTAssertEqual(applyCount, 1)
            XCTAssertFalse(try UI.button(L("selection_edit.apply"), in: panel).isAccessibilityEnabled())
            XCTAssertTrue(try UI.button(L("common.cancel"), in: panel).accessibilityPerformPress())
            XCTAssertEqual(cancelCount, 1)
            panel.close()
        }
    }

    func testExpiredProposalCannotApplyThroughAccessibility() async throws {
        Loc.use(.english)
        var calls = 0
        var callbacks = SelectionReviewCallbacks.none
        callbacks.apply = { _ in calls += 1; return true }
        let proposal = makeProposal(expiresAt: .distantPast)
        let panel = try await UI.panel(SelectionReviewView(proposal: proposal, callbacks: callbacks), width: 280, height: 240)
        defer { panel.close() }
        let apply = try UI.button(L("selection_edit.apply"), in: panel)
        XCTAssertFalse(try apply.isAccessibilityEnabled())
        _ = try apply.accessibilityPerformPress()
        XCTAssertEqual(calls, 0)
    }

    func testKeyboardCancelDoesNotMakeReturnAnApplyShortcut() async throws {
        Loc.use(.english)
        var applied = 0
        var cancelled = 0
        var callbacks = SelectionReviewCallbacks.none
        callbacks.apply = { _ in applied += 1; return true }
        callbacks.cancel = { _ in cancelled += 1 }
        let panel = try await UI.panel(SelectionReviewView(proposal: makeProposal(), callbacks: callbacks),
            width: 280, height: 240, accessibility: false)
        defer { panel.close() }
        for (code, character) in [(UInt16(36), "\r"), (UInt16(53), "\u{1b}")] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code))
            let handled = panel.performKeyEquivalent(with: event)
            XCTAssertEqual(handled, code == 53)
        }
        XCTAssertEqual(applied, 0)
        XCTAssertEqual(cancelled, 1)
        XCTAssertFalse(panel.isKeyWindow)
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
                onClose: { closed += 1 }), width: 280, height: 104)
            defer { panel.close() }
            let restore = try UI.button(L("selection_edit.restore"), in: panel)
            XCTAssertTrue(try restore.accessibilityPerformPress())
            try await UI.settle(panel)
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

    func testRejectedApplyKeepsNoticeAndCancelVisibleWithoutRetry() async throws {
        for language in [UILanguage.english, .chinese] {
            Loc.use(language)
            var calls = 0
            var cancelled = 0
            var callbacks = SelectionReviewCallbacks.none
            callbacks.apply = { _ in calls += 1; return false }
            callbacks.cancel = { _ in cancelled += 1 }
            let panel = try await UI.panel(SelectionReviewView(proposal: makeProposal(), callbacks: callbacks),
                width: 280, height: 240)
            defer { panel.close() }
            XCTAssertTrue(try UI.button(L("selection_edit.apply"), in: panel).accessibilityPerformPress())
            try await UI.settle(panel)
            _ = try UI.button(L("selection_edit.apply"), in: panel).accessibilityPerformPress()
            XCTAssertEqual(calls, 1)
            UI.assertVisible(try UI.text(L("selection_edit.expired"), in: panel), in: panel)
            UI.assertVisible(try UI.button(L("common.cancel"), in: panel), in: panel)
            try await NativeE2EUI.capture("rejected-apply-\(language)", window: panel)
            XCTAssertTrue(try UI.button(L("common.cancel"), in: panel).accessibilityPerformPress())
            XCTAssertEqual(cancelled, 1)
            panel.close()
        }
    }

    private func makeProposal(original: String = "原文", candidate: String = "候选",
                              expiresAt: Date = Date().addingTimeInterval(120)) -> SelectionEditProposal {
        SelectionEditProposal(sessionID: UUID(), targetID: UUID(), originalSelection: original,
            recognizedInstruction: "改礼貌一点，保留完整细节与 Unicode。", candidate: candidate, expiresAt: expiresAt)
    }
}

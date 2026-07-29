import AppKit
import XCTest
@testable import OpenType

@MainActor
final class DeferredReplacementPolicyTests: XCTestCase {
    func testOnlyAppliesToSmartFormat() {
        XCTAssertTrue(DeferredReplacementPolicy.shouldUseDeferredReplacement(
            outputMode: .processed,
            enableInstantInsert: true
        ))
        XCTAssertFalse(DeferredReplacementPolicy.shouldUseDeferredReplacement(
            outputMode: .processed,
            enableInstantInsert: false
        ))
        XCTAssertFalse(DeferredReplacementPolicy.shouldUseDeferredReplacement(
            outputMode: .direct,
            enableInstantInsert: true
        ))
        XCTAssertFalse(DeferredReplacementPolicy.shouldUseDeferredReplacement(
            outputMode: .command,
            enableInstantInsert: true
        ))
    }

    func testFormattingKeepsFocusedTextFromQuickContext() {
        let quickContext = InputContext(
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Planning",
            screenContext: nil,
            textBeforeSelection: "before cursor",
            selectedText: "selected phrase",
            textAfterSelection: "after cursor",
            outputMode: .processed,
            inputLanguage: .english,
            source: .menuBar
        )
        let replacement = DeferredReplacement(
            rawText: "raw",
            insertedText: "quick",
            targetApp: nil,
            message: "formatting",
            context: quickContext
        )

        let deferredContext = VoicePipeline.deferredInputContext(
            for: replacement,
            screenContext: "fresh OCR",
            inputLanguage: .english
        )

        XCTAssertEqual(deferredContext.windowTitle, "Planning")
        XCTAssertEqual(deferredContext.screenContext, "fresh OCR")
        XCTAssertEqual(deferredContext.textBeforeSelection, "before cursor")
        XCTAssertEqual(deferredContext.selectedText, "selected phrase")
        XCTAssertEqual(deferredContext.textAfterSelection, "after cursor")
    }

    func testFailedStateIsNotReplaceable() {
        var replacement = DeferredReplacement(
            rawText: "raw",
            insertedText: "quick",
            targetApp: nil,
            message: "formatting",
            createdAt: Date(timeIntervalSince1970: 100),
            expirationInterval: 15
        )
        replacement.state = .failed

        XCTAssertEqual(
            DeferredReplacementPolicy.decision(
                for: replacement,
                currentBundleIdentifier: nil,
                now: Date(timeIntervalSince1970: 105)
            ),
            .copy(.notReady)
        )
    }

    func testDecisionRequiresSameFrontmostApp() throws {
        var replacement = DeferredReplacement(
            rawText: "raw",
            insertedText: "quick",
            targetApp: nil,
            message: "formatting",
            createdAt: Date(timeIntervalSince1970: 100),
            expirationInterval: 15
        )
        replacement.formattedText = "formatted"
        replacement.state = .ready

        XCTAssertEqual(
            DeferredReplacementPolicy.decision(
                for: replacement,
                currentBundleIdentifier: nil,
                now: Date(timeIntervalSince1970: 105)
            ),
            .copy(.missingTarget)
        )

        guard let bundleIdentifier = NSRunningApplication.current.bundleIdentifier else {
            throw XCTSkip("Current test process has no bundle identifier")
        }

        replacement = DeferredReplacement(
            rawText: "raw",
            insertedText: "quick",
            targetApp: NSRunningApplication.current,
            message: "formatting",
            createdAt: Date(timeIntervalSince1970: 100),
            expirationInterval: 15
        )
        replacement.formattedText = "formatted"
        replacement.state = .ready

        XCTAssertEqual(
            DeferredReplacementPolicy.decision(
                for: replacement,
                currentBundleIdentifier: "other.app",
                now: Date(timeIntervalSince1970: 105)
            ),
            .copy(.appChanged)
        )
        XCTAssertEqual(
            DeferredReplacementPolicy.decision(
                for: replacement,
                currentBundleIdentifier: bundleIdentifier,
                now: Date(timeIntervalSince1970: 116)
            ),
            .copy(.expired)
        )
    }
}

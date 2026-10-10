import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import UtterContracts
import AppKit
import XCTest
@testable import UtterPresentation

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


    func testFailedStateIsNotReplaceable() {
        var replacement = DeferredReplacement(
            historyRecordID: UUID(),
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
            historyRecordID: UUID(),
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
            historyRecordID: UUID(),
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

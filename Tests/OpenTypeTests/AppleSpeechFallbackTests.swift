import UtterContracts
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
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import XCTest
import UtterAppleSpeech

@MainActor
final class AppleSpeechFallbackTests: XCTestCase {
    func testCancellationNeverStartsLegacyRecognizer() async {
        var legacyCalls = 0
        var reports = 0
        do {
            _ = try await AppleSpeechTranscriptionFallback.run(analyzer: { throw CancellationError() }, legacy: {
                legacyCalls += 1; return "legacy"
            }, reportFailure: { _ in reports += 1 })
            XCTFail("Cancellation produced a transcript")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(legacyCalls, 0)
        XCTAssertEqual(reports, 0)
    }

    func testNonCooperativeAnalyzerCannotPublishOrStartFallbackAfterCancellation() async {
        var entered = false
        var release: CheckedContinuation<Void, Never>?
        var legacyCalls = 0
        let task = Task {
            try await AppleSpeechTranscriptionFallback.run(analyzer: {
                entered = true
                await withCheckedContinuation { release = $0 }
                return "   "
            }, legacy: { legacyCalls += 1; return "legacy" }, reportFailure: { _ in })
        }
        while !entered { await Task.yield() }
        task.cancel()
        release?.resume()
        do { _ = try await task.value; XCTFail("Cancelled analyzer continued") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(legacyCalls, 0)
    }

    func testAnalyzerFailureAndEmptyTranscriptStillUseIntentionalLegacyFallback() async throws {
        var reports = 0
        let errorResult = try await AppleSpeechTranscriptionFallback.run(analyzer: { throw FixtureError.failed },
            legacy: { "legacy" }, reportFailure: { _ in reports += 1 })
        let emptyResult = try await AppleSpeechTranscriptionFallback.run(analyzer: { " " },
            legacy: { "legacy" }, reportFailure: { _ in reports += 1 })
        XCTAssertEqual(errorResult, "legacy")
        XCTAssertEqual(emptyResult, "legacy")
        XCTAssertEqual(reports, 1)
    }
}

private enum FixtureError: Error { case failed }

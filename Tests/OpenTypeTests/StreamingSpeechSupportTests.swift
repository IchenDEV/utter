import Foundation
import XCTest
@testable import OpenType

final class StreamingSpeechSupportTests: XCTestCase {
    func testPartialUpdateSchedulerKeepsExistingTimerWhenBuffersContinueArriving() {
        var scheduler = StreamingPartialUpdateScheduler()

        XCTAssertTrue(scheduler.requestSchedule())
        XCTAssertFalse(scheduler.requestSchedule())

        scheduler.markScheduledUpdateFired()
        XCTAssertTrue(scheduler.requestSchedule())

        scheduler.cancelScheduledUpdate()
        XCTAssertTrue(scheduler.requestSchedule())
    }

    func testPreviewAccumulatorPreservesEarlierContextAcrossSlidingWindow() {
        let accumulator = StreamingPreviewAccumulator()

        XCTAssertEqual(accumulator.merge("你好今天我们来"), "你好今天我们来")
        XCTAssertEqual(accumulator.merge("我们来测试流式"), "你好今天我们来测试流式")
        XCTAssertEqual(accumulator.merge("测试流式识别"), "你好今天我们来测试流式识别")
    }

    func testPreviewAccumulatorReplacesMatchingTailWhenRecognitionRefinesText() {
        let accumulator = StreamingPreviewAccumulator()

        XCTAssertEqual(accumulator.merge("hello wor"), "hello wor")
        XCTAssertEqual(accumulator.merge("hello world"), "hello world")
    }

    func testPreviewAccumulatorIgnoresShorterTailRegression() {
        let accumulator = StreamingPreviewAccumulator()

        XCTAssertEqual(accumulator.merge("open type streaming"), "open type streaming")
        XCTAssertEqual(accumulator.merge("streaming"), "open type streaming")
    }

    func testPreviewAccumulatorMergesAcrossTentativePunctuation() {
        let accumulator = StreamingPreviewAccumulator()

        XCTAssertEqual(accumulator.merge("Ship the release notes."), "Ship the release notes.")
        XCTAssertEqual(accumulator.merge("release notes today."), "Ship the release notes today.")
    }

    func testPreviewAccumulatorDoesNotMergeShortLatinPrefixInsideWord() {
        let accumulator = StreamingPreviewAccumulator()

        XCTAssertEqual(accumulator.merge("go to"), "go to")
        XCTAssertEqual(accumulator.merge("today"), "go to today")
    }

    func testPreviewAccumulatorContinuesTrailingLatinWordFragments() {
        let accumulator = StreamingPreviewAccumulator()

        XCTAssertEqual(accumulator.merge("hello wor"), "hello wor")
        XCTAssertEqual(accumulator.merge("world today"), "hello world today")
    }

    func testPreviewAccumulatorMergesShortLatinWholeWordOverlap() {
        let accumulator = StreamingPreviewAccumulator()

        XCTAssertEqual(accumulator.merge("go to."), "go to.")
        XCTAssertEqual(accumulator.merge("to start"), "go to start")
    }

    func testPreviewAccumulatorAddsSpaceAfterSentencePunctuationWithoutOverlap() {
        let accumulator = StreamingPreviewAccumulator()

        XCTAssertEqual(accumulator.merge("Ship today."), "Ship today.")
        XCTAssertEqual(accumulator.merge("Confirm QA."), "Ship today. Confirm QA.")
    }

    func testPreviewAccumulatorConcatenatesCJKWithoutArtificialSpace() {
        let accumulator = StreamingPreviewAccumulator()

        XCTAssertEqual(accumulator.merge("今天下午"), "今天下午")
        XCTAssertEqual(accumulator.merge("同步发布"), "今天下午同步发布")
    }

    func testPreviewAccumulatorConcatenatesJapaneseKanaWithoutArtificialSpace() {
        let accumulator = StreamingPreviewAccumulator()

        XCTAssertEqual(accumulator.merge("金曜の午後"), "金曜の午後")
        XCTAssertEqual(accumulator.merge("よろしく"), "金曜の午後よろしく")
        XCTAssertEqual(accumulator.merge("お願いします"), "金曜の午後よろしくお願いします")
    }

    func testTranscriptResolverUsesRecordedAudioWhenAvailable() async throws {
        let metrics = StreamingSessionMetrics(
            receivedBufferCount: 4,
            capturedUnitCount: 64_000,
            partialUpdateCount: 2,
            startedAt: Date(),
            lastPartialAt: Date(),
            lastPartialUnitCount: 64_000
        )

        var transcribeCalls = 0
        let text = try await StreamingTranscriptResolver.resolveFinalTranscript(
            engineName: "WhisperEngine",
            audioURL: URL(fileURLWithPath: "/tmp/opentype-test.wav"),
            livePreviewText: "preview text",
            metrics: metrics,
            unitLabel: "samples"
        ) {
            transcribeCalls += 1
            return "final text"
        }

        XCTAssertEqual(text, "final text")
        XCTAssertEqual(transcribeCalls, 1)
    }

    func testTranscriptResolverAlwaysRetranscribesEvenWhenPreviewCoversAudio() async throws {
        // The heuristic preview can lock in mis-heard characters at window
        // boundaries, so a covering preview must not shortcut re-transcription.
        let metrics = StreamingSessionMetrics(
            receivedBufferCount: 4,
            capturedUnitCount: 64_000,
            partialUpdateCount: 2,
            startedAt: Date(),
            lastPartialAt: Date(),
            lastPartialUnitCount: 64_000
        )

        var transcribeCalls = 0
        let text = try await StreamingTranscriptResolver.resolveFinalTranscript(
            engineName: "WhisperEngine",
            audioURL: URL(fileURLWithPath: "/tmp/opentype-test.wav"),
            livePreviewText: " preview text ",
            metrics: metrics,
            unitLabel: "samples"
        ) {
            transcribeCalls += 1
            return "final text"
        }

        XCTAssertEqual(text, "final text")
        XCTAssertEqual(transcribeCalls, 1)
    }

    func testTranscriptResolverFallsBackToLivePreviewWithoutRecordedAudio() async throws {
        let metrics = StreamingSessionMetrics(
            receivedBufferCount: 2,
            capturedUnitCount: 32_000,
            partialUpdateCount: 1,
            startedAt: Date(),
            lastPartialAt: Date()
        )

        var transcribeCalls = 0
        let text = try await StreamingTranscriptResolver.resolveFinalTranscript(
            engineName: "VolcASR",
            audioURL: nil,
            livePreviewText: "live preview only",
            metrics: metrics,
            unitLabel: "bytes"
        ) {
            transcribeCalls += 1
            return "should not be used"
        }

        XCTAssertEqual(text, "live preview only")
        XCTAssertEqual(transcribeCalls, 0)
    }

    func testTranscriptResolverFallsBackToPreviewWhenRetranscriptionIsEmpty() async throws {
        let metrics = StreamingSessionMetrics(
            receivedBufferCount: 3,
            capturedUnitCount: 24_000,
            partialUpdateCount: 2,
            startedAt: Date(),
            lastPartialAt: Date()
        )

        let text = try await StreamingTranscriptResolver.resolveFinalTranscript(
            engineName: "VolcASR",
            audioURL: URL(fileURLWithPath: "/tmp/opentype-test.wav"),
            livePreviewText: "live preview text",
            metrics: metrics,
            unitLabel: "bytes"
        ) {
            ""
        }

        XCTAssertEqual(text, "live preview text")
    }
}

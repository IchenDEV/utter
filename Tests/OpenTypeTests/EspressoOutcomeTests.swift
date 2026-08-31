import XCTest
@testable import OpenType

final class EspressoOutcomeTests: XCTestCase {
    private final class WeakTrackerBox {
        weak var value: EspressoGenerationTracker?
    }

    func testOutcomeTrackingUsesLatestOperationAndIsRequestScoped() async {
        let processor = TextProcessor()
        var outcomes: [EspressoGenerationOutcome?] = []

        await TextProcessor.withEspressoOutcomeTracking {
            await TextProcessor.recordEspressoOutcome(.fallback)
            await TextProcessor.recordEspressoOutcome(.failed)
            outcomes.append(await processor.consumeEspressoOutcome())
        }
        await TextProcessor.withEspressoOutcomeTracking {
            await TextProcessor.recordEspressoOutcome(.failed)
            await TextProcessor.recordEspressoOutcome(.fallback)
            outcomes.append(await processor.consumeEspressoOutcome())
        }
        await TextProcessor.withEspressoOutcomeTracking {
            outcomes.append(await processor.consumeEspressoOutcome())
        }
        for staleOutcome in [EspressoGenerationOutcome.fallback, .failed] {
            await TextProcessor.withEspressoOutcomeTracking {
                await TextProcessor.recordEspressoOutcome(staleOutcome)
                await TextProcessor.clearEspressoOutcome()
                outcomes.append(await processor.consumeEspressoOutcome())
            }
        }

        XCTAssertEqual(outcomes[0], .failed)
        XCTAssertEqual(outcomes[1], .fallback)
        XCTAssertNil(outcomes[2])
        XCTAssertNil(outcomes[3])
        XCTAssertNil(outcomes[4])
    }

    func testRemoteAttemptClearsEarlierEspressoOutcome() async {
        let processor = TextProcessor()
        var options = TextProcessingOptions(settings: AppSettings.shared)
        options.useRemoteLLM = true
        options.remoteAPIKey = ""
        var outcome: EspressoGenerationOutcome?

        await TextProcessor.withEspressoOutcomeTracking {
            await TextProcessor.recordEspressoOutcome(.fallback)
            _ = try? await processor.generateText(
                prompt: "test",
                systemPrompt: "test",
                options: options,
                maxTokens: 1,
                temperature: 0
            )
            outcome = await processor.consumeEspressoOutcome()
        }

        XCTAssertNil(outcome)
    }

    func testOutcomeTrackerIsReleasedAfterRequestCompletes() async {
        let box = WeakTrackerBox()

        await TextProcessor.withEspressoOutcomeTracking {
            box.value = TextProcessor.espressoGenerationTracker
            XCTAssertNotNil(box.value)
        }

        XCTAssertNil(box.value)
    }
}

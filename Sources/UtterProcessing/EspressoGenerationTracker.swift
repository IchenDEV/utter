import UtterContracts

package actor EspressoGenerationTracker {
    private var outcome: EspressoGenerationOutcome?

    package init() {}

    package func record(_ newOutcome: EspressoGenerationOutcome) {
        outcome = newOutcome
    }

    package func clear() {
        outcome = nil
    }

    package func consume() -> EspressoGenerationOutcome? {
        defer { outcome = nil }
        return outcome
    }
}


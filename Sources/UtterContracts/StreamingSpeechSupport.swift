import Foundation

package struct StreamingSessionMetrics: Equatable {
    package var receivedBufferCount = 0
    package var capturedUnitCount = 0
    package var partialUpdateCount = 0
    package var startedAt = Date()
    package var lastPartialAt: Date?
    package var lastPartialUnitCount = 0

    package init(
        receivedBufferCount: Int = 0, capturedUnitCount: Int = 0, partialUpdateCount: Int = 0,
        startedAt: Date = Date(), lastPartialAt: Date? = nil, lastPartialUnitCount: Int = 0
    ) {
        self.receivedBufferCount = receivedBufferCount
        self.capturedUnitCount = capturedUnitCount
        self.partialUpdateCount = partialUpdateCount
        self.startedAt = startedAt
        self.lastPartialAt = lastPartialAt
        self.lastPartialUnitCount = lastPartialUnitCount
    }

    package var hasCapturedAudio: Bool {
        capturedUnitCount > 0
    }

    package var livePreviewCoversCapturedAudio: Bool {
        partialUpdateCount > 0 && lastPartialUnitCount >= capturedUnitCount
    }

    package mutating func recordBuffer(unitCount: Int) {
        guard unitCount > 0 else { return }
        receivedBufferCount += 1
        capturedUnitCount += unitCount
    }

    package mutating func markPartial(unitCount: Int, at date: Date = Date()) {
        partialUpdateCount += 1
        lastPartialAt = date
        lastPartialUnitCount = max(lastPartialUnitCount, unitCount)
    }
}

package struct StreamingSessionOutcome: Equatable {
    package let livePreviewText: String
    package let metrics: StreamingSessionMetrics
    package init(livePreviewText: String, metrics: StreamingSessionMetrics) {
        self.livePreviewText = livePreviewText
        self.metrics = metrics
    }
}

package struct StreamingPartialUpdateScheduler: Equatable {
    package init() {}
    private var hasScheduledUpdate = false

    package mutating func requestSchedule() -> Bool {
        guard !hasScheduledUpdate else { return false }
        hasScheduledUpdate = true
        return true
    }

    package mutating func markScheduledUpdateFired() {
        hasScheduledUpdate = false
    }

    package mutating func cancelScheduledUpdate() {
        hasScheduledUpdate = false
    }
}

package enum StreamingTranscriptResolver {
    /// The live preview is a heuristic merge of sliding-window partials and can
    /// lock in mis-heard characters at window boundaries. It is only ever used
    /// for HUD display and as a last-resort fallback — the final transcript is
    /// always re-transcribed from the recorded audio file when one exists.
    package static func resolveFinalTranscript(
        engineName: String,
        audioURL: URL?,
        livePreviewText: String,
        metrics: StreamingSessionMetrics,
        unitLabel: String,
        log: Log? = nil,
        transcribeFromFile: @escaping () async throws -> String
    ) async throws -> String {
        try Task.checkCancellation()
        let elapsed = Date().timeIntervalSince(metrics.startedAt)
        let partialAgeText: String
        if let lastPartialAt = metrics.lastPartialAt {
            partialAgeText = String(format: "%.2fs", Date().timeIntervalSince(lastPartialAt))
        } else {
            partialAgeText = "n/a"
        }

        log?.info(
            "[\(engineName)] streaming summary: buffers=\(metrics.receivedBufferCount) " +
            "\(unitLabel)=\(metrics.capturedUnitCount) partials=\(metrics.partialUpdateCount) " +
            "elapsed=\(String(format: "%.2fs", elapsed)) lastPartialAgo=\(partialAgeText)"
        )

        if !metrics.hasCapturedAudio {
            log?.error("[\(engineName)] streaming session captured 0 \(unitLabel)")
        }

        let trimmedPreview = livePreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard audioURL != nil else {
            log?.info("[\(engineName)] no recorded audio file available, using live preview fallback")
            return trimmedPreview
        }

        let finalText = try await transcribeFromFile()
        try Task.checkCancellation()
        if finalText.isEmpty, !trimmedPreview.isEmpty {
            log?.info("[\(engineName)] recorded-audio transcription was empty, falling back to live preview")
            return trimmedPreview
        }
        return finalText
    }
}

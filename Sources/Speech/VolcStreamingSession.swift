import UtterMediaContracts
import AVFoundation
import Foundation

final class VolcStreamingSession: @unchecked Sendable {
    private let engine: VolcSpeechEngine
    private let language: String?
    private let partialHandler: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "opentype.volc-stream")

    private static let partialWindowBytes = 15 * 16_000 * 2
    private static let minPartialBytes = 32_000

    private var normalizer: StreamingAudioNormalizer?
    private var pcmData = Data()
    private var previewAccumulator = StreamingPreviewAccumulator()
    private var latestPreview = ""
    private var pendingWorkItem: DispatchWorkItem?
    private var updateScheduler = StreamingPartialUpdateScheduler()
    private var activeTask: Task<String, Error>?
    private var submittedByteCount = 0
    private var closed = false
    private var metrics = StreamingSessionMetrics()

    init(
        engine: VolcSpeechEngine,
        language: String?,
        partialHandler: @escaping @Sendable (String) -> Void
    ) {
        self.engine = engine
        self.language = language
        self.partialHandler = partialHandler
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        queue.async {
            guard !self.closed else { return }
            if self.normalizer == nil {
                self.normalizer = StreamingAudioNormalizer(inputFormat: buffer.format)
            }

            guard let normalizer = self.normalizer else {
                Log.error("[VolcASR] failed to create streaming audio normalizer")
                return
            }

            do {
                let chunk = try normalizer.convert(buffer)
                let chunkData = chunk.pcm16Data
                guard !chunkData.isEmpty else { return }
                self.metrics.recordBuffer(unitCount: chunkData.count)
                self.pcmData.append(chunkData)
                self.schedulePartialUpdate()
            } catch {
                Log.error("[VolcASR] streaming buffer conversion failed: \(error.localizedDescription)")
            }
        }
    }

    func finishLivePreview() async -> StreamingSessionOutcome {
        let task = queue.sync { () -> Task<String, Error>? in
            self.closed = true
            self.pendingWorkItem?.cancel()
            self.pendingWorkItem = nil
            self.updateScheduler.cancelScheduledUpdate()
            self.startFinalPartialTaskIfNeeded()
            return self.activeTask
        }
        _ = try? await task?.value

        let trailingTask = queue.sync { () -> Task<String, Error>? in
            self.startFinalPartialTaskIfNeeded()
            return self.activeTask
        }
        _ = try? await trailingTask?.value

        return queue.sync {
            StreamingSessionOutcome(
                livePreviewText: self.latestPreview,
                metrics: self.metrics
            )
        }
    }

    func cancel() {
        queue.sync {
            self.closed = true
            self.pendingWorkItem?.cancel()
            self.pendingWorkItem = nil
            self.updateScheduler.cancelScheduledUpdate()
            self.activeTask?.cancel()
            self.activeTask = nil
        }
    }

    private func schedulePartialUpdate() {
        guard updateScheduler.requestSchedule() else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.runScheduledPartialUpdate()
        }
        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.7, execute: workItem)
    }

    private func runScheduledPartialUpdate() {
        pendingWorkItem = nil
        updateScheduler.markScheduledUpdateFired()
        startPartialTaskIfNeeded()
    }

    private func startPartialTaskIfNeeded() {
        guard !closed, activeTask == nil, pcmData.count >= Self.minPartialBytes else { return }
        startPartialTask()
    }

    private func startFinalPartialTaskIfNeeded() {
        guard activeTask == nil, pcmData.count >= Self.minPartialBytes else { return }
        guard pcmData.count > submittedByteCount else { return }
        startPartialTask()
    }

    private func startPartialTask() {
        guard activeTask == nil else { return }

        let snapshot: Data
        if pcmData.count > Self.partialWindowBytes {
            snapshot = Data(pcmData.suffix(Self.partialWindowBytes))
        } else {
            snapshot = pcmData
        }
        let submittedByteCount = pcmData.count
        self.submittedByteCount = submittedByteCount

        activeTask = Task(priority: .utility) { [weak self, engine, language] in
            let text = try await engine.transcribePCMData(snapshot, language: language)
            await self?.finishPartialTask(text: text, submittedByteCount: submittedByteCount)
            return text
        }
    }

    private func finishPartialTask(text: String, submittedByteCount: Int) async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.activeTask = nil
                self.applyPartial(text, submittedByteCount: submittedByteCount, emitUpdate: !self.closed)
                if !self.closed, self.pcmData.count > submittedByteCount {
                    self.schedulePartialUpdate()
                }
                continuation.resume()
            }
        }
    }

    private func applyPartial(_ text: String, submittedByteCount: Int, emitUpdate: Bool) {
        guard !text.isEmpty else { return }

        let merged = previewAccumulator.merge(text)
        guard !merged.isEmpty else { return }
        metrics.markPartial(unitCount: submittedByteCount)
        guard merged != latestPreview else { return }

        latestPreview = merged
        if emitUpdate {
            partialHandler(merged)
        }
    }
}

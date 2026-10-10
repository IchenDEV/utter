import Foundation
import UtterContracts
import UtterMediaContracts

@MainActor
protocol CaptureDriver: AnyObject {
    func start(_ request: CaptureRequest, callbacks: CaptureCallbacks) async throws
    func stop(flushTail: Bool) async -> CapturedAudio
    func cleanup() async
}

@MainActor
final class ScopedCaptureService: CaptureService {
    private let makeDriver: (CaptureRequest) throws -> any CaptureDriver
    private let isCurrent: () -> Bool
    private var recording: CaptureRecording?
    private var closed = false

    init(isCurrent: @escaping () -> Bool, makeDriver: @escaping (CaptureRequest) throws -> any CaptureDriver) {
        self.isCurrent = isCurrent
        self.makeDriver = makeDriver
    }

    func begin(_ request: CaptureRequest, callbacks: CaptureCallbacks) async throws -> any OwnedRecording {
        try checkCurrent()
        guard recording == nil else { throw CaptureError.busy }
        let recording = CaptureRecording(driver: try makeDriver(request), isCurrent: isCurrent)
        self.recording = recording
        recording.onClose = { [weak self, weak recording] in
            if self?.recording === recording { self?.recording = nil }
        }
        do {
            try await recording.start(request, callbacks: callbacks)
            try checkCurrent()
            return recording
        } catch {
            await recording.close()
            throw error
        }
    }

    func revoke() {
        closed = true
        recording?.revoke()
    }

    func close() async {
        revoke()
        await recording?.close()
    }

    private func checkCurrent() throws {
        try Task.checkCancellation()
        guard !closed, isCurrent() else { throw CancellationError() }
    }
}

@MainActor
private final class CaptureRecording: OwnedRecording {
    private let driver: any CaptureDriver
    private let isCurrent: () -> Bool
    private let callbacks = CaptureCallbackGate()
    private var startTask: Task<Void, Error>?
    private var finishTask: Task<CapturedAudio, Never>?
    private var closeTask: Task<Void, Never>?
    private var closed = false
    var onClose: (() -> Void)?

    init(driver: any CaptureDriver, isCurrent: @escaping () -> Bool) {
        self.driver = driver
        self.isCurrent = isCurrent
    }

    func start(_ request: CaptureRequest, callbacks requested: CaptureCallbacks) async throws {
        try checkCurrent()
        let guarded = callbacks.guarding(requested)
        let task = Task { @MainActor in
            try self.checkCurrent()
            try await self.driver.start(request, callbacks: guarded)
        }
        startTask = task
        defer { startTask = nil }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try checkCurrent()
    }

    func finish() async throws -> CapturedAudio {
        try checkCurrent()
        let task: Task<CapturedAudio, Never>
        if let finishTask { task = finishTask }
        else {
            task = Task { @MainActor in await self.driver.stop(flushTail: true) }
            finishTask = task
        }
        let audio = await task.value
        callbacks.revoke()
        try checkCurrent()
        return audio
    }

    func revoke() {
        closed = true
        callbacks.revoke()
        startTask?.cancel()
        finishTask?.cancel()
    }

    func stopCapture() async {
        revoke()
        if let startTask { _ = await startTask.result }
        let stop: Task<CapturedAudio, Never>
        if let finishTask { stop = finishTask }
        else {
            stop = Task { @MainActor in await self.driver.stop(flushTail: false) }
            finishTask = stop
        }
        _ = await stop.value
    }

    func close() async {
        if let closeTask { await closeTask.value; return }
        revoke()
        let task = Task { @MainActor in
            await self.stopCapture()
            await self.driver.cleanup()
            self.onClose?()
            self.onClose = nil
        }
        closeTask = task
        await task.value
    }

    private func checkCurrent() throws {
        try Task.checkCancellation()
        guard !closed, isCurrent() else { throw CancellationError() }
    }
}

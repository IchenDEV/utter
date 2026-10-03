import UtterContracts
import Foundation

@MainActor
package final class CorrectionCaptureService: CorrectionControlService {
    private let enabled: () -> Bool
    private let learn: (LearnedCorrectionCandidate) -> Void
    private let updateHistory: (UUID, String) -> Void
    private let classification: any CorrectionClassificationService
    private let log: UtterContracts.Log

    package init(enabled: @escaping () -> Bool, classification: any CorrectionClassificationService,
                 learn: @escaping (LearnedCorrectionCandidate) -> Void,
                 updateHistory: @escaping (UUID, String) -> Void, log: UtterContracts.Log) {
        self.enabled = enabled
        self.classification = classification
        self.learn = learn
        self.updateHistory = updateHistory
        self.log = log
    }

    private static let lifetime: TimeInterval = 60
    private var activeSession: ActiveCorrectionCapture?
    private var observer: UUID?
    private var isClosed = false
    private var ownedTasks: [UUID: Task<Void, Never>] = [:]
    private var monitorTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    package func start(seed: CorrectionCaptureSeed, recordID: UUID) {
        guard !isClosed else { return }
        finishCurrentSession()
        guard enabled(), seed.observation.isEligible else {
            return
        }

        activeSession = ActiveCorrectionCapture(
            seed: seed,
            recordID: recordID,
            expiresAt: Date().addingTimeInterval(Self.lifetime),
            latestFinalText: seed.insertedText
        )
        installObserver(for: seed)
        startMonitor()
    }

    package func finishCurrentSession() {
        guard !isClosed, enabled() else {
            tearDown()
            return
        }
        captureLatestValue()
        guard let session = activeSession, session.seed.observation.isEligible else {
            tearDown()
            return
        }
        if session.latestFinalText != session.seed.insertedText,
           let candidate = classification.candidate(
                inserted: session.seed.insertedText,
                userFinal: session.latestFinalText,
                sourceRecordID: session.recordID,
                languageCode: session.seed.context.inputLanguage.whisperCode,
                bundleIdentifier: session.seed.context.bundleIdentifier
           ) {
            learn(candidate)
            log.info("[CorrectionCapture] learned candidate \(candidate.original.count)->\(candidate.replacement.count) chars")
        }
        tearDown()
    }

    package func cancelCurrentSession() {
        tearDown()
    }

    func handleValueChanged() {
        guard !isClosed, activeSession != nil else { return }
        debounceTask?.cancel()
        debounceTask = ownedTask { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.captureLatestValue()
        }
    }

    package func revoke() {
        guard !isClosed else { return }
        isClosed = true
        tearDown()
    }

    package func close() async {
        revoke()
        for task in Array(ownedTasks.values) { await task.value }
    }

    private func ownedTask(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.ownedTasks.removeValue(forKey: id) }
            await operation()
        }
        ownedTasks[id] = task
        return task
    }

}

private extension CorrectionCaptureService {
    struct ActiveCorrectionCapture {
        let seed: CorrectionCaptureSeed
        let recordID: UUID
        let expiresAt: Date
        var latestFinalText: String
    }

    func installObserver(for seed: CorrectionCaptureSeed) {
        observer = seed.observation.observe { [weak self] in self?.handleValueChanged() }
        if observer == nil { log.info("[CorrectionCapture] AX observer unavailable; using bounded polling") }
    }

    func startMonitor() {
        monitorTask?.cancel()
        monitorTask = ownedTask { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self, let session = self.activeSession else { return }
                guard !isClosed, enabled() else {
                    self.cancelCurrentSession()
                    return
                }
                if Date() >= session.expiresAt {
                    self.finishCurrentSession()
                    return
                }
                if !session.seed.observation.isFocused || !session.seed.observation.isEligible {
                    self.finishCurrentSession()
                    return
                }
                self.captureLatestValue()
            }
        }
    }

    func captureLatestValue() {
        guard !isClosed, enabled(), var session = activeSession,
              session.seed.observation.isEligible,
              let edited = session.seed.observation.readEditedText(),
              let associated = classification.associatedFinalText(
                inserted: session.seed.insertedText,
                edited: edited
              ) else {
            return
        }
        session.latestFinalText = associated
        activeSession = session
        updateHistory(session.recordID, associated)
    }

    func tearDown() {
        monitorTask?.cancel()
        debounceTask?.cancel()
        monitorTask = nil
        debounceTask = nil
        if let observer, let session = activeSession {
            session.seed.observation.removeObserver(observer)
        }
        observer = nil
        activeSession = nil
    }
}

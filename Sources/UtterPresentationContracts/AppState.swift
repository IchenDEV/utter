import Foundation
import Combine
import UtterContracts

package enum AppPhase: Equatable {
    case idle, downloading, loadingModel, recording, transcribing, processing, inserting, done, copied, uncertain
    case error(String)
}
package enum AppCompletionKind: Equatable { case standard, espressoFallback }
package enum VoiceInputMode: Equatable {
    case dictation, translation(TranslationLanguage)
    package var isTranslation: Bool { if case .translation = self { return true }; return false }
}

@MainActor
package final class AppState: ObservableObject {
    @Published package var selectedSettingsID = "presentation.general"
    @Published package private(set) var phase: AppPhase = .idle
    @Published package private(set) var rawTranscription = ""
    @Published package private(set) var processedText = ""
    @Published package private(set) var audioLevel: Float = 0
    @Published package private(set) var statusMessage = L("status.ready")
    @Published package private(set) var pendingReplacement: DeferredReplacement?
    @Published package private(set) var lastInsertedText = ""
    @Published package private(set) var activeInputMode: VoiceInputMode = .dictation
    @Published package private(set) var completionKind: AppCompletionKind = .standard
    @Published package private(set) var lastFormattingDurationSeconds: Double = 0
    @Published package private(set) var snapshot = SessionExecutionSnapshot()
    package var presentation: SessionPresentation { SessionPresentation(snapshot) }
    package var isRecording: Bool { phase == .recording }
    package var isDownloading: Bool { phase == .downloading }
    package var isBusy: Bool { snapshot.isBusy }
    package init() {}

    package func project(_ snapshot: SessionExecutionSnapshot) {
        self.snapshot = snapshot
        let presentation = SessionPresentation(snapshot)
        statusMessage = presentation.message
        rawTranscription = snapshot.transcript
        processedText = snapshot.text
        audioLevel = snapshot.audioLevel
        completionKind = snapshot.generationOutcome == .fallback ? .espressoFallback : .standard
        if case .translation(let target) = snapshot.mode { activeInputMode = .translation(target) }
        else { activeInputMode = .dictation }
        switch presentation.status {
        case .idle: phase = .idle
        case .preparing: phase = .loadingModel
        case .recording: phase = .recording
        case .transcribing: phase = .transcribing
        case .processing: phase = .processing
        case .delivering: phase = .inserting
        case .inserted: phase = .done
        case .copied: phase = .copied
        case .uncertain: phase = .uncertain
        case .failed: phase = .error(presentation.message)
        }
        if let performance = snapshot.performance {
            lastFormattingDurationSeconds = performance.generations.reduce(0) { $0 + $1.elapsedMilliseconds } / 1000
        } else { lastFormattingDurationSeconds = 0 }
    }

    package func project(_ output: SessionOutputSnapshot) {
        pendingReplacement = output.pending
        lastInsertedText = output.recentText
    }
}

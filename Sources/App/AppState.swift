import Foundation
import Combine

enum AppPhase: Equatable {
    case idle
    case downloading
    case recording
    case transcribing
    case processing
    case inserting
    case done
    case error(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .idle
    @Published var rawTranscription: String = ""
    @Published var processedText: String = ""
    @Published var audioLevel: Float = 0
    @Published var whisperModelReady = false
    @Published var llmModelReady = false
    @Published var downloadProgress: Double = 0
    @Published var downloadSizeText: String = ""
    @Published var downloadElapsedText: String = ""
    @Published var downloadRemainingText: String = ""
    @Published var downloadSpeedText: String = ""
    @Published var downloadDetailText: String = ""
    @Published var statusMessage: String = L("status.ready")
    @Published var lastInsertedText: String = ""
    @Published var lastFormattingDurationSeconds: Double = 0
    @Published var pendingReplacement: DeferredReplacement?
    @Published var activeInputMode: VoiceInputMode = .dictation

    let settings = AppSettings.shared

    var isRecording: Bool { phase == .recording }
    var isDownloading: Bool { phase == .downloading }

    var isBusy: Bool {
        switch phase {
        case .idle, .done, .error: return false
        default: return true
        }
    }

    func reset() {
        phase = .idle
        rawTranscription = ""
        processedText = ""
        audioLevel = 0
        statusMessage = L("status.ready")
        resetDownloadProgress()
        pendingReplacement = nil
        activeInputMode = .dictation
    }

    func clearPendingReplacement() {
        pendingReplacement = nil
    }

    func resetDownloadProgress() {
        downloadProgress = 0
        downloadSizeText = ""
        downloadElapsedText = ""
        downloadRemainingText = ""
        downloadSpeedText = ""
        downloadDetailText = ""
    }

    func updateDownloadProgress(_ info: DownloadProgressInfo) {
        downloadProgress = info.fraction
        downloadSizeText = info.transferredText
        downloadElapsedText = info.elapsedText
        downloadRemainingText = info.remainingText
        downloadSpeedText = info.speedText
        downloadDetailText = info.detailText
    }
}

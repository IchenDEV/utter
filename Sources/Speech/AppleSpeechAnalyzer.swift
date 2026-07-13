import AVFoundation
import Foundation
@preconcurrency import Speech

enum AppleSpeechAnalyzer {
    static func prepare(locale: Locale) async throws {
        let transcriber = try await makeTranscriber(locale: locale)
        try await ensureModel(for: transcriber)
    }

    static func transcribe(audioURL: URL, locale: Locale) async throws -> String {
        let transcriber = try await makeTranscriber(locale: locale)
        try await ensureModel(for: transcriber)

        let file = try AVAudioFile(forReading: audioURL)
        let resultTask = Task<String, Error> {
            var transcript = ""
            for try await result in transcriber.results where result.isFinal {
                transcript += String(result.text.characters)
            }
            return transcript
        }

        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
        do {
            if let lastSample = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await resultTask.value
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private static func makeTranscriber(locale: Locale) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechAnalyzerError.unavailable
        }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AppleSpeechAnalyzerError.unsupportedLocale(locale.identifier)
        }
        return SpeechTranscriber(locale: supported, preset: .transcription)
    }

    private static func ensureModel(for transcriber: SpeechTranscriber) async throws {
        let modules: [any SpeechModule] = [transcriber]
        if await AssetInventory.status(forModules: modules) == .installed { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await request.downloadAndInstall()
        }
        guard await AssetInventory.status(forModules: modules) == .installed else {
            throw AppleSpeechAnalyzerError.modelUnavailable
        }
    }
}

enum AppleSpeechAnalyzerError: LocalizedError {
    case unavailable
    case unsupportedLocale(String)
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "SpeechAnalyzer is unavailable on this Mac"
        case .unsupportedLocale(let locale):
            return "SpeechAnalyzer does not support locale \(locale)"
        case .modelUnavailable:
            return "SpeechAnalyzer model is not installed"
        }
    }
}

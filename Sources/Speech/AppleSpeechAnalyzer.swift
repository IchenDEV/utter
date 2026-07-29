import AVFoundation
import Foundation
@preconcurrency import Speech

enum AppleSpeechAnalyzer {
    static func prepare(locale: Locale) async throws {
        if let transcriber = await makeSpeechTranscriber(locale: locale) {
            try await ensureModel(for: transcriber)
            return
        }
        let transcriber = try await makeDictationTranscriber(
            locale: locale,
            preset: .shortDictation
        )
        try await ensureModel(for: transcriber)
    }

    static func transcribe(
        audioURL: URL,
        locale: Locale,
        context: SpeechRecognitionContext = .empty
    ) async throws -> String {
        let metadataFile = try AVAudioFile(forReading: audioURL)
        let duration = Double(metadataFile.length)
            / metadataFile.processingFormat.sampleRate
        if let transcriber = await makeSpeechTranscriber(locale: locale) {
            do {
                try await ensureModel(for: transcriber)
                return try await transcribe(
                    file: AVAudioFile(forReading: audioURL),
                    with: transcriber
                )
            } catch {
                Log.info(
                    "[AppleSpeech] SpeechTranscriber failed, trying compatible dictation: "
                        + error.localizedDescription
                )
            }
        }

        let transcriber = try await makeDictationTranscriber(
            locale: locale,
            preset: dictationPreset(forDuration: duration)
        )
        try await ensureModel(for: transcriber)
        return try await transcribe(
            file: AVAudioFile(forReading: audioURL),
            with: transcriber,
            context: context
        )
    }

    static func dictationPreset(
        forDuration duration: TimeInterval
    ) -> DictationTranscriber.Preset {
        duration > 60 ? .longDictation : .shortDictation
    }

    private static func transcribe(
        file: AVAudioFile,
        with transcriber: SpeechTranscriber
    ) async throws -> String {
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
        let resultTask = Task<String, Error> {
            var transcript = ""
            for try await result in transcriber.results where result.isFinal {
                transcript += String(result.text.characters)
            }
            return transcript
        }
        return try await analyze(file: file, with: analyzer, resultTask: resultTask)
    }

    private static func transcribe(
        file: AVAudioFile,
        with transcriber: DictationTranscriber,
        context: SpeechRecognitionContext
    ) async throws -> String {
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
        if !context.phrases.isEmpty {
            let analysisContext = AnalysisContext()
            analysisContext.contextualStrings[.general] = context.phrases
            try await analyzer.setContext(analysisContext)
        }
        let resultTask = Task<String, Error> {
            var transcript = ""
            for try await result in transcriber.results where result.isFinal {
                transcript += String(result.text.characters)
            }
            return transcript
        }
        return try await analyze(file: file, with: analyzer, resultTask: resultTask)
    }

    private static func analyze(
        file: AVAudioFile,
        with analyzer: SpeechAnalyzer,
        resultTask: Task<String, Error>
    ) async throws -> String {
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

    private static func makeSpeechTranscriber(
        locale: Locale
    ) async -> SpeechTranscriber? {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(
                equivalentTo: locale
              ) else {
            return nil
        }
        return SpeechTranscriber(locale: supported, preset: .transcription)
    }

    private static func makeDictationTranscriber(
        locale: Locale,
        preset: DictationTranscriber.Preset
    ) async throws -> DictationTranscriber {
        guard let supported = await DictationTranscriber.supportedLocale(
            equivalentTo: locale
        ) else {
            throw AppleSpeechAnalyzerError.unsupportedLocale(locale.identifier)
        }
        return DictationTranscriber(locale: supported, preset: preset)
    }

    private static func ensureModel(for module: any SpeechModule) async throws {
        let modules = [module]
        if await AssetInventory.status(forModules: modules) == .installed { return }
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: modules
        ) {
            try await request.downloadAndInstall()
        }
        guard await AssetInventory.status(forModules: modules) == .installed else {
            throw AppleSpeechAnalyzerError.modelUnavailable
        }
    }
}

enum AppleSpeechAnalyzerError: LocalizedError {
    case unsupportedLocale(String)
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let locale):
            return "SpeechAnalyzer does not support locale \(locale)"
        case .modelUnavailable:
            return "SpeechAnalyzer model is not installed"
        }
    }
}

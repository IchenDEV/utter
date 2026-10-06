import UtterContracts
import AVFoundation
import Foundation
@preconcurrency import Speech

package enum AppleSpeechAnalyzer {
    package static func isModelInstalled(locale: Locale) async -> Bool {
        if let transcriber = await makeSpeechTranscriber(locale: locale) {
            return await AssetInventory.status(forModules: [transcriber]) == .installed
        }
        guard let transcriber = try? await makeDictationTranscriber(locale: locale, preset: .shortDictation) else { return false }
        return await AssetInventory.status(forModules: [transcriber]) == .installed
    }

    package static func prepare(locale: Locale) async throws {
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

    package static func transcribe(
        audioURL: URL,
        locale: Locale,
        context: SpeechRecognitionContext = .empty,
        allowAssetInstallation: Bool = true,
        log: Log
    ) async throws -> String {
        let metadataFile = try AVAudioFile(forReading: audioURL)
        let duration = Double(metadataFile.length)
            / metadataFile.processingFormat.sampleRate
        if let transcriber = await makeSpeechTranscriber(locale: locale) {
            do {
                try await ensureModel(for: transcriber, allowDownload: allowAssetInstallation)
                return try await transcribe(
                    file: AVAudioFile(forReading: audioURL),
                    with: transcriber,
                    context: context
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                log.info(
                    "[AppleSpeech] SpeechTranscriber failed, trying compatible dictation: "
                        + error.localizedDescription
                )
            }
        }

        let transcriber = try await makeDictationTranscriber(
            locale: locale,
            preset: dictationPreset(forDuration: duration)
        )
        try await ensureModel(for: transcriber, allowDownload: allowAssetInstallation)
        return try await transcribe(
            file: AVAudioFile(forReading: audioURL),
            with: transcriber,
            context: context
        )
    }

    package static func dictationPreset(
        forDuration duration: TimeInterval
    ) -> DictationTranscriber.Preset {
        duration > 60 ? .longDictation : .shortDictation
    }

    private static func transcribe(
        file: AVAudioFile,
        with transcriber: SpeechTranscriber,
        context: SpeechRecognitionContext
    ) async throws -> String {
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
        try await apply(context, to: analyzer)
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
        try await apply(context, to: analyzer)
        let resultTask = Task<String, Error> {
            var transcript = ""
            for try await result in transcriber.results where result.isFinal {
                transcript += String(result.text.characters)
            }
            return transcript
        }
        return try await analyze(file: file, with: analyzer, resultTask: resultTask)
    }

    private static func apply(
        _ context: SpeechRecognitionContext,
        to analyzer: SpeechAnalyzer
    ) async throws {
        guard !context.phrases.isEmpty else { return }
        let analysisContext = AnalysisContext()
        analysisContext.contextualStrings[.general] = context.phrases
        try await analyzer.setContext(analysisContext)
    }

    private static func analyze(
        file: AVAudioFile,
        with analyzer: SpeechAnalyzer,
        resultTask: Task<String, Error>
    ) async throws -> String {
        try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                if let lastSample = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: lastSample)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                let text = try await resultTask.value
                try Task.checkCancellation()
                return text
            } catch {
                resultTask.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            resultTask.cancel()
            Task { await analyzer.cancelAndFinishNow() }
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

    private static func ensureModel(for module: any SpeechModule, allowDownload: Bool = true) async throws {
        try Task.checkCancellation()
        let modules = [module]
        if await AssetInventory.status(forModules: modules) == .installed { return }
        guard allowDownload else { throw AppleSpeechAnalyzerError.modelUnavailable }
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: modules
        ) {
            try await withTaskCancellationHandler {
                do { try await request.downloadAndInstall() }
                catch { try Task.checkCancellation(); throw error }
                try Task.checkCancellation()
            } onCancel: { request.progress.cancel() }
        }
        guard await AssetInventory.status(forModules: modules) == .installed else {
            throw AppleSpeechAnalyzerError.modelUnavailable
        }
    }
}

enum AppleSpeechAnalyzerError: LocalizedError {
    case unsupportedLocale(String)
    case modelUnavailable

    package var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let locale):
            return "SpeechAnalyzer does not support locale \(locale)"
        case .modelUnavailable:
            return "SpeechAnalyzer model is not installed"
        }
    }
}

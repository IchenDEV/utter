import Foundation
import UtterContracts
import UtterEvaluation
import UtterMediaContracts
import UtterModels
import UtterMLX
import UtterRuntime

@MainActor
struct EvaluationAudio {
    let selection: SpeechEvaluationSelection?
    let files: [String: URL]

    static func validateModel(_ arguments: VoiceEvaluationArguments, samples: [VoiceEvaluationCase]) throws {
        guard samples.contains(where: { $0.audio_file != nil }) else { return }
        guard let speech = arguments.speech else { throw VoiceEvaluationError.unavailableAudioProvider }
        if speech.type == .whisper {
            guard ModelAssets.whisperModelIsComplete(at: speech.model),
                  (try? WhisperTokenizerAssets.read(at: speech.model, expectedModel: speech.modelID)) != nil else {
                throw GenerationServiceError.modelUnavailable
            }
        } else {
            guard let artifact = MLXModelArtifacts.speech.first(where: { $0.id == speech.modelID }),
                  ModelAssets.speechModelIsComplete(at: speech.model, requiredFiles: artifact.requiredFiles) else {
                throw GenerationServiceError.modelUnavailable
            }
        }
    }

    init(arguments: VoiceEvaluationArguments, samples: [VoiceEvaluationCase], runtime: PluginRuntime) throws {
        selection = arguments.speech
        let inspector = try runtime.service(AudioServices.files)
        var files: [String: URL] = [:]
        for sample in samples {
            guard let path = sample.audio_file else { continue }
            let url = (path.hasPrefix("/") ? URL(fileURLWithPath: path)
                : arguments.corpus.deletingLastPathComponent().appendingPathComponent(path))
                .standardizedFileURL.resolvingSymlinksInPath()
            guard url != arguments.output, url != arguments.output.appendingPathExtension("manifest.json") else {
                throw VoiceEvaluationError.invalidArguments("output overlaps an input audio file")
            }
            let metadata = try inspector.inspect(url)
            guard metadata.frameCount > 0, metadata.sampleRate.isFinite, metadata.sampleRate > 0,
                  metadata.channels > 0, metadata.channels <= 8,
                  Double(metadata.frameCount) / metadata.sampleRate <= 600 else {
                throw VoiceEvaluationError.invalidCase(sample.id)
            }
            files[sample.id] = url
        }
        self.files = files
    }

    func transcript(_ sample: VoiceEvaluationCase, request: ProcessingRequest, runtime: PluginRuntime) async throws -> String {
        guard let url = files[sample.id] else { return sample.text }
        guard let selection else { throw VoiceEvaluationError.unavailableAudioProvider }
        let speech = try runtime.service(SpeechServices.providers)
        guard let descriptor = speech.descriptors.first(where: { $0.id == selection.providerID }) else {
            throw VoiceEvaluationError.unavailableAudioProvider
        }
        let selected = SpeechSelection(providerID: descriptor.id, type: selection.type, model: selection.modelID,
            modelPath: selection.model.path)
        let files = FrozenModelFiles(modelID: selection.modelID, using: try runtime.service(ModelServices.files))
        let engine = try await speech.create(id: descriptor.id, request: SpeechProviderRequest(selection: selected, modelFiles: files))
        engine.configureRecognition(context: SpeechRecognitionContext(phrases: descriptor.recognitionVocabulary == .personal
            ? request.dictionary.personalRecognitionPhrases : request.dictionary.recognitionPhrases))
        do {
            await engine.prepare()
            try Task.checkCancellation()
            guard engine.isReady else { throw IntegrationError.modelNotReady }
            guard try await runtime.service(AudioServices.evidence).containsSpeech(at: url) else {
                throw IntegrationError.noSpeechDetected
            }
            let raw = try await engine.transcribe(audioURL: url, language: request.options.inputLanguage.whisperCode)
            try Task.checkCancellation()
            guard let text = try runtime.service(ProcessingServices.preparation).transcript(raw, activity: nil,
                recognitionPhrases: request.dictionary.recognitionPhrases) else { throw IntegrationError.noSpeechDetected }
            await engine.drainRecognition()
            return text
        } catch {
            engine.cancelListening()
            await Task { await engine.drainRecognition() }.value
            throw error
        }
    }
}

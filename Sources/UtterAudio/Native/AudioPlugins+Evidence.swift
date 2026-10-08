import Foundation
import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension AudioPlugins {
    package static func files() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "audio.files", provides: [AudioServices.files.reference])) { context, _ in
            try context.provide(AudioServices.files, value: BorrowedAudioFileService(isCurrent: { context.isCurrent }))
        }
    }

    package static func speechEvidence() -> PluginRegistration {
        speechEvidence { url, log in await SpeechActivityClassifier.containsSpeech(at: url, diagnostics: log) }
    }

    static func speechEvidence(classify: @escaping (URL?, Log) async -> Bool) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "audio.speech-evidence", requires: [IntegrationServices.diagnostics.required],
            provides: [AudioServices.evidence.reference]
        )) { context, _ in
            let log = Log(service: try context.require(IntegrationServices.diagnostics))
            let service = ScopedSpeechEvidenceService(isCurrent: { context.isCurrent }) { await classify($0, log) }
            try context.scope.onRevoke { service.revoke() }
            try context.scope.onDispose { await service.close() }
            try context.provide(AudioServices.evidence, value: service)
        }
    }
}

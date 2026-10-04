import Foundation
import UtterContracts
import UtterRuntime
import UtterData
import UtterModels
import UtterSession
import UtterProcessing
import UtterAudio
import UtterMacServices
import UtterRemoteMic
import UtterAppleSpeech
import UtterWhisper
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import UtterPresentation

@MainActor
package enum BuiltinPlugins {
    package static func registrations(defaults: UserDefaults, directory: URL,
                                     settings: any SettingsService,
                                     configuration: @escaping () throws -> any ConfigurationService,
                                     additional: [PluginRegistration] = [],
                                     replacements: [PluginRegistration] = []) throws -> [PluginRegistration] {
        let diagnostics = SystemDiagnostics()
        let data = [
            DataPlugins.settings { settings }, DataPlugins.credentials(), DataPlugins.notifications(),
            DataPlugins.diagnostics(diagnostics), DataPlugins.integrationClients(defaults: defaults),
            DataPlugins.configuration(makeService: configuration), DataPlugins.dictionary(directoryURL: directory),
            DataPlugins.lexicons(), DataPlugins.history(directoryURL: directory, reportError: diagnostics.error),
            DataPlugins.memory(), DataPlugins.correctionClassification(),
        ]
        let models = [ModelPlugins.artifacts(), ModelPlugins.resourceAccess(), ModelPlugins.files(),
                      ModelPlugins.speechProviders(), ModelPlugins.textProviders(), ModelPlugins.imageProviders(),
                      MLXPlugins.modelDownloads(), ModelPlugins.catalog(), ModelPlugins.storage(), ModelPlugins.lifecycle()]
        let inference = [AppleSpeechPlugins.speech(), WhisperPlugins.speech(), RemoteInferencePlugins.speech(),
                         MLXPlugins.qwenSpeech(), MLXPlugins.fireredSpeech(), MLXPlugins.megaSpeech(),
                         MLXPlugins.text(), MLXPlugins.image(), ANEPlugins.text(), RemoteInferencePlugins.text()]
        let processing = [ProcessingPlugins.preparation(), ProcessingPlugins.text(), ModePlugins.recipes(),
                          ModePlugins.direct(), ModePlugins.formatting(), ModePlugins.command(),
                          ModePlugins.translation(), ModePlugins.edit()]
        let platform = [RemoteMicPlugins.capture(), AudioPlugins.capture(), AudioPlugins.files(), AudioPlugins.speechEvidence(), AudioPlugins.devices(),
                        MacPlugins.target(), MacPlugins.output(), MacPlugins.screen(), MacPlugins.hotkeys(),
                        MacPlugins.sounds(), MacPlugins.loginItem(), MacPlugins.correction()]
        let session = [SessionPlugins.outputs(), SessionPlugins.voiceWorkflows(), SessionPlugins.execution(), SessionPlugins.api()]
        let ingress = [IngressPlugins.hotkeySessions(), IngressPlugins.remoteSessions(), IngressPlugins.http(), IngressPlugins.xpc()]
        let presentation = [PresentationPlugins.catalog(), PresentationPlugins.icons(), PresentationPlugins.menu(),
            PresentationPlugins.overlay(), PresentationPlugins.desktop(), PresentationPlugins.general(), PresentationPlugins.history(),
            PresentationPlugins.models(), PresentationPlugins.style(), PresentationPlugins.integrations(), PresentationPlugins.about(),
            PresentationPlugins.onboarding(), PresentationPlugins.configuration()]
        return try BuiltinRegistrationPolicy.replacing(data + models + inference + processing + platform + session + ingress + presentation + additional,
                                                     with: replacements)
    }
}

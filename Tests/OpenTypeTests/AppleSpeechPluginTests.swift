import UtterPresentationContracts
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Speech
import XCTest
import UtterAppleSpeech
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterModels
import UtterRuntime

@MainActor
final class AppleSpeechPluginTests: XCTestCase {
    func testRegistrationPublishesMetadataWithoutChangingSpeechAuthorization() async throws {
        let before = SFSpeechRecognizer.authorizationStatus()
        let runtime = PluginRuntime(catalog: try PluginCatalog([
            ModelPlugins.speechProviders(),
            DataPlugins.diagnostics(SystemDiagnostics()),
            AppleSpeechPlugins.speech(),
        ]))
        try await runtime.start([
            PluginSelection("speech.apple"),
            PluginSelection("data.diagnostics"),
            PluginSelection("models.speech-providers"),
        ])
        let providers = try runtime.service(SpeechServices.providers)
        XCTAssertEqual(providers.descriptors.map(\.id), ["speech.apple"])
        XCTAssertEqual(try runtime.service(SpeechServices.apple).legacyIDs, ["apple"])
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), before)
        try await runtime.stop()
        XCTAssertTrue(providers.descriptors.isEmpty)
    }
}

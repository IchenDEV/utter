import UtterData
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import UtterContracts
import UtterMediaContracts
import UtterModels
import UtterProcessing
import UtterPresentationContracts

extension TextProcessor {
    convenience init(
        providers: (any ProviderCatalog<GenerationPurpose, any TextGenerationService>)? = nil,
        imageProviders: (any ProviderCatalog<GenerationPurpose, any ImageGenerationService>)? = nil,
        access: (any ModelResourceAccess)? = nil, files: (any ModelFilesService)? = nil
    ) {
        let access = access ?? LocalModelAccessGate()
        let files = files ?? LiveModelFiles()
        let log = UtterContracts.Log(service: TestDiagnostics.service)
        let text: any ProviderCatalog<GenerationPurpose, any TextGenerationService>
        let images: (any ProviderCatalog<GenerationPurpose, any ImageGenerationService>)?
        if let providers {
            text = providers
            images = imageProviders
        } else {
            let builtins = TestGenerationServices(access: access, files: files, log: log)
            text = builtins.text
            images = imageProviders ?? builtins.image
        }
        self.init(
            providers: text, imageProviders: images,
            access: access, files: files,
            settings: { AppSettings.shared.snapshot },
            dictionary: { PersonalDictionary.shared.snapshot(settings: .shared) }, log: log
        )
    }
}

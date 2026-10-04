import Foundation
import WhisperKit
import UtterContracts
import UtterPresentationContracts

extension ModelCatalog {
    package func repairSelectedModels() {
        let resolvedWhisperModel = WhisperModelSelection.resolve(
            requested: settings.whisperModel,
            available: whisperModels.map(\.id),
            fallback: WhisperKit.recommendedModels().default
        )
        if settings.whisperModel != resolvedWhisperModel {
            settings.whisperModel = resolvedWhisperModel
        }

        if !llmModels.contains(where: { $0.id == settings.llmModel }) {
            settings.llmModel = llmModels.first(where: {
                $0.id == AppSettings.defaultLLMModelID
            })?.id ?? llmModels.first?.id ?? ""
        }

        if !asrModels.contains(where: { $0.id == settings.qwenASRModel }) {
            settings.qwenASRModel = QwenASRModel.defaultID
        }
    }
}

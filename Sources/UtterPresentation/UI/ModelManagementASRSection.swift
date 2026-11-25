import UtterPresentationContracts
import UtterContracts
import SwiftUI

extension ModelManagementView {
    var qwenASRSection: some View {
        let engineType = settings.speechEngine
        let models = catalog.asrModels(for: engineType)
        let activeID = engineType == .qwen3
            ? settings.qwenASRModel
            : (engineType.asrModelID ?? settings.qwenASRModel)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L(engineType == .audio8 ? "audio8_asr.config_hint" : "qwen_asr.config_hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            modelList(models, activeID: activeID, type: .asr)
            if engineType == .audio8 {
                Link(L("model.audio8_license"), destination: URL(
                    string: "https://huggingface.co/Edge0/Audio8-ASR-0.1B/blob/\(Audio8ASRModel.revision)/LICENSE"
                )!)
                .font(.system(size: 10))
            }
            if engineType == .qwen3 {
                HStack(spacing: 12) {
                    Link(L("model.confucius_license"), destination: URL(
                        string: "https://huggingface.co/mlx-community/Confucius4-R2T2-8bit/blob/main/MODEL_LICENSE_zh"
                    )!)
                    Link(L("model.confucius_english_license"), destination: URL(
                        string: "https://huggingface.co/mlx-community/Confucius4-R2T2-8bit/blob/main/LICENSE"
                    )!)
                    Link(L("model.confucius_notice"), destination: URL(
                        string: "https://huggingface.co/mlx-community/Confucius4-R2T2-8bit/blob/main/NOTICE"
                    )!)
                }
                .font(.system(size: 10))
            }
        }
    }
}

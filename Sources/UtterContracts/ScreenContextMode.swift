import Foundation

package enum ScreenContextMode: String, Codable, CaseIterable {
    case ocr = "ocr"
    case multimodal = "multimodal"

    package static func effectiveCaptureMode(
        preference: ScreenContextMode,
        useRemoteLLM: Bool,
        modelID: String
    ) -> ScreenContextMode {
        guard preference == .multimodal,
              !useRemoteLLM,
              supportsScreenImageContext(modelID: modelID)
        else {
            return .ocr
        }
        return .multimodal
    }

    package static func supportsScreenImageContext(modelID: String) -> Bool {
        let id = modelID.lowercased()
        return id.contains("gemma-4")
            || id.contains("gemma4")
            || id.contains("gemma_4")
            || id.contains("-vl")
            || id.contains("_vl")
            || id.contains("paligemma")
            || id.contains("smolvlm")
            || id.contains("fastvlm")
            || id.contains("pixtral")
            || id.contains("idefics")
    }

    package var label: String {
        switch self {
        case .ocr: return L("screen_context_mode.ocr")
        case .multimodal: return L("screen_context_mode.multimodal")
        }
    }
}

import SwiftUI

extension ModelManagementView {
    var enginePickerSection: some View {
        Picker(L("settings.speech_engine"), selection: $settings.speechEngine) {
            ForEach(SpeechEngineType.selectableCases, id: \.self) { engine in
                Text(engine.pickerTitle)
                    .tag(engine)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

private extension SpeechEngineType {
    var pickerTitle: String {
        switch self {
        case .whisper: return L("engine.whisper_short")
        case .apple: return L("engine.apple_short")
        case .volc: return L("engine.volc_short")
        case .qwen3:
            return "\(L("engine.qwen3_short")) · \(L("common.recommended_short"))"
        case .mimo: return L("engine.mimo_short")
        }
    }

}

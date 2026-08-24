import SwiftUI
import AppKit

extension ModelManagementView {
    var enginePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("model.speech_recognition"), systemImage: "waveform")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(L("settings.speech_engine"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                speechEnginePicker
            }
        }
    }

    private var speechEnginePicker: some View {
        HStack(spacing: 0) {
            ForEach(SpeechEngineType.selectableCases, id: \.self) { engine in
                speechEngineButton(engine)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func speechEngineButton(_ engine: SpeechEngineType) -> some View {
        let isSelected = settings.speechEngine == engine

        return Button {
            settings.speechEngine = engine
        } label: {
            VStack(spacing: 2) {
                Image(systemName: engine.pickerIcon)
                    .font(.system(size: 14))

                Text(engine.pickerTitle)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .foregroundStyle(
            isSelected
                ? Color.accentColor
                : Color.primary
        )
        .help(engine.label)
    }
}

private extension SpeechEngineType {
    var pickerTitle: String {
        switch self {
        case .whisper: return L("engine.whisper_short")
        case .apple: return L("engine.apple_short")
        case .volc: return L("engine.volc_short")
        case .qwen3: return L("engine.qwen3_short")
        case .mimo: return L("engine.mimo_short")
        }
    }

    var pickerIcon: String {
        switch self {
        case .whisper: return "waveform"
        case .apple: return "apple.logo"
        case .volc: return "cloud.bolt.fill"
        case .qwen3: return "q.circle.fill"
        case .mimo: return "m.circle.fill"
        }
    }
}

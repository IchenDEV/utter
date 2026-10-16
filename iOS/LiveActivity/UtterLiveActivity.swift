import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents
import UtterKeyboardBridge

@main
struct UtterWidgets: WidgetBundle {
    var body: some Widget { UtterLiveActivity() }
}

struct UtterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceActivity.self) { context in
            HStack {
                Text(L("ios.phase.\(context.state.phase)"))
                Spacer()
                controls(context.attributes.requestID, phase: context.state.phase)
            }.padding().tint(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Text(L("ios.phase.\(context.state.phase)")) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack { controls(context.attributes.requestID, phase: context.state.phase) }.tint(.primary)
                }
            } compactLeading: { Image(systemName: "mic.fill") }
            compactTrailing: { Text("Utter").font(.caption) }
            minimal: { Image(systemName: "mic.fill") }
        }
    }

    @ViewBuilder private func controls(_ requestID: UUID, phase: String) -> some View {
        Button(intent: StopVoiceIntent(requestID: requestID)) { Text(L("ios.action.stop")) }
            .disabled(phase != "recording")
            .accessibilityIdentifier("activity.stop")
        Button(intent: StopVoiceIntent(requestID: requestID, cancel: true)) { Text(L("ios.action.cancel")) }
            .accessibilityIdentifier("activity.cancel")
    }
}

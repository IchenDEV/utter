import SwiftUI
import UtterKeyboardBridge

#if DEBUG && targetEnvironment(simulator)
@MainActor
final class KeyboardState: ObservableObject {
    @Published var status: VoiceStatus?
    @Published var lease: KeyboardLease?
    @Published var errorKey: String?
    @Published var pending = false
}

@MainActor
struct KeyboardView: View {
    @ObservedObject var state: KeyboardState
    let prepare: (UUID, VoiceAction, KeyboardLease) -> Bool
    let insert: () -> Void
    let edit: (String?) -> Void
    @State private var nonce = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("模拟器唤醒实验。此按钮会打开主 App，不录音。")
            Link("打开 Utter 主 App", destination: URL(string: "utter-wake-probe://activate?nonce=\(nonce.uuidString)")!)
                .accessibilityIdentifier("wake.link").accessibilityValue(nonce.uuidString)
                .padding(.vertical, 12)
        }.padding(16).tint(.primary)
    }
}
#else
#error("Wake keyboard is restricted to Debug simulator builds")
#endif

import SwiftUI

@main
@MainActor
struct WakeHostApp: App {
    var body: some Scene { WindowGroup { WakeHostView() } }
}

private struct WakeHostView: View {
    private enum Field: String, Hashable { case first, second }
    @FocusState private var focus: Field?
    @State private var first = "Wake sample"
    @State private var second = "Other sample"
    var body: some View {
        NavigationStack {
            Form {
                Text("只使用固定文字的模拟器测试。")
                Text(focus?.rawValue ?? "none").accessibilityIdentifier("host.focus")
                TextField("第一输入框", text: $first).focused($focus, equals: .first)
                    .accessibilityIdentifier("host.first")
                TextField("第二输入框", text: $second).focused($focus, equals: .second)
                    .accessibilityIdentifier("host.second")
                Link("主 App URL 对照", destination: URL(string: "utter-wake-probe://activate?nonce=11111111-1111-4111-8111-111111111111")!)
                    .accessibilityIdentifier("host.control")
            }.navigationTitle("Wake Host").navigationBarTitleDisplayMode(.inline)
                .scrollEdgeEffectHidden().tint(.primary)
        }
    }
}

import SwiftUI

#if DEBUG && targetEnvironment(simulator)
@main
@MainActor
struct WakeProbeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var processID = UUID()
    @State private var nonce = ""
    @State private var count = 0
    @State private var callbackTime = 0.0
    @State private var saveError = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Text("模拟器唤醒实验。此版本不录音。")
                    Text("URL 回调：\(nonce.isEmpty ? "未收到" : "已收到")")
                    Text(nonce).accessibilityIdentifier("wake.nonce")
                    Text(String(count)).accessibilityIdentifier("wake.count")
                    Text(processID.uuidString).accessibilityIdentifier("wake.process")
                    Text(String(ProcessInfo.processInfo.processIdentifier)).accessibilityIdentifier("wake.pid")
                    Text(scenePhase == .active ? "active" : "inactive").accessibilityIdentifier("wake.scene")
                    if saveError { Text("诊断回执保存失败").accessibilityIdentifier("wake.error") }
                }
                .navigationTitle("Utter 唤醒实验").navigationBarTitleDisplayMode(.inline)
                .scrollEdgeEffectHidden().tint(.primary)
                .onOpenURL { url in
                    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          components.scheme == "utter-wake-probe", components.host == "activate",
                          let value = components.queryItems?.first(where: { $0.name == "nonce" })?.value,
                          let id = UUID(uuidString: value) else { return }
                    nonce = id.uuidString
                    count += 1
                    callbackTime = Date().timeIntervalSince1970
                    saveReceipt()
                }
                .onChange(of: scenePhase) { if !nonce.isEmpty { saveReceipt() } }
            }
        }
    }

    private func saveReceipt() {
        do {
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            let receipt: [String: Any] = ["nonce": nonce, "count": count, "process": processID.uuidString,
                "pid": ProcessInfo.processInfo.processIdentifier, "callbackTime": callbackTime,
                "scene": scenePhase == .active ? "active" : "inactive", "savedAt": Date().timeIntervalSince1970]
            try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
                .write(to: directory.appendingPathComponent("wake-probe.json"), options: .atomic)
        } catch { saveError = true }
    }
}
#else
#error("Wake probe is restricted to Debug simulator builds")
#endif

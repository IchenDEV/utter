import SwiftUI
import UtterMobile
import UtterKeyboardBridge

@main
@MainActor
struct UtterPhoneApp: App {
    var body: some Scene { WindowGroup { MobileRootView(controller: VoiceHost.shared.controller, standby: VoiceHost.shared.standby) } }
}

private enum MobilePage: String, CaseIterable, Identifiable {
    case voice, models, settings
    var id: String { rawValue }
    var title: String { L("ios.tab.\(rawValue)") }
    var icon: String { switch self { case .voice: "mic"; case .models: "arrow.down.circle"; case .settings: "gearshape" } }
}

@MainActor
private struct MobileRootView: View {
    @ObservedObject var controller: MobileController
    @ObservedObject var standby: StandbyService
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: MobilePage? = .voice
    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List(MobilePage.allCases, selection: $selected) { page in
                        Group {
                            if dynamicTypeSize.isAccessibilitySize { Text(page.title) }
                            else { Label(page.title, systemImage: page.icon) }
                        }.tag(page)
                            .accessibilityIdentifier("tab.\(page.rawValue)")
                    }.navigationTitle("Utter")
                        .navigationSplitViewColumnWidth(min: dynamicTypeSize.isAccessibilitySize ? 320 : 280,
                                                       ideal: dynamicTypeSize.isAccessibilitySize ? 340 : 280, max: 380)
                } detail: { NavigationStack { page(selected ?? .voice) } }
            } else {
                TabView(selection: $selected) {
                    ForEach(MobilePage.allCases) { item in
                        NavigationStack { page(item) }
                            .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .tabBar)
                            .toolbarBackground(.visible, for: .tabBar)
                            .tabItem { Label(item.title, systemImage: item.icon) }
                            .tag(Optional(item))
                            .accessibilityIdentifier("tab.\(item.rawValue)")
                    }
                }
            }
        }
        .tint(.primary)
        .overlay(alignment: .bottomTrailing) {
            // Picture in Picture needs a visible source view; it is transparent and ignores touches.
            StandbySource(view: standby.sourceView).frame(width: 44, height: 44).allowsHitTesting(false).accessibilityHidden(true)
        }
        .onOpenURL { url in
            // The keyboard opens this link when voice standby is not running; activation needs the app in the foreground.
            if url.scheme == "utter", url.host == "standby" { Task { await standby.activate() } }
        }
        .task { await controller.prepareLibrary() }
        #if DEBUG
        // Debugger-free device experiments start standby without a tap; permissions must already be granted.
        .task { if ProcessInfo.processInfo.arguments.contains("--standby-autostart") { await standby.activate() } }
        #endif
        .onChange(of: scenePhase) { if scenePhase == .active { controller.refreshResult() } }
        #if DEBUG && targetEnvironment(simulator)
        .task(id: scenePhase) { if scenePhase == .active { await VoiceHost.shared.runSimulatorBridge() } }
        #endif
    }
    @ViewBuilder private func page(_ page: MobilePage) -> some View {
        switch page {
        case .voice: PhoneView(controller: controller, standby: standby)
        case .models: MobileModelsView(controller: controller)
        case .settings: MobileSettingsView(controller: controller)
        }
    }
}

@MainActor
struct PhoneView: View {
    @ObservedObject var controller: MobileController
    @ObservedObject var standby: StandbyService
    @State private var errorKey: String?
    @State private var firstField = ""
    @State private var secondField = ""
    @FocusState private var focusedField: Int?
    private var standbyFooterKey: String {
        switch standby.phase {
        case .unsupported: "ios.standby.unsupported"
        case .failed: "ios.standby.failed"
        case .active: "ios.standby.active"
        case .starting: "ios.local_description"
        default: controller.isEnabled ? "ios.standby.inactive" : "ios.local_description"
        }
    }
    var body: some View {
        ScrollViewReader { scroll in
            Form {
                Section {
                    VStack(spacing: 20) {
                        Text(L(controller.status.errorKey ?? "ios.phase.\(controller.status.phase.rawValue)"))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("voice.status").accessibilityValue(controller.status.phase.rawValue)
                        if controller.status.phase == .preparing || controller.status.phase == .processing {
                            ProgressView().frame(minHeight: 88).accessibilityLabel(L("ios.phase.preparing"))
                        } else {
                            Button {
                                Task {
                                    if controller.status.phase == .recording { await controller.stop() }
                                    else if !controller.isEnabled { await standby.activate() }
                                    else {
                                        do { try await VoiceHost.shared.startLocally() }
                                        catch { errorKey = "ios.error.live_activity" }
                                    }
                                }
                            } label: {
                                Image(systemName: controller.status.phase == .recording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 34, weight: .medium)).foregroundStyle(Color(uiColor: .systemBackground))
                                    .frame(width: 88, height: 88).background(Color(uiColor: .label), in: Circle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel(L(controller.status.phase == .recording ? "ios.action.stop" : controller.isEnabled ? "ios.action.record" : "ios.action.enable"))
                                .accessibilityIdentifier(controller.status.phase == .recording ? "voice.stop" : controller.isEnabled ? "voice.record" : "voice.enable")
                        }
                        Text(L(controller.status.phase == .recording ? "ios.tap_stop" : "ios.tap_speak"))
                            .font(.subheadline)
                        if controller.status.isBusy {
                            Button(L("ios.action.cancel")) { Task { await controller.cancel() } }.accessibilityIdentifier("voice.cancel")
                        } else if controller.isEnabled {
                            Button(L("ios.action.disable")) { Task { await standby.deactivate() } }.accessibilityIdentifier("voice.disable")
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 20)
                } footer: { mobileSectionFooter(standbyFooterKey, id: "voice.standby", value: standby.phase == .failed && !standby.diagnostic.isEmpty ? "failed|\(standby.diagnostic)" : standby.phase.name) }
                if !controller.status.text.isEmpty {
                    Section(L("ios.result")) {
                        Text(controller.status.text).textSelection(.enabled).accessibilityIdentifier("voice.result")
                        Button(L("ios.action.copy")) {
                            controller.refreshResult()
                            if !controller.status.text.isEmpty { UIPasteboard.general.string = controller.status.text }
                        }.accessibilityIdentifier("voice.copy")
                        Button(L("ios.action.discard"), role: .destructive) { controller.discardResult() }.accessibilityIdentifier("voice.discard")
                    }
                }
                Section {
                    TextField(L("ios.field.first"), text: $firstField, prompt: Text(L("ios.field.first")).foregroundColor(Color(uiColor: .label))).accessibilityIdentifier("field.first")
                        .focused($focusedField, equals: 1).id(1)
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--bridge-diagnostic") {
                        TextField(L("ios.field.second"), text: $secondField, prompt: Text(L("ios.field.second")).foregroundColor(Color(uiColor: .label))).accessibilityIdentifier("field.second")
                            .focused($focusedField, equals: 2).id(2)
                    }
                    #endif
                } header: { mobileSectionHeader("ios.try_keyboard") }
                Section {
                    Text(L("ios.keyboard_setup"))
                    Button(L("ios.action.settings"), action: openUtterSettings).accessibilityIdentifier("voice.settings")
                    NavigationLink(L("ios.dictionary")) { DictionaryView(controller: controller) }.accessibilityIdentifier("dictionary.open")
                } header: { mobileSectionHeader("ios.keyboard") }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--bridge-diagnostic") {
                    Section {
                        Text(L("ios.diagnostic_notice"))
                        Button(L("ios.diagnostic_enable")) { Task { try? await controller.enableBridgeDiagnostic(text: "Utter bridge sample") } }
                            .disabled(controller.isEnabled || controller.status.isBusy).accessibilityIdentifier("diagnostic.enable")
                    }
                }
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                if let focusedField { scroll.scrollTo(focusedField, anchor: .center) }
            }
        }
        .navigationTitle(L("ios.tab.voice"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("ios.error.title"), isPresented: Binding(get: { errorKey != nil }, set: { if !$0 { errorKey = nil } })) {
            Button(L("ios.action.ok")) { errorKey = nil }
        } message: { Text(L(errorKey ?? "ios.error.recognition")) }
    }
}

func mobileSectionHeader(_ key: String) -> some View {
    MobileSectionText(text: L(key), style: .headline, isHeader: true)
}

func mobileSectionFooter(_ key: String, id: String? = nil, value: String? = nil) -> some View {
    MobileSectionText(text: L(key), style: .footnote, isHeader: false, identifier: id, value: value)
}

private struct MobileSectionText: UIViewRepresentable {
    let text: String
    let style: UIFont.TextStyle
    let isHeader: Bool
    var identifier: String?
    var value: String?
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityTraits = isHeader ? [.staticText, .header] : .staticText
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.accessibilityIdentifier = identifier
        label.accessibilityValue = value
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: style)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        uiView.sizeThatFits(CGSize(width: proposal.width ?? 300, height: .greatestFiniteMagnitude))
    }
}

@MainActor
func openUtterSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}

import Foundation
import AppIntents
import UtterKeyboardBridge

struct StopVoiceIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "ios.action.stop"
    static var isDiscoverable = false
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }
    @Parameter(title: "ios.request") var requestID: String
    @Parameter(title: "ios.action.cancel") var cancel: Bool

    init() {}
    init(requestID: UUID, cancel: Bool = false) { self.requestID = requestID.uuidString; self.cancel = cancel }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if UTTER_MAIN
        guard let id = UUID(uuidString: requestID), VoiceHost.shared.controller.status.requestID == id else { throw BridgeError.invalidTarget }
        if cancel { await VoiceHost.shared.controller.cancel() }
        else { await VoiceHost.shared.controller.stop() }
        #else
        throw BridgeError.unavailable
        #endif
        return .result()
    }
}

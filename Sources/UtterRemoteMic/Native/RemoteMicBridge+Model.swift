import Foundation
import UtterContracts

extension XiaomiRemoteMicBridge {
    func handleModelNumber(_ data: Data?, attempt: UInt64) {
        guard handshake.accepts(attempt), !handshake.decoderConfigured else { return }
        var model: String?
        if let data {
            guard let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                failAttempt(reason: L("remote_mic.error.model_unreadable"))
                return
            }
            model = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lowFirst = RemoteMicDeviceMatcher.usesLowNibbleFirst(modelNumber: model)
        decoder.lowNibbleFirst = lowFirst
        diagnostics.modelNumber = model
        diagnostics.lowNibbleFirst = lowFirst
        handshake.markDecoderConfigured()
        finishInitializationIfReady()
    }
}

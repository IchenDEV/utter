#if os(iOS) && DEBUG
import Foundation

/// Debug-only hooks that let a launch argument exercise the real local rewrite model, which the simulator's
/// synthetic dictation does not reach.
extension MobileController {
    public func probeLoadPolishModel() async -> (error: String?, seconds: Double) {
        let start = Date()
        do { try await polishService.load(modelID: polishModel); return (nil, Date().timeIntervalSince(start)) }
        catch { return (String(describing: error), Date().timeIntervalSince(start)) }
    }

    public func probePolish(_ text: String, language: String) async -> (output: String?, seconds: Double) {
        let start = Date()
        let output = await polishService.polish(text, language: language, protectedTerms: [], modelID: polishModel)
        return (output, Date().timeIntervalSince(start))
    }
}
#endif

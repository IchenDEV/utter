import UtterRuntime

package protocol TextPreparationService: Sendable {
    func transcript(_ text: String, activity: AudioCaptureActivity?, recognitionPhrases: [String]) -> String?
    func preview(_ text: String, language: InputLanguage) -> String
    func format(text: String, context: InputContext?) -> TextFormatDecision
}

package enum ProcessingServices {
    package static let preparation = ServiceKey<any TextPreparationService>("processing.preparation")
}

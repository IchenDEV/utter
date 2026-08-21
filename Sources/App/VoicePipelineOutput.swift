struct VoicePipelineOutput {
    let text: String
    let context: InputContext
    let formatKind: TextFormatKind?

    init(text: String, context: InputContext, formatKind: TextFormatKind? = nil) {
        self.text = text
        self.context = context
        self.formatKind = formatKind
    }
}

enum VoicePipelineStop: Error {
    case noSpeech
}

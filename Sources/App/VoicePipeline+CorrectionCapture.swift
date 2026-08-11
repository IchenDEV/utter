import Foundation

@MainActor
extension VoicePipeline {
    func beginCorrectionCapture(
        recordID: UUID,
        insertedText: String,
        context: InputContext
    ) {
        guard appState.settings.enableCorrectionLearning,
              let seed = textInserter.correctionCaptureSeed(
                expectedText: insertedText,
                context: context
              ) else {
            return
        }
        correctionCapture.start(seed: seed, recordID: recordID)
    }
}

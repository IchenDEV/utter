import Foundation
import UtterContracts

package enum CommandOutputCleaner {
    package static func clean(_ text: String) -> String {
        if let finalText = LLMFinalTextOutput.text(from: text) {
            return FormattedOutputCleaner.clean(finalText)
        }
        let cleaned = FormattedOutputCleaner.clean(text)
        let prefix = "^(?:(?:好的|当然)[，,。.]?\\s*)?(?:以下是|下面是)(?:给您|给你|为您|为你)?(?:的)?(?:回复|回覆|答复|回信)[：:]\\s*|^(?:sure[,.]?\\s*)?here(?: is|'s) (?:the |a |your )?(?:reply|response)[:：]\\s*"
        return cleaned.replacingOccurrences(of: prefix, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

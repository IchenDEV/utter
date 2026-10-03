import Foundation
import UtterContracts
import UtterModels
import UtterPresentationContracts

typealias LiveModelFiles = ConfiguredModelFiles

extension ConfiguredModelFiles {
    init() {
        self.init(
            settings: { AppSettings.shared.snapshot },
            speechRequiredFiles: { ModelCatalog.asrRequiredFiles(for: $0) }
        )
    }
}

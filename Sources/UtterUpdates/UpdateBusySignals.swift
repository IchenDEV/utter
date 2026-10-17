import Foundation
import UtterContracts

enum UpdateBusySignals {
    /// A relaunch must not interrupt a model download, compile or load: the first costs
    /// bandwidth, the others minutes of work that restart from zero.
    static func isModelBusy(_ snapshot: ModelCatalogSnapshot) -> Bool {
        (snapshot.whisper + snapshot.text + snapshot.speech).contains { $0.status.isBusy }
    }
}

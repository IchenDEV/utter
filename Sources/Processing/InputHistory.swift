import UtterContracts
import UtterData
import UtterPresentationContracts

@MainActor
extension InputHistory {
    static let shared = InputHistory(service: HistoryStore(
        directoryURL: DataLocations.applicationSupport,
        retention: { AppSettings.shared.historyRetention },
        reportError: Log.error
    ))
}

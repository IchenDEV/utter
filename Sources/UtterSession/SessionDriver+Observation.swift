import Foundation
import UtterContracts

extension SessionDriver {
    package func observe(_ callback: @escaping (SessionExecutionSnapshot) -> Void) -> UUID {
        let id = UUID()
        if !closed { observers[id] = callback }
        return id
    }
    package func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    package func observeProgress(_ callback: @escaping (SessionIntent, SessionExecutionSnapshot) -> Void) -> UUID {
        let id = UUID()
        if !closed { progressObservers[id] = callback }
        return id
    }
    package func removeProgressObserver(_ id: UUID) { progressObservers.removeValue(forKey: id) }

    package func observeSettlement(_ callback: @escaping (SessionIntent, Result<SessionCompletion, Error>) -> Void) -> UUID {
        let id = UUID()
        if !closed { settlementObservers[id] = callback }
        return id
    }
    package func removeSettlementObserver(_ id: UUID) { settlementObservers.removeValue(forKey: id) }

}

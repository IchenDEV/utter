import Foundation
import UtterContracts

extension VoiceSessionJob {
    func attach(control: any SessionJobControl) {
        guard intent.clientID != nil, !revoked else { return }
        let check: @MainActor () async -> Void = { [weak self, weak control] in
            guard let self, let control, !self.revoked, control.isCurrent else { return }
            do { try self.authorize() }
            catch { control.cancel() }
        }
        let callbacks = callbacks
        settingsObservation = dependencies.settings.observe { _ in callbacks.enqueue(check) }
        credentialsObservation = dependencies.credentials.observe { _ in callbacks.enqueue(check) }
        clientObservation = dependencies.clients.observeAuthorization { callbacks.enqueue(check) }
        do { try authorize() }
        catch { control.cancel() }
    }

    func detachAuthorization() {
        if let settingsObservation { dependencies.settings.removeObserver(settingsObservation) }
        if let credentialsObservation { dependencies.credentials.removeObserver(credentialsObservation) }
        if let clientObservation { dependencies.clients.removeAuthorizationObserver(clientObservation) }
        settingsObservation = nil
        credentialsObservation = nil
        clientObservation = nil
    }
}

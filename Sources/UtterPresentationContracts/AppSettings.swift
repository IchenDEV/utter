import Foundation
import Combine
import SwiftUI
import UtterContracts

@dynamicMemberLookup
package final class AppSettings: ObservableObject {
    package static let defaultLLMModelID = SettingsValues.defaultLLMModelID

    private let service: any SettingsService
    private let credentials: (any CredentialsService)?
    private let subject: CurrentValueSubject<SettingsValues, Never>
    private var observation: UUID?
    private var credentialObservation: UUID?

    package init(service: any SettingsService, credentials: (any CredentialsService)? = nil) {
        self.service = service
        self.credentials = credentials
        subject = CurrentValueSubject(credentials?.snapshot.applying(to: service.values) ?? service.values)
        observation = service.observe { [weak self] _ in self?.publishSnapshot() }
        credentialObservation = credentials?.observe { [weak self] _ in self?.publishSnapshot() }
    }

    deinit {
        if let observation { service.removeObserver(observation) }
        if let credentialObservation { credentials?.removeObserver(credentialObservation) }
    }

    package var snapshot: SettingsValues { credentials?.snapshot.applying(to: service.values) ?? service.values }

    package subscript<Value>(dynamicMember key: KeyPath<SettingsValues, Value>) -> Value {
        snapshot[keyPath: key]
    }

    package subscript<Value>(dynamicMember key: WritableKeyPath<SettingsValues, Value>) -> Value {
        get { snapshot[keyPath: key] }
        set {
            if let credentials, Self.credentialKeys.contains(key) {
                var values = snapshot
                values[keyPath: key] = newValue
                let proposed = CredentialsSnapshot(settings: values)
                credentials.update { $0 = proposed }
            } else {
                service.update { $0[keyPath: key] = newValue }
            }
        }
    }

    package func publisher<Value: Equatable>(for key: KeyPath<SettingsValues, Value>) -> AnyPublisher<Value, Never> {
        subject.map { $0[keyPath: key] }.removeDuplicates().eraseToAnyPublisher()
    }

    package func resetDeveloperHTTPToken() {
        if let credentials { credentials.resetDeveloperHTTPToken() }
        else { service.resetDeveloperHTTPToken() }
    }

    private func publishSnapshot() {
        let values = snapshot
        guard values != subject.value else { return }
        objectWillChange.send()
        subject.send(values)
    }

    private static let credentialKeys: Set<AnyKeyPath> = [
        \SettingsValues.remoteAPIKey, \SettingsValues.volcAppKey,
        \SettingsValues.volcAccessKey, \SettingsValues.developerHTTPToken,
    ]
}

import Foundation
import Combine
import SwiftUI
import UtterContracts

@dynamicMemberLookup
package final class AppSettings: ObservableObject {
    package static let defaultLLMModelID = SettingsValues.defaultLLMModelID

    private let service: any SettingsService
    private let subject: CurrentValueSubject<SettingsValues, Never>
    private var observation: UUID?

    package init(service: any SettingsService) {
        self.service = service
        subject = CurrentValueSubject(service.values)
        observation = service.observe { [weak self] values in
            guard let self else { return }
            self.objectWillChange.send()
            self.subject.send(values)
        }
    }

    deinit {
        if let observation { service.removeObserver(observation) }
    }

    package var snapshot: SettingsValues { service.values }

    package subscript<Value>(dynamicMember key: KeyPath<SettingsValues, Value>) -> Value {
        service.values[keyPath: key]
    }

    package subscript<Value>(dynamicMember key: WritableKeyPath<SettingsValues, Value>) -> Value {
        get { service.values[keyPath: key] }
        set { service.update { $0[keyPath: key] = newValue } }
    }

    package func publisher<Value: Equatable>(for key: KeyPath<SettingsValues, Value>) -> AnyPublisher<Value, Never> {
        subject.map { $0[keyPath: key] }.removeDuplicates().eraseToAnyPublisher()
    }

    package func resetDeveloperHTTPToken() {
        service.resetDeveloperHTTPToken()
    }
}

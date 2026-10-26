import Foundation

package struct SelectionEditRemoteConsent: Equatable, Sendable {
    package let selectedText: String
    package let providerID: String
    package let providerBaseURL: String
    package let expiresAt: Date
    package var providerHost: String { URL(string: providerBaseURL)?.host ?? "" }
    package init(selectedText: String, providerID: String, providerBaseURL: String,
                 expiresAt: Date = Date().addingTimeInterval(120)) {
        self.selectedText = selectedText; self.providerID = providerID
        self.providerBaseURL = providerBaseURL; self.expiresAt = expiresAt
    }
    package func authorizes(selectedText: String, options: TextProcessingOptions) -> Bool {
        Date() < expiresAt && self.selectedText == selectedText
            && providerID == (options.textProviderID ?? "generation.remote")
            && providerBaseURL == options.remoteBaseURL
    }
}

package struct SelectionEditRemoteDisclosureRequired: LocalizedError {
    package let consent: SelectionEditRemoteConsent
    package let isTargetCurrent: @MainActor @Sendable () -> Bool
    package init(consent: SelectionEditRemoteConsent,
                 isTargetCurrent: @escaping @MainActor @Sendable () -> Bool) {
        self.consent = consent; self.isTargetCurrent = isTargetCurrent
    }
    package var errorDescription: String? { L("selection_edit.remote_disclosure_required") }
}

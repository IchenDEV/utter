import AppKit
import ApplicationServices
import Foundation

struct CorrectionCaptureSeed {
    let processIdentifier: pid_t
    let element: AXUIElement
    let insertedText: String
    let locator: CorrectionCaptureRegionLocator
    let context: InputContext
}

@MainActor
final class CorrectionCaptureService {
    private static let lifetime: TimeInterval = 60
    private var activeSession: ActiveCorrectionCapture?
    private var observer: AXObserver?
    private var monitorTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    func start(seed: CorrectionCaptureSeed, recordID: UUID) {
        finishCurrentSession()
        guard AppSettings.shared.enableCorrectionLearning,
              CorrectionCapturePrivacyPolicy.isEligible(
                bundleIdentifier: seed.context.bundleIdentifier,
                appName: seed.context.appName,
                element: seed.element
              ) else {
            return
        }

        activeSession = ActiveCorrectionCapture(
            seed: seed,
            recordID: recordID,
            expiresAt: Date().addingTimeInterval(Self.lifetime),
            latestFinalText: seed.insertedText
        )
        installObserver(for: seed)
        startMonitor()
    }

    func finishCurrentSession() {
        guard AppSettings.shared.enableCorrectionLearning else {
            tearDown()
            return
        }
        captureLatestValue()
        guard let session = activeSession else {
            tearDown()
            return
        }
        if session.latestFinalText != session.seed.insertedText,
           let candidate = CorrectionCandidateClassifier.candidate(
                inserted: session.seed.insertedText,
                userFinal: session.latestFinalText,
                sourceRecordID: session.recordID,
                languageCode: session.seed.context.inputLanguage.whisperCode
                    ?? session.seed.context.inputLanguage.rawValue,
                bundleIdentifier: session.seed.context.bundleIdentifier
           ) {
            PersonalDictionary.shared.recordLearnedCandidate(candidate)
            Log.info("[CorrectionCapture] learned candidate \(candidate.original.count)->\(candidate.replacement.count) chars")
        }
        tearDown()
    }

    func cancelCurrentSession() {
        tearDown()
    }

    fileprivate func handleValueChanged(_ element: AXUIElement) {
        guard let session = activeSession, CFEqual(session.seed.element, element) else { return }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.captureLatestValue()
        }
    }
}

private extension CorrectionCaptureService {
    struct ActiveCorrectionCapture {
        let seed: CorrectionCaptureSeed
        let recordID: UUID
        let expiresAt: Date
        var latestFinalText: String
    }

    func installObserver(for seed: CorrectionCaptureSeed) {
        var createdObserver: AXObserver?
        guard AXObserverCreate(
            seed.processIdentifier,
            correctionCaptureObserverCallback,
            &createdObserver
        ) == .success,
              let createdObserver else {
            Log.info("[CorrectionCapture] AX observer unavailable; using bounded polling")
            return
        }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(
            createdObserver,
            seed.element,
            kAXValueChangedNotification as CFString,
            pointer
        ) == .success else {
            Log.info("[CorrectionCapture] value notification unavailable; using bounded polling")
            return
        }
        observer = createdObserver
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(createdObserver),
            .commonModes
        )
    }

    func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self, let session = self.activeSession else { return }
                guard AppSettings.shared.enableCorrectionLearning else {
                    self.cancelCurrentSession()
                    return
                }
                if Date() >= session.expiresAt {
                    self.finishCurrentSession()
                    return
                }
                let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                if frontPID != session.seed.processIdentifier
                    || !CorrectionCaptureAX.isFocused(session.seed.element, pid: session.seed.processIdentifier) {
                    self.finishCurrentSession()
                    return
                }
                self.captureLatestValue()
            }
        }
    }

    func captureLatestValue() {
        guard var session = activeSession,
              let documentText = CorrectionCaptureAX.stringValue(
                of: session.seed.element,
                attribute: kAXValueAttribute as CFString
              ),
              let edited = session.seed.locator.editedText(in: documentText),
              let associated = CorrectionObservationPolicy.associatedFinalText(
                inserted: session.seed.insertedText,
                edited: edited
              ) else {
            return
        }
        session.latestFinalText = associated
        activeSession = session
        InputHistory.shared.updateUserFinalText(recordID: session.recordID, text: associated)
    }

    func tearDown() {
        monitorTask?.cancel()
        debounceTask?.cancel()
        monitorTask = nil
        debounceTask = nil
        if let observer, let session = activeSession {
            AXObserverRemoveNotification(
                observer,
                session.seed.element,
                kAXValueChangedNotification as CFString
            )
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        activeSession = nil
    }
}

private func correctionCaptureObserverCallback(
    _: AXObserver,
    element: AXUIElement,
    _: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let service = Unmanaged<CorrectionCaptureService>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in
        service.handleValueChanged(element)
    }
}

private enum CorrectionCaptureAX {
    static func stringValue(of element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    static func isFocused(_ element: AXUIElement, pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return false
        }
        return CFEqual(element, value)
    }
}

enum CorrectionCapturePrivacyPolicy {
    private static let blockedApps = [
        "terminal", "iterm", "warp", "ghostty", "alacritty", "wezterm",
        "keychain", "1password", "bitwarden", "keepass",
    ]
    private static let blockedFieldHints = [
        "address bar", "address and search", "omnibox", "url field", "password", "secure",
    ]

    static func isEligible(
        bundleIdentifier: String?,
        appName: String?,
        element: AXUIElement
    ) -> Bool {
        let appText = [bundleIdentifier, appName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        let fieldText = [
            kAXRoleAttribute,
            kAXSubroleAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXIdentifierAttribute,
        ].compactMap {
            CorrectionCaptureAX.stringValue(of: element, attribute: $0 as CFString)?.lowercased()
        }.joined(separator: " ")
        return !isBlocked(appText: appText, fieldText: fieldText)
    }

    static func isBlocked(appText: String, fieldText: String) -> Bool {
        let normalizedApp = appText.lowercased()
        let normalizedField = fieldText.lowercased()
        return blockedApps.contains(where: normalizedApp.contains)
            || blockedFieldHints.contains(where: normalizedField.contains)
    }
}

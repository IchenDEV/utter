import UIKit
import SwiftUI
import UtterKeyboardBridge

final class KeyboardController: UIInputViewController, UIInputViewAudioFeedback {
    private let state = KeyboardState()
    private var bridge: SharedVoiceBridge?
    private var polling: Task<Void, Never>?
    private var watching: Task<Void, Never>?
    private var visible = false
    private var signature: [String?] = []
    private let globe = UIButton(type: .system)
    private lazy var feedback = UIImpactFeedbackGenerator(style: .light, view: view)
    var enableInputClicksWhenVisible: Bool { visible && keyboardPreferences()?.bool(forKey: "keyboard.sounds") == true }

    @objc private func keyFeedback() {
        if hasFullAccess {
            if keyboardPreferences()?.object(forKey: "keyboard.haptics") as? Bool ?? true { feedback.impactOccurred() }
            if enableInputClicksWhenVisible { UIDevice.current.playInputClick() }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bridge = try? voiceBridge()
        let content = KeyboardView(state: state, prepare: { [weak self] in self?.prepare(id: $0, action: $1, lease: $2) ?? false },
                                   insert: { [weak self] in self?.insertResult() }, edit: { [weak self] in self?.edit($0) })
        let host = UIHostingController(rootView: content)
        addChild(host); view.addSubview(host.view); host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = KeyboardView.surfaceColor
        view.backgroundColor = KeyboardView.surfaceColor
        globe.addTarget(self, action: #selector(keyFeedback), for: .touchDown)
        globe.tintColor = .label
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 20), forImageIn: .normal)
        globe.accessibilityLabel = L("ios.action.next_keyboard")
        globe.accessibilityIdentifier = "keyboard.globe"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        view.addSubview(globe); globe.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: globe.topAnchor),
            globe.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            globe.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            globe.heightAnchor.constraint(equalToConstant: 44), globe.widthAnchor.constraint(equalToConstant: 44),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 300)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        globe.isHidden = false
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        refresh(); watchStandby()
    }
    override func viewWillDisappear(_ animated: Bool) {
        visible = false; watching?.cancel(); watching = nil; invalidate(); super.viewWillDisappear(animated)
    }

    // Standby can be replaced by another app's Picture in Picture while the keyboard stays open.
    private func watchStandby() {
        watching?.cancel()
        watching = Task { [weak self] in
            while let self, self.visible, !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard self.hasFullAccess, !self.state.pending, self.state.status?.isBusy != true,
                      let live = try? self.bridge?.status()?.isStandbyLive else { continue }
                if live != self.state.standbyLive { self.refresh() }
            }
        }
    }
    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        guard visible else { return }
        if currentSignature() != signature { invalidate(); refresh() }
    }
    override func selectionWillChange(_ textInput: (any UITextInput)?) {
        invalidate(); super.selectionWillChange(textInput)
    }
    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput); refresh()
    }

    private func currentSignature() -> [String?] {
        [documentID()?.uuidString,
         textDocumentProxy.documentContextBeforeInput.map { String($0.suffix(4096)) },
         textDocumentProxy.documentContextAfterInput.map { String($0.prefix(4096)) }, textDocumentProxy.selectedText]
    }

    private func documentID() -> UUID? {
        // UIKit can return nil after the host tears down a document, despite the nonnull Swift declaration.
        let getter = #selector(getter: UITextDocumentProxy.documentIdentifier)
        guard let proxy = textDocumentProxy as? NSObject, proxy.responds(to: getter),
              let id = proxy.perform(getter)?.takeUnretainedValue() as? NSUUID else { return nil }
        return id as UUID
    }

    private func refresh() {
        guard visible else { return }
        signature = currentSignature()
        state.standbyLive = false
        guard let document = documentID() else { invalidate(); state.errorKey = "ios.error.session"; return }
        guard hasFullAccess else { state.errorKey = "ios.error.full_access"; state.lease = nil; return }
        if bridge == nil { bridge = try? voiceBridge() }
        guard let bridge else { state.errorKey = "ios.error.bridge"; state.lease = nil; return }
        do {
            state.status = try bridge.status()
            state.errorKey = nil
            state.lease = nil
            state.standbyLive = state.status?.isStandbyLive == true
            if let status = state.status, status.isStandbyLive {
                if status.isBusy { state.errorKey = "ios.error.session"; waitForInvalidatedSession() }
                else { state.lease = KeyboardLease(generation: status.generation, documentID: document) }
            }
        } catch { state.errorKey = "ios.error.bridge" }
    }

    private func waitForInvalidatedSession() {
        polling?.cancel()
        polling = Task { [weak self] in
            let deadline = Date().addingTimeInterval(8)
            while let self, self.visible, !Task.isCancelled, Date() < deadline {
                do {
                    guard let status = try self.bridge?.status(), status.isBusy else { self.refresh(); return }
                    try await Task.sleep(for: .milliseconds(300))
                } catch is CancellationError { return }
                catch { self.state.errorKey = "ios.error.bridge"; return }
            }
        }
    }

    private func invalidate() {
        polling?.cancel(); polling = nil; state.pending = false
        if let id = state.lease?.id {
            do { try bridge?.revoke(id) }
            catch { state.errorKey = "ios.error.bridge" }
        }
        state.lease = nil
    }

    private func prepare(id: UUID, action: VoiceAction, lease: KeyboardLease) -> Bool {
        guard hasFullAccess else { state.errorKey = "ios.error.full_access"; return false }
        guard visible, hasFullAccess, let bridge, lease.id == state.lease?.id,
              documentID() == lease.documentID, currentSignature() == signature else { return false }
        keyFeedback()
        if action == .cancel && state.pending && state.status?.isBusy != true {
            invalidate(); refresh(); state.errorKey = "ios.phase.cancelled"
            return false
        }
        do {
            var renewed = lease; renewed.expiresAt = Date().addingTimeInterval(5)
            if action == .start {
                // Every recording gets its own lease so an old stop/cancel cannot affect the next one.
                try bridge.revoke(lease.id)
                renewed = KeyboardLease(generation: lease.generation, documentID: lease.documentID)
            }
            try bridge.renew(renewed)
            try bridge.post(VoiceCommand(id: id, lease: renewed, action: action))
            state.lease = renewed; state.errorKey = nil; state.pending = true
            poll(lease: renewed, action: action)
            return true
        } catch { state.errorKey = "ios.error.bridge"; return false }
    }

    private func poll(lease: KeyboardLease, action: VoiceAction) {
        polling?.cancel()
        polling = Task { [weak self] in
            let deadline = Date().addingTimeInterval(12)
            var observedBusy = action != .start
            while let self, self.visible, !Task.isCancelled {
                do {
                    guard self.hasFullAccess, self.currentSignature() == self.signature,
                          let bridge = self.bridge, let status = try bridge.status(), status.generation == lease.generation else {
                        self.invalidate(); self.state.errorKey = "ios.error.session"; return
                    }
                    var renewed = lease; renewed.expiresAt = Date().addingTimeInterval(5)
                    try bridge.renew(renewed); self.state.lease = renewed
                    self.state.status = status
                    if status.isBusy && (status.leaseID != lease.id || status.documentID != lease.documentID) {
                        self.invalidate(); self.state.errorKey = "ios.error.session"; return
                    }
                    if status.isBusy { observedBusy = true; self.state.pending = false }
                    if !status.isBusy && observedBusy {
                        self.state.pending = false
                        if status.phase == .result { await self.observeResult(status) }
                        return
                    }
                    if !observedBusy && Date() > deadline {
                        self.state.pending = false; self.state.errorKey = "ios.error.background"; self.invalidate(); return
                    }
                    try await Task.sleep(for: .milliseconds(300))
                } catch is CancellationError { return }
                catch { self.invalidate(); self.state.errorKey = "ios.error.bridge"; return }
            }
        }
    }

    private func observeResult(_ result: VoiceStatus) async {
        // Observe only the visible, short-lived result; no microphone lease heartbeat after completion.
        guard let expiry = result.expiresAt else { return }
        while visible, !Task.isCancelled, Date() < expiry {
            do {
                try await Task.sleep(for: .seconds(1))
                guard visible, !Task.isCancelled else { return }
                guard hasFullAccess, currentSignature() == signature else { invalidate(); state.status = nil; return }
                let current = try bridge?.status()
                guard current?.phase == .result, current?.generation == result.generation,
                      current?.requestID == result.requestID else { state.status = nil; refresh(); return }
            } catch is CancellationError { return }
            catch { state.status = nil; state.errorKey = "ios.error.bridge"; return }
        }
        guard !Task.isCancelled else { return }
        state.status = nil
        refresh()
    }

    private func insertResult() {
        guard visible, hasFullAccess, let status = state.status, var lease = state.lease,
              documentID() == lease.documentID, currentSignature() == signature else { return }
        do {
            guard let bridge else { throw BridgeError.unavailable }
            lease.expiresAt = Date().addingTimeInterval(5)
            try bridge.renew(lease)
            let text = try bridge.consume(status, lease: lease)
            keyFeedback()
            textDocumentProxy.insertText(text)
            state.status?.text = ""; invalidate(); refresh()
        } catch { state.errorKey = "ios.error.session" }
    }

    private func edit(_ text: String?) {
        keyFeedback()
        invalidate()
        if let text { textDocumentProxy.insertText(text) } else { textDocumentProxy.deleteBackward() }
        refresh()
    }
}

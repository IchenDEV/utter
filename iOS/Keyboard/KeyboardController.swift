import UIKit
import SwiftUI
import UtterKeyboardBridge

final class KeyboardController: UIInputViewController, UIInputViewAudioFeedback {
    let state = KeyboardState()
    var voiceGesture = VoiceKeyGesture()
    let globe = GlobeKey()
    lazy var heightConstraint: NSLayoutConstraint = {
        let constraint = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.initial.viewHeight)
        constraint.priority = UILayoutPriority(999)
        return constraint
    }()
    lazy var globeFrame = (
        leading: globe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        width: globe.widthAnchor.constraint(equalToConstant: 0), height: globe.heightAnchor.constraint(equalToConstant: 0))
    var hostSides: (leading: NSLayoutConstraint, trailing: NSLayoutConstraint)?
    var bridge: SharedVoiceBridge?
    var polling: Task<Void, Never>?
    var watching: Task<Void, Never>?
    var visible = false
    var signature: [String?] = []
    var stream = StreamingInsertion()
    var lastDictation: Dictation?
    private lazy var feedback = UIImpactFeedbackGenerator(style: .light, view: view)
    var enableInputClicksWhenVisible: Bool { visible && keyboardPreferences()?.bool(forKey: "keyboard.sounds") == true }

    @objc func keyFeedback() {
        if hasFullAccess {
            if keyboardPreferences()?.object(forKey: "keyboard.haptics") as? Bool ?? true { feedback.impactOccurred() }
            if enableInputClicksWhenVisible { UIDevice.current.playInputClick() }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bridge = try? voiceBridge()
        let content = KeyboardView(state: state, prepare: { [weak self] in self?.prepare(id: $0, action: $1, lease: $2) ?? false },
                                   voice: voiceHandlers,
                                   undo: { [weak self] in self?.undoDictation() }, leaveForApp: { [weak self] in self?.postDictationIntent() },
                                   edit: { [weak self] in self?.edit($0) })
        let host = UIHostingController(rootView: content)
        addChild(host); view.addSubview(host.view); host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        // Keys sit on absolute grid coordinates; the keyboard's own safe area must not move them.
        host.safeAreaRegions = []
        // The system draws the keyboard backdrop; painting our own is what made Utter look foreign.
        host.view.backgroundColor = .clear
        view.backgroundColor = .clear
        installGlobe()
        let sides = (leading: host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                     trailing: host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor))
        hostSides = sides
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor), sides.leading, sides.trailing,
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightConstraint
        ])
        applyMetrics()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyMetrics()
    }
    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.applyMetrics() }
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
        state.keyDown = false; voiceGesture.reset()
        endDictation(keepUndo: false)
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
                self.startFromIntentIfReady()
            }
        }
    }
    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        guard visible, !state.streaming else { return }
        if currentSignature() != signature { invalidate(); refresh() }
    }
    override func selectionWillChange(_ textInput: (any UITextInput)?) {
        if !state.streaming { invalidate() }
        super.selectionWillChange(textInput)
    }
    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        if !state.streaming { refresh() }
    }

    func currentSignature() -> [String?] {
        [documentID()?.uuidString,
         textDocumentProxy.documentContextBeforeInput.map { String($0.suffix(4096)) },
         textDocumentProxy.documentContextAfterInput.map { String($0.prefix(4096)) }, textDocumentProxy.selectedText]
    }

    func documentID() -> UUID? {
        // UIKit can return nil after the host tears down a document, despite the nonnull Swift declaration.
        let getter = #selector(getter: UITextDocumentProxy.documentIdentifier)
        guard let proxy = textDocumentProxy as? NSObject, proxy.responds(to: getter),
              let id = proxy.perform(getter)?.takeUnretainedValue() as? NSUUID else { return nil }
        return id as UUID
    }

    func refresh() {
        guard visible else { return }
        validateUndo()
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
        startFromIntentIfReady()
    }

    func waitForInvalidatedSession() {
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

    func invalidate() {
        polling?.cancel(); polling = nil; state.pending = false
        if let id = state.lease?.id {
            do { try bridge?.revoke(id) }
            catch { state.errorKey = "ios.error.bridge" }
        }
        state.lease = nil
    }

    func prepare(id: UUID, action: VoiceAction, lease: KeyboardLease) -> Bool {
        guard hasFullAccess else { state.errorKey = "ios.error.full_access"; return false }
        guard visible, hasFullAccess, let bridge, lease.id == state.lease?.id,
              documentID() == lease.documentID, state.streaming || currentSignature() == signature else { return false }
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

    private func edit(_ text: String?) {
        keyFeedback()
        endDictation(keepUndo: false)
        invalidate()
        if let text { textDocumentProxy.insertText(text) } else { textDocumentProxy.deleteBackward() }
        refresh()
    }
}

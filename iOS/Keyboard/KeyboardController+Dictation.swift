import UIKit
import UtterKeyboardBridge

/// What the last dictation left in the host field, so one key can take it back.
struct Dictation: Equatable {
    var raw: String
    var polished: Bool
}

/// Streams a dictation into the host field while it is spoken and settles it when it ends. The keyboard
/// only deletes text it wrote itself; as soon as the field no longer looks the way the keyboard left it,
/// writing stops and the recording is cancelled.
extension KeyboardController {
    func poll(lease: KeyboardLease, action: VoiceAction) {
        polling?.cancel()
        polling = Task { [weak self] in
            let deadline = Date().addingTimeInterval(12)
            var observedBusy = action != .start
            var mismatches = 0
            while let self, self.visible, !Task.isCancelled {
                do {
                    guard self.hasFullAccess, let bridge = self.bridge, let status = try bridge.status(),
                          status.generation == lease.generation, self.documentID() == lease.documentID else {
                        self.abandonDictation(); return
                    }
                    guard self.fieldIsUnchanged() else {
                        mismatches += 1
                        if mismatches >= 2 { self.abandonDictation(); return }
                        try await Task.sleep(for: .milliseconds(300)); continue
                    }
                    mismatches = 0
                    var renewed = lease; renewed.expiresAt = Date().addingTimeInterval(5)
                    try bridge.renew(renewed); self.state.lease = renewed
                    self.state.status = status
                    if status.isBusy && (status.leaseID != lease.id || status.documentID != lease.documentID) {
                        self.abandonDictation(); return
                    }
                    if status.isBusy {
                        observedBusy = true; self.state.pending = false
                        self.beginStreamingIfNeeded(); self.write(status.text)
                    }
                    if !status.isBusy && observedBusy {
                        self.state.pending = false
                        await self.settle(status, lease: renewed)
                        return
                    }
                    if !observedBusy && Date() > deadline {
                        self.state.pending = false; self.state.errorKey = "ios.error.background"; self.invalidate(); return
                    }
                    try await Task.sleep(for: .milliseconds(300))
                } catch is CancellationError { return }
                catch { self.abandonDictation(); self.state.errorKey = "ios.error.bridge"; return }
            }
        }
    }

    // MARK: Writing

    private func beginStreamingIfNeeded() {
        guard !state.streaming else { return }
        stream.begin(contextBefore: textDocumentProxy.documentContextBeforeInput,
                     contextAfter: textDocumentProxy.documentContextAfterInput)
        state.streaming = true; state.undoable = false; lastDictation = nil
    }

    private func fieldIsUnchanged() -> Bool {
        if state.streaming { return fieldMatchesStream() }
        return currentSignature() == signature
    }

    func fieldMatchesStream() -> Bool {
        stream.isIntact(contextBefore: textDocumentProxy.documentContextBeforeInput,
                        contextAfter: textDocumentProxy.documentContextAfterInput, selectedText: textDocumentProxy.selectedText)
    }

    /// Bring the text we own in the field to `text`, touching only the characters that changed.
    func write(_ text: String) {
        let change = stream.edit(to: text)
        for _ in 0..<change.deleteCount { textDocumentProxy.deleteBackward() }
        if !change.insert.isEmpty { textDocumentProxy.insertText(change.insert) }
    }

    // MARK: Ending

    /// The recording is over. Settle the field, then take the one-time result so it cannot be written twice.
    private func settle(_ status: VoiceStatus, lease: KeyboardLease) async {
        switch status.phase {
        case .result: await commit(status, lease: lease)
        case .cancelled, .failed:
            if state.streaming, fieldMatchesStream() { write("") }
            endDictation(keepUndo: false); invalidate(); refresh()
        default: endDictation(keepUndo: false); invalidate(); refresh()
        }
    }

    private func commit(_ result: VoiceStatus, lease: KeyboardLease) async {
        beginStreamingIfNeeded()
        write(result.text)
        var latest = result
        var polished = false
        if result.polish == .pending { latest = await awaitPolish(result) ?? result }
        if latest.polish == .done, let better = latest.polished, !better.isEmpty, fieldMatchesStream() {
            write(better); polished = true
        }
        do {
            var renewed = lease; renewed.expiresAt = Date().addingTimeInterval(5)
            try bridge?.renew(renewed)
            _ = try bridge?.consume(latest, lease: renewed)
        } catch { state.errorKey = "ios.error.session" }
        keyFeedback()
        let finished = Dictation(raw: result.text, polished: polished)
        state.streaming = false
        if fieldMatchesStream() { lastDictation = finished; state.undoable = true }
        invalidate(); refresh()
    }

    /// Wait for the language-model rewrite; the raw text is already on screen, so give up quickly.
    private func awaitPolish(_ result: VoiceStatus) async -> VoiceStatus? {
        let deadline = Date().addingTimeInterval(7)
        while visible, !Task.isCancelled, Date() < deadline, fieldMatchesStream() {
            guard let current = try? bridge?.status(), current.requestID == result.requestID, current.phase == .result else { return nil }
            state.status = current
            if current.polish != .pending { return current }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    /// The field was changed under us, or the session broke: stop writing and stop recording.
    func abandonDictation() {
        let wasStreaming = state.streaming
        stream.detach(); endDictation(keepUndo: false)
        invalidate(); refresh()
        state.errorKey = wasStreaming ? "ios.error.stream_stopped" : "ios.error.session"
    }

    func endDictation(keepUndo: Bool) {
        state.streaming = false
        if !keepUndo { state.undoable = false; lastDictation = nil }
    }

    /// Take back the last dictation: the rewrite first, then the whole text.
    func undoDictation() {
        guard var last = lastDictation, fieldMatchesStream() else { endDictation(keepUndo: false); return }
        keyFeedback()
        if last.polished { write(last.raw); last.polished = false; lastDictation = last }
        else { write(""); endDictation(keepUndo: false) }
    }

    func validateUndo() {
        if state.undoable, !state.streaming, !fieldMatchesStream() { endDictation(keepUndo: false) }
    }

    // MARK: Leaving for the app and coming back

    /// The microphone key sends the user to Utter when standby is off; leave a note so the keyboard that
    /// returns starts listening without another tap.
    func postDictationIntent() {
        guard hasFullAccess, let document = documentID() else { return }
        try? bridge?.postDictationIntent(DictationIntent(documentID: document))
    }

    func startFromIntentIfReady() {
        guard visible, hasFullAccess, !state.streaming, let bridge, let intent = try? bridge.dictationIntent(),
              state.standbyLive, !state.pending, state.status?.isBusy != true,
              let lease = state.lease, let document = documentID() else { return }
        try? bridge.clearDictationIntent()
        guard intent.documentID == document else { return }
        _ = prepare(id: UUID(), action: .start, lease: lease)
    }
}

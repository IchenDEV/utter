import Foundation
import UtterContracts
@testable import UtterRemoteMic

/// A press source with a scripted permission, so plugin tests never open a real HID manager.
@MainActor
final class PluginPressSource: RemotePressSourcing {
    var onEdge: ((RemoteButton, Bool) -> Void)?
    var onDevicesChanged: (() -> Void)?
    var status: PressSourceStatus = .live
    var statusAfterPrompt: PressSourceStatus?
    var onStop: (() -> Void)?
    private(set) var refreshes: [Bool] = []
    private(set) var stops = 0

    func refresh(prompt: Bool) -> PressSourceStatus {
        refreshes.append(prompt)
        if prompt, let statusAfterPrompt { status = statusAfterPrompt }
        return status
    }

    func stop() {
        stops += 1
        onStop?()
    }

    func press(_ button: RemoteButton) { onEdge?(button, true) }
    func release(_ button: RemoteButton) { onEdge?(button, false) }
}

@MainActor
final class PluginPoster: SyntheticInputPosting {
    private(set) var posted: [SyntheticInput] = []

    func post(_ input: SyntheticInput) -> Bool {
        posted.append(input)
        return true
    }
}

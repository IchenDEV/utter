import SwiftUI
import UtterKeyboardBridge

@MainActor
final class KeyboardState: ObservableObject {
    @Published var status: VoiceStatus?
    @Published var lease: KeyboardLease?
    @Published var errorKey: String?
    @Published var pending = false
    @Published var standbyLive = false
    /// The keyboard is writing a live draft into the host field.
    @Published var streaming = false
    /// A finished dictation sits right before the cursor and can be undone.
    @Published var undoable = false
    /// True while a finger is on the voice key, so the key can say "release to finish".
    @Published var keyDown = false
    @Published var metrics = KeyboardMetrics.initial
    /// Extra height for accessibility text sizes, where the status and result need more room.
    @Published var extraHeight: CGFloat = 0
}

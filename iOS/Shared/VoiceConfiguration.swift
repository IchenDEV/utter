import Foundation
import UtterKeyboardBridge

func L(_ key: String) -> String {
    NSLocalizedString(key, tableName: key.hasPrefix("ios.selection.") ? "SelectionEdit" : nil, comment: "")
}

@MainActor
func voiceBridge() throws -> SharedVoiceBridge {
    guard let identifier = Bundle.main.object(forInfoDictionaryKey: "UtterAppGroup") as? String,
          let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
        throw BridgeError.unavailable
    }
    return try SharedVoiceBridge(container: container)
}

func keyboardPreferences() -> UserDefaults? {
    guard let identifier = Bundle.main.object(forInfoDictionaryKey: "UtterAppGroup") as? String else { return nil }
    return UserDefaults(suiteName: identifier)
}

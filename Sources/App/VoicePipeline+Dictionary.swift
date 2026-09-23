import AppKit

@MainActor
extension VoicePipeline {
    func dictionarySnapshot(
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) -> PersonalDictionarySnapshot {
        if let sessionDictionarySnapshot { return sessionDictionarySnapshot }
        return PersonalDictionary.shared.snapshot(
            settings: settings,
            bundleIdentifier: targetApp?.bundleIdentifier,
            languageCode: settings.inputLanguage.whisperCode
        )
    }
}

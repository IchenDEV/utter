import Foundation

package enum Loc {
    private static let lock = NSLock()
    private static var selectedLanguage: UILanguage = .chinese
    private static var cachedLanguage: UILanguage?
    private static var cachedBundle: Bundle?

    package static var bundle: Bundle {
        ResourceBundle.owned("OpenType_UtterContracts", fallback: Bundle.module)
    }

    package static func use(_ language: UILanguage) {
        lock.lock()
        defer { lock.unlock() }
        selectedLanguage = language
    }

    package static func string(_ key: String, language explicitLanguage: UILanguage? = nil) -> String {
        lock.lock()
        defer { lock.unlock() }
        let language = explicitLanguage ?? selectedLanguage
        if language != cachedLanguage {
            cachedLanguage = language
            let names = language == .chinese ? ["zh-Hans", "zh-hans", "zh"] : ["en"]
            cachedBundle = names.lazy
                .compactMap { bundle.path(forResource: $0, ofType: "lproj") }
                .compactMap { Bundle(path: $0) }
                .first ?? bundle
        }
        return cachedBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }
}

package func L(_ key: String) -> String { Loc.string(key) }

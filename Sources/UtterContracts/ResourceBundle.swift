import Foundation

package enum ResourceBundle {
    package static func owned(_ name: String, fallback: @autoclosure () -> Bundle) -> Bundle {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(name + ".bundle"),
            Bundle.main.bundleURL.appendingPathComponent(name + ".bundle"),
        ].compactMap { $0 }
        for url in candidates {
            if let bundle = Bundle(url: url) { return bundle }
        }
        return fallback()
    }
}

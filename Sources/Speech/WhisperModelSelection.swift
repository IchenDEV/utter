import Foundation

enum WhisperModelSelection {
    static func resolve(
        requested: String,
        available: [String],
        fallback: String
    ) -> String {
        if available.contains(requested) {
            return requested
        }
        let requestedVariant = canonicalVariant(requested)
        if available.contains(fallback), matches(fallback, variant: requestedVariant) {
            return fallback
        }
        if let match = available.first(where: {
            matches($0, variant: requestedVariant)
        }) {
            return match
        }
        if available.contains(fallback) {
            return fallback
        }
        return available.first ?? fallback
    }

    static func matches(_ modelID: String, variant: String) -> Bool {
        let requested = canonicalVariant(variant)
        return !requested.isEmpty && canonicalVariant(modelID) == requested
    }

    static func canonicalVariant(_ value: String) -> String {
        var result = value.lowercased()
        if let slash = result.lastIndex(of: "/") {
            result = String(result[result.index(after: slash)...])
        }
        if result.hasPrefix("openai_whisper-") {
            result.removeFirst("openai_whisper-".count)
        }
        result = result.replacingOccurrences(
            of: #"_[0-9]+mb$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"-v[0-9]{4,}(?=[_-]|$)"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "_turbo", with: "-turbo")
        return result
    }
}

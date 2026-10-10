import Foundation

package enum InputSource: String, Codable, Equatable {
    case menuBar
    case integration
}

package struct InputContext: Codable, Equatable {
    package static let maxScreenContextLength = 1_200
    package static let maxWindowTitleLength = 160
    package static let maxFocusedContextLength = 500

    package let appName: String?
    package let bundleIdentifier: String?
    package let windowTitle: String?
    package let screenContext: String?
    package let textBeforeSelection: String?
    package let selectedText: String?
    package let textAfterSelection: String?
    package let outputMode: OutputMode
    package let inputLanguage: InputLanguage
    package let source: InputSource

    package init(
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        screenContext: String? = nil,
        textBeforeSelection: String? = nil,
        selectedText: String? = nil,
        textAfterSelection: String? = nil,
        outputMode: OutputMode,
        inputLanguage: InputLanguage,
        source: InputSource
    ) {
        self.appName = Self.normalized(appName)
        self.bundleIdentifier = Self.normalized(bundleIdentifier)
        self.windowTitle = Self.normalized(windowTitle, limit: Self.maxWindowTitleLength)
        self.screenContext = Self.normalized(screenContext, limit: Self.maxScreenContextLength)
        self.textBeforeSelection = Self.normalized(textBeforeSelection, limit: Self.maxFocusedContextLength)
        self.selectedText = Self.normalized(selectedText, limit: Self.maxFocusedContextLength)
        self.textAfterSelection = Self.normalized(textAfterSelection, limit: Self.maxFocusedContextLength)
        self.outputMode = outputMode
        self.inputLanguage = inputLanguage
        self.source = source
    }

    package static func normalized(_ text: String?, limit: Int = .max) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit))
    }

}

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum DictionaryFilePanel {
    static func importData() throws -> Data? {
        let panel = NSOpenPanel()
        panel.title = L("dictionary.import")
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try Data(contentsOf: url)
    }

    static func export(_ data: Data) throws -> Bool {
        let panel = NSSavePanel()
        panel.title = L("dictionary.export")
        panel.nameFieldStringValue = "OpenType-Dictionary.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }
}

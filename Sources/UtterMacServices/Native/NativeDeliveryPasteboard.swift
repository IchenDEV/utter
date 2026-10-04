import AppKit
import Foundation

@MainActor
final class NativeDeliveryPasteboard: DeliveryPasteboard {
    private let pasteboard: NSPasteboard
    init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    var changeCount: Int { pasteboard.changeCount }
    var text: String? { pasteboard.string(forType: .string) }
    func snapshot() -> [[String: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type.rawValue, $0) }
            })
        }
    }
    func write(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
    func restore(_ items: [[String: Data]]) {
        pasteboard.clearContents()
        let restored = items.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}

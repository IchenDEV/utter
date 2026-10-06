import UIKit

/// Key grid of the system keyboard, measured on iPad mini (A17 Pro, iPadOS 27.2) so Utter's keys land
/// where the system's do. Other iPads scale by width and are not verified; iPhone and narrow widths
/// (floating keyboard) get a compact grid with no alignment promise.
struct KeyboardMetrics: Equatable {
    var width: CGFloat
    var sideMargin: CGFloat
    var gap: CGFloat
    var keyHeight: CGFloat
    var rowPitch: CGFloat
    var topMargin: CGFloat
    var bottomMargin: CGFloat
    var cornerRadius: CGFloat
    /// Width of the globe, 123 and dictation keys.
    var unitKeyWidth: CGFloat
    /// Width of the keys at the right end of the bottom row.
    var sideKeyWidth: CGFloat
    var deleteKeyWidth: CGFloat
    /// Space the system adds below the input view, which the key area includes. iPad only.
    var bottomSpacer: CGFloat = 0

    static var initial: KeyboardMetrics {
        UIDevice.current.userInterfaceIdiom == .pad
            ? make(width: 744, landscape: false, pad: true) : make(width: 393, landscape: false, pad: false)
    }

    /// Height of the area below the assistant bar, the same extent the system keyboard has.
    var keyAreaHeight: CGFloat { topMargin + 3 * rowPitch + keyHeight + bottomMargin }
    var viewHeight: CGFloat { keyAreaHeight - bottomSpacer }
    var gridBottom: CGFloat { rowTop(3) + keyHeight }
    var mainHeight: CGFloat { rowPitch + keyHeight }
    func rowTop(_ row: Int) -> CGFloat { topMargin + CGFloat(row) * rowPitch }

    static func make(width: CGFloat, landscape: Bool, pad: Bool) -> KeyboardMetrics {
        guard pad, width >= 600 else { return compact(width: width, landscape: landscape) }
        let reference = landscape ? landscapeReference : portraitReference
        let scale = width / reference.width
        return KeyboardMetrics(
            width: width, sideMargin: reference.margin * scale, gap: reference.gap * scale,
            keyHeight: reference.keyHeight * scale, rowPitch: reference.rowPitch * scale,
            topMargin: reference.top * scale, bottomMargin: reference.bottom * scale,
            cornerRadius: reference.radius * scale, unitKeyWidth: reference.unit * scale,
            sideKeyWidth: reference.side * scale, deleteKeyWidth: reference.delete * scale, bottomSpacer: 20)
    }

    private struct Reference {
        var width, margin, gap, keyHeight, rowPitch, top, bottom, radius, unit, side, delete: CGFloat
    }
    private static let portraitReference = Reference(
        width: 744, margin: 6, gap: 12, keyHeight: 55, rowPitch: 64.5, top: 8, bottom: 28.5,
        radius: 10, unit: 56.5, side: 91.5, delete: 67.5)
    private static let landscapeReference = Reference(
        width: 1133, margin: 7, gap: 13.5, keyHeight: 73.5, rowPitch: 85.5, top: 12, bottom: 31,
        radius: 12, unit: 88.5, side: 140, delete: 107.5)

    private static func compact(width: CGFloat, landscape: Bool) -> KeyboardMetrics {
        if landscape {
            return KeyboardMetrics(
                width: width, sideMargin: 4, gap: 6, keyHeight: 38, rowPitch: 46, topMargin: 6, bottomMargin: 8,
                cornerRadius: 6, unitKeyWidth: 56, sideKeyWidth: 100, deleteKeyWidth: 72)
        }
        return KeyboardMetrics(
            width: width, sideMargin: 4, gap: 6, keyHeight: 44, rowPitch: 56, topMargin: 8, bottomMargin: 12,
            cornerRadius: 6, unitKeyWidth: 44, sideKeyWidth: 84, deleteKeyWidth: 56)
    }
}

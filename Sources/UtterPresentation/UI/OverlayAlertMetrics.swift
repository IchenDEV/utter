import AppKit
import UtterContracts
import UtterPresentationContracts

/// What the error / unconfirmed-insertion notice shows. Layout and view both read this, so they cannot disagree.
struct OverlayAlert: Equatable {
    let message: String
    let isUncertain: Bool
    let copyTitle: String?
    let recoveryTitle: String?

    @MainActor
    init(appState: AppState) {
        message = appState.statusMessage
        isUncertain = appState.phase == .uncertain
        copyTitle = appState.presentation.canCopy ? L("common.copy") : nil
        recoveryTitle = appState.snapshot.recoveryAction.map { L($0 == .models ? "hud.open_models" : "hud.open_permissions") }
    }

    init(message: String, isUncertain: Bool, copyTitle: String? = nil, recoveryTitle: String? = nil) {
        self.message = message; self.isUncertain = isUncertain
        self.copyTitle = copyTitle; self.recoveryTitle = recoveryTitle
    }

    var actionTitles: [String] { [copyTitle, recoveryTitle].compactMap { $0 } }

    /// A message of two or more sentences reads as a title and a quieter detail line, so lines break at a
    /// sentence boundary instead of inside a phrase. One sentence is all title.
    var parts: (title: String, detail: String?) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var previous: Character?
        for index in text.indices {
            let character = text[index]
            let cut: String.Index?
            if "。！？".contains(character) { cut = text.index(after: index) }
            else if character == " ", let previous, ".!?".contains(previous) { cut = index }
            else { cut = nil }
            if let cut {
                let detail = text[cut...].trimmingCharacters(in: .whitespacesAndNewlines)
                return (String(text[..<cut]), detail.isEmpty ? nil : detail)
            }
            previous = character
        }
        return (text, nil)
    }
}

/// The panel frame is set from this measurement, so it has to match what `OverlayAlertView` lays out:
/// the same font, fixed action widths and paddings. Measuring slightly narrower than the real width
/// means a rounding difference can only add padding, never clip.
enum OverlayAlertMetrics {
    enum Arrangement: Equatable {
        /// Icon, message and actions on one row.
        case inline
        /// Message and Close on the first row, text actions below it; used when the message would need more than three lines.
        case stacked
    }

    struct Plan: Equatable {
        let arrangement: Arrangement
        let capsuleWidths: [CGFloat]
        let messageWidth: CGFloat
        let titleLines: Int
        let detailLines: Int
        let size: CGSize
    }

    private struct TextFit {
        let titleLines: Int
        let detailLines: Int
        let height: CGFloat
        let exceeds: Bool
    }

    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 18
    /// Black layer over the HUD material; the default 0.22 turns mid-grey on a white window, which is too weak for text.
    static let surfaceTint: Double = 0.6
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 10
    static let itemSpacing: CGFloat = 8
    static let actionSpacing: CGFloat = 6
    static let iconWidth: CGFloat = 16
    static let maxLines = 3
    /// Space between the title and the detail line.
    static let detailGap: CGFloat = 2

    private static let capsuleInset: CGFloat = 11
    private static let minimumCapsuleWidth: CGFloat = 44
    private static let slack: CGFloat = 4
    private static var controlHeight: CGFloat { OverlayControlMetrics.actionButtonSize }

    /// Same faces SwiftUI resolves for `.caption.weight(.medium)` and `.caption`.
    static var titleFont: NSFont { face(.medium) }
    static var detailFont: NSFont { face(.regular) }
    private static func face(_ weight: NSFont.Weight) -> NSFont {
        .systemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: weight)
    }

    static func plan(for alert: OverlayAlert) -> Plan {
        let capsules = alert.actionTitles.map { max(minimumCapsuleWidth, ceil(textWidth($0)) + 2 * capsuleInset) }
        let content = width - 2 * horizontalPadding - iconWidth - itemSpacing
        let trailing = capsules.reduce(0, +) + CGFloat(capsules.count) * actionSpacing + controlHeight
        let inlineWidth = content - itemSpacing - trailing
        let inline = fit(alert, width: inlineWidth)
        if !inline.exceeds || capsules.isEmpty {
            return Plan(arrangement: .inline, capsuleWidths: capsules, messageWidth: inlineWidth,
                        titleLines: inline.titleLines, detailLines: inline.detailLines,
                        size: CGSize(width: width, height: max(controlHeight, inline.height) + 2 * verticalPadding))
        }
        let stackedWidth = content - itemSpacing - controlHeight
        let stacked = fit(alert, width: stackedWidth)
        let height = 2 * verticalPadding + max(controlHeight, stacked.height) + itemSpacing + controlHeight
        return Plan(arrangement: .stacked, capsuleWidths: capsules, messageWidth: stackedWidth,
                    titleLines: stacked.titleLines, detailLines: stacked.detailLines,
                    size: CGSize(width: width, height: height))
    }

    /// At most `maxLines` lines in total; the title keeps priority and the detail gets what is left.
    private static func fit(_ alert: OverlayAlert, width: CGFloat) -> TextFit {
        let (title, detail) = alert.parts
        let titleRun = measure(title, font: titleFont, width: width)
        guard let detail else {
            let lines = min(titleRun.lines, maxLines)
            return TextFit(titleLines: lines, detailLines: 0, height: titleRun.lineHeight * CGFloat(lines),
                           exceeds: titleRun.lines > maxLines)
        }
        let detailRun = measure(detail, font: detailFont, width: width)
        let titleLines = min(titleRun.lines, maxLines - 1)
        let detailLines = min(detailRun.lines, maxLines - titleLines)
        let height = titleRun.lineHeight * CGFloat(titleLines) + detailRun.lineHeight * CGFloat(detailLines) + detailGap
        return TextFit(titleLines: titleLines, detailLines: detailLines, height: height,
                       exceeds: titleRun.lines + detailRun.lines > maxLines)
    }

    private static func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: titleFont]).width
    }

    private static func measure(_ text: String, font: NSFont, width: CGFloat) -> (lines: Int, lineHeight: CGFloat) {
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        let bounds = (text as NSString).boundingRect(with: CGSize(width: max(1, width - slack), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        return (max(1, Int((ceil(bounds.height) / lineHeight).rounded())), lineHeight)
    }
}

import AppKit
import UtterContracts
import UtterPresentationContracts

extension AppState {
    /// Restore is offered only after a confirmed write, and never while another session runs.
    var offersRestore: Bool {
        selectionEditRestoration.map { $0.isAvailable && Date() < $0.expiresAt } == true && phase == .done && !snapshot.isBusy
    }
}

enum SelectionReviewMetrics {
    static let edgePadding: CGFloat = 12
    static let blockSpacing: CGFloat = 8
    static let headerHeight: CGFloat = 40
    static let labelHeight: CGFloat = 14
    static let restoreHeight: CGFloat = 80

    /// Narrowest/shortest connected display, so the panel fits wherever it is placed.
    private static var viewport: CGSize {
        let frames = NSScreen.screens.map(\.visibleFrame)
        return CGSize(width: frames.map(\.width).min() ?? 800, height: frames.map(\.height).min() ?? 600)
    }

    static var width: CGFloat { min(304, max(280, viewport.width - 48)) }
    static var restoreWidth: CGFloat { min(288, max(280, viewport.width - 48)) }

    static func reviewHeight(for proposal: SelectionEditProposal) -> CGFloat {
        let textWidth = width - 2 * edgePadding
        let blocks = [proposal.originalSelection, proposal.candidate].reduce(CGFloat(0)) {
            $0 + labelHeight + 4 + textHeight($1, .caption1, textWidth)
        }
        let instruction = labelHeight + 4 + textHeight(proposal.recognizedInstruction, .caption1, textWidth)
        let content = blocks + instruction + 2 * blockSpacing + edgePadding
        return min(max(headerHeight + content, 180), min(360, viewport.height * 0.7))
    }

    static func disclosureHeight(for consent: SelectionEditRemoteConsent) -> CGFloat {
        let textWidth = width - 2 * edgePadding
        let lead = textHeight(String(format: L("selection_edit.remote_lead"), consent.providerHost), .caption1, textWidth)
        let block = labelHeight + 4 + textHeight(consent.selectedText, .caption1, textWidth)
        return min(max(headerHeight + lead + block + blockSpacing + edgePadding, 180), min(360, viewport.height * 0.7))
    }

    private static func textHeight(_ text: String, _ style: NSFont.TextStyle, _ width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.preferredFont(forTextStyle: style)])
        return ceil(bounds.height)
    }
}

extension OverlayLayout {
    enum Content: Equatable { case status, review, restore, disclosure, notice }

    init(content: Content, size: CGSize) {
        width = size.width; height = size.height
        outerCornerRadius = content == .review || content == .disclosure ? 22 : 18
        isInteractive = true
        horizontalPadding = 0; topPadding = 0; bottomPadding = 0; stackSpacing = 0
        self.content = content
    }
}

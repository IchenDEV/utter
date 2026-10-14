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
    static let blockPadding: CGFloat = 10
    static let edgePadding: CGFloat = 16
    static let blockSpacing: CGFloat = 12
    static let headerHeight: CGFloat = 48
    static let footerHeight: CGFloat = 60
    static let labelHeight: CGFloat = 18
    static let restoreHeight: CGFloat = 104

    /// Narrowest/shortest connected display, so the panel fits wherever it is placed.
    private static var viewport: CGSize {
        let frames = NSScreen.screens.map(\.visibleFrame)
        return CGSize(width: frames.map(\.width).min() ?? 800, height: frames.map(\.height).min() ?? 600)
    }

    static var width: CGFloat { min(420, max(280, viewport.width - 48)) }
    static var restoreWidth: CGFloat { min(340, max(280, viewport.width - 48)) }

    static func reviewHeight(for proposal: SelectionEditProposal) -> CGFloat {
        let textWidth = width - 2 * edgePadding - 2 * blockPadding
        let blocks = [proposal.originalSelection, proposal.candidate].reduce(CGFloat(0)) {
            $0 + labelHeight + 4 + textHeight($1, .body, textWidth) + 2 * blockPadding
        }
        let instruction = labelHeight + 4 + textHeight(proposal.recognizedInstruction, .callout, width - 2 * edgePadding)
        let content = blocks + instruction + 2 * blockSpacing + edgePadding
        return min(max(headerHeight + content + footerHeight, 240), viewport.height * 0.7)
    }

    static func disclosureHeight(for consent: SelectionEditRemoteConsent) -> CGFloat {
        let textWidth = width - 2 * edgePadding - 2 * blockPadding
        let lead = textHeight(L("selection_edit.remote_lead") + consent.providerHost, .callout, width - 2 * edgePadding)
        let block = labelHeight + 4 + textHeight(consent.selectedText, .body, textWidth) + 2 * blockPadding
        return min(max(headerHeight + lead + block + blockSpacing + edgePadding + footerHeight, 240), viewport.height * 0.7)
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
        width = size.width; height = size.height; outerCornerRadius = 16; isInteractive = true
        horizontalPadding = 0; topPadding = 0; bottomPadding = 0; stackSpacing = 0
        self.content = content
    }
}

import UtterContracts
import UtterPresentationContracts
import SwiftUI

struct OverlayLayout: Equatable {
    let width: CGFloat
    let height: CGFloat
    let outerCornerRadius: CGFloat
    let isInteractive: Bool
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let stackSpacing: CGFloat
    var content: Content = .status

    var panelSize: CGSize {
        CGSize(width: width, height: height)
    }

    @MainActor
    init(appState: AppState, notice: String? = nil) {
        if let consent = appState.remoteDisclosure {
            self = OverlayLayout(content: .disclosure,
                size: CGSize(width: SelectionReviewMetrics.width, height: SelectionReviewMetrics.disclosureHeight(for: consent)))
            return
        }
        if let proposal = appState.selectionEditProposal {
            self = OverlayLayout(content: .review,
                size: CGSize(width: SelectionReviewMetrics.width, height: SelectionReviewMetrics.reviewHeight(for: proposal)))
            return
        }
        if appState.offersRestore {
            self = OverlayLayout(content: .restore,
                size: CGSize(width: SelectionReviewMetrics.restoreWidth, height: SelectionReviewMetrics.restoreHeight))
            return
        }
        if notice != nil, !appState.isBusy {
            self = OverlayLayout(content: .notice,
                size: CGSize(width: SelectionReviewMetrics.restoreWidth, height: SelectionReviewMetrics.restoreHeight))
            return
        }
        let hasPreview = appState.phase == .recording && !appState.rawTranscription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showsEspressoFallback = appState.phase == .done
            && appState.completionKind == .espressoFallback
        isInteractive = appState.isRecording || appState.presentation.keepsVisible

        switch appState.phase {
        case .recording where hasPreview:
            width = 304
            height = 80
            outerCornerRadius = 22
            horizontalPadding = 14
            topPadding = 8
            bottomPadding = 8
            stackSpacing = 6
        case .recording:
            width = 148
            height = 40
            outerCornerRadius = 20
            horizontalPadding = 7
            topPadding = 7
            bottomPadding = 7
            stackSpacing = 6
        case .transcribing, .processing, .inserting:
            width = 216
            height = 40
            outerCornerRadius = 20
            horizontalPadding = 12
            topPadding = 10
            bottomPadding = 10
            stackSpacing = 6
        case .error, .uncertain:
            width = 360
            height = 96
            outerCornerRadius = 18
            horizontalPadding = 12
            topPadding = 8
            bottomPadding = 8
            stackSpacing = 6
        case .done where showsEspressoFallback:
            width = 288
            height = 56
            outerCornerRadius = 18
            horizontalPadding = 12
            topPadding = 8
            bottomPadding = 8
            stackSpacing = 6
        default:
            width = 192
            height = 40
            outerCornerRadius = 20
            horizontalPadding = 12
            topPadding = 10
            bottomPadding = 10
            stackSpacing = 6
        }
    }
}

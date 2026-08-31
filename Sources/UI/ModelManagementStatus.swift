import SwiftUI

extension ModelManagementView {
    func secondaryText(for model: ModelCatalog.ModelEntry) -> String {
        switch model.status {
        case .unavailable(let message), .error(let message):
            return message
        default:
            return model.hint
        }
    }

    func statusDot(_ status: ModelCatalog.ModelStatus) -> some View {
        Group {
            switch status {
            case .notDownloaded:
                Circle().fill(.secondary.opacity(0.3))
            case .downloading, .compiling, .loading:
                ProgressView().controlSize(.mini)
            case .downloaded, .ready:
                Circle().fill(.green)
            case .unavailable:
                Circle().fill(.orange)
            case .error:
                Circle().fill(.red)
            }
        }
        .frame(width: 8, height: 8)
    }
}

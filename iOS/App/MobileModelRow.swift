import SwiftUI
import UtterMobile

/// One model in a selection list, in the pattern of iOS Settings: tap a downloaded row to use it (checkmark),
/// the trailing control is the cloud for "download", a progress ring that stops the transfer, or nothing.
struct MobileModelRow: View {
    let model: MobileModel
    let selected: Bool
    let select: () -> Void
    let download: () -> Void
    let cancel: () -> Void

    var body: some View {
        if model.downloaded, !blocked {
            Button(action: select) { content }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("model.use.\(model.id)")
        } else { content }
    }

    private var content: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name).font(.body).foregroundStyle(blocked ? .secondary : .primary)
                if !model.detail.isEmpty { Text(model.detail).font(.footnote).foregroundStyle(.secondary) }
                status
            }
            Spacer(minLength: 8)
            accessory
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private var blocked: Bool { if case .blocked = model.fit { return true }; return false }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .downloading:
            Text(progressText).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
        case .preparing:
            Text(L("ios.models.optimizing")).font(.footnote).foregroundStyle(.secondary)
        case .paused:
            Text(L("ios.models.paused")).font(.footnote).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("model.error.\(model.id)")
        case .notDownloaded, .downloaded:
            if case .blocked(let reason) = model.fit { Text(reason).font(.footnote).foregroundStyle(.secondary) }
            else if case .marginal(let reason) = model.fit, !model.downloaded { Text(reason).font(.footnote).foregroundStyle(.orange) }
            else if model.bytes > 0, !model.detail.contains("GB"), !model.detail.contains("MB") { Text(sizeText).font(.footnote).monospacedDigit().foregroundStyle(.secondary) }
        }
    }

    private var sizeText: String { ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file) }
    private var progressText: String {
        let percent = min(1, max(0, model.progress)).formatted(.percent.precision(.fractionLength(0)))
        return model.progressDetail.isEmpty ? percent : percent + " · " + model.progressDetail
    }

    @ViewBuilder private var accessory: some View {
        switch model.state {
        case .downloaded:
            if selected { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.blue).accessibilityLabel(L("ios.models.selected")) }
        case .downloading:
            Button(action: cancel) { ProgressRing(progress: model.progress) }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("ios.action.cancel")).accessibilityValue(progressText)
                .accessibilityIdentifier("model.cancel.\(model.id)")
        case .preparing:
            ProgressView()
        case .notDownloaded, .paused, .failed:
            if blocked { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary).accessibilityHidden(true) }
            else {
                Button(action: download) {
                    Image(systemName: model.error != nil ? "arrow.clockwise" : "icloud.and.arrow.down").font(.title3)
                }
                .buttonStyle(.borderless).tint(.blue)
                .accessibilityLabel(L(model.error != nil ? "ios.action.retry" : model.state == .paused ? "ios.models.resume" : "ios.models.download"))
                .accessibilityIdentifier("model.download.\(model.id)")
            }
        }
    }
}

/// The App Store's transfer indicator: a ring that fills, with a stop square inside.
struct ProgressRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
            Circle().trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            RoundedRectangle(cornerRadius: 2).fill(Color.blue).frame(width: 9, height: 9)
        }
        .frame(width: 28, height: 28).frame(minWidth: 44, minHeight: 44)
    }
}

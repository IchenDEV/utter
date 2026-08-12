import AppKit
import SwiftUI

enum SettingsPageKind {
    case activity
    case general
    case models
    case style
    case integrations
    case about

    var assetName: String {
        switch self {
        case .activity: "SettingsActivityIllustration"
        case .general: "SettingsVoiceIllustration"
        case .models: "SettingsModelsIllustration"
        case .style: "SettingsStyleIllustration"
        case .integrations: "SettingsIntegrationsIllustration"
        case .about: "SettingsAboutIllustration"
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .activity: "chart.line.uptrend.xyaxis"
        case .general: "waveform.and.mic"
        case .models: "cpu"
        case .style: "text.book.closed"
        case .integrations: "point.3.connected.trianglepath.dotted"
        case .about: "info.circle"
        }
    }
}

struct SettingsPageHeader<Accessory: View>: View {
    let kind: SettingsPageKind
    let title: String
    let subtitle: String
    let accessory: Accessory

    @Environment(\.colorSchemeContrast) private var contrast

    init(
        kind: SettingsPageKind,
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)
            accessory
            SettingsPageIllustration(kind: kind, size: 72)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 96)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

extension SettingsPageHeader where Accessory == EmptyView {
    init(kind: SettingsPageKind, title: String, subtitle: String) {
        self.init(kind: kind, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct SettingsPageIllustration: View {
    let kind: SettingsPageKind
    let size: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor.opacity(contrast == .increased ? 0.16 : 0.09))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.accentColor.opacity(contrast == .increased ? 0.5 : 0.2), lineWidth: 1)
                }

            Group {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: kind.fallbackSymbol)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.tint)
                        .padding(16)
                }
            }
            .padding(6)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var image: NSImage? {
        guard let url = AppResources.bundle.url(
            forResource: kind.assetName,
            withExtension: "png"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct SettingsPageBadge: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
    }
}

struct SettingsPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsCardBackground())
    }
}

struct SettingsCardBackground: View {
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
    }
}

extension View {
    func settingsPageSurface() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

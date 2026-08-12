import SwiftUI

struct AppIconView: View {
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    init(size: CGFloat) {
        self.size = size
    }

    var body: some View {
        icon
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = AppIcon.image(
            for: settings.appIconAppearance,
            systemIsDark: colorScheme == .dark,
            size: size
        ) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    Text("U")
                        .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

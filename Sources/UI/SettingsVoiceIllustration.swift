import AppKit
import SwiftUI

enum SettingsPageLayout {
    static let contentInset: CGFloat = 28
}

struct SettingsCardBackground: View {
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(SettingsSurface.card)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SettingsSurface.cardStroke, lineWidth: 0.5)
            }
    }
}

extension View {
    func settingsPageSurface() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsSurface.page)
    }
}

import SwiftUI

enum OverlayControlMetrics {
    static let actionButtonSize: CGFloat = 26
    static let recordingControlsWidth: CGFloat = 134
}

enum OverlayActionKind {
    case cancel
    case confirm

    var symbolName: String {
        switch self {
        case .cancel: return "xmark"
        case .confirm: return "checkmark"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .cancel: return L("overlay.cancel_recording")
        case .confirm: return L("overlay.finish_recording")
        }
    }

    var keyboardShortcut: KeyboardShortcut {
        switch self {
        case .cancel: return .cancelAction
        case .confirm: return .defaultAction
        }
    }
}

struct OverlayActionButton: View {
    let kind: OverlayActionKind
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: kind.symbolName)
        }
        .buttonStyle(OverlayActionButtonStyle(kind: kind, isHovering: isHovering))
        .keyboardShortcut(kind.keyboardShortcut)
        .accessibilityLabel(kind.accessibilityLabel)
        .help(kind.accessibilityLabel)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }
}

private struct OverlayActionButtonStyle: ButtonStyle {
    let kind: OverlayActionKind
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foregroundStyle)
            .frame(
                width: OverlayControlMetrics.actionButtonSize,
                height: OverlayControlMetrics.actionButtonSize
            )
            .background {
                Circle()
                    .fill(backgroundStyle(isPressed: configuration.isPressed))
            }
            .overlay {
                Circle()
                    .strokeBorder(borderStyle, lineWidth: 0.5)
            }
            .contentShape(Circle())
    }

    private var foregroundStyle: Color {
        switch kind {
        case .cancel: return .white.opacity(0.72)
        case .confirm: return .black.opacity(0.82)
        }
    }

    private func backgroundStyle(isPressed: Bool) -> Color {
        switch kind {
        case .cancel:
            return .white.opacity(isPressed ? 0.18 : isHovering ? 0.13 : 0.07)
        case .confirm:
            return .white.opacity(isPressed ? 0.76 : isHovering ? 1 : 0.9)
        }
    }

    private var borderStyle: Color {
        switch kind {
        case .cancel: return .white.opacity(0.08)
        case .confirm: return .white.opacity(0.42)
        }
    }
}

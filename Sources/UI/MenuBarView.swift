import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    let onOpenSettings: () -> Void
    let onApplyPendingReplacement: () -> Void
    let onConfirmMedicalDraft: () -> Void
    let onDiscardMedicalDraft: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            header
            if hasVisibleContent {
                Divider()
                mainContent
            }
            Divider()
            bottomActions
        }
        .padding(10)
        .frame(width: 260)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            AppIconView(size: 18)
            Text(ProductBrand.displayName)
                .font(.system(size: 13, weight: .semibold))
            Text(activeLanguageSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(activationHint)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private var activationHint: String {
        let key = settings.hotkeyType.rawValue
        switch settings.activationMode {
        case .longPress: return "\(key) " + L("menubar.hold")
        case .doubleTap: return "\(key) ×2"
        case .toggle: return "\(key) " + L("menubar.toggle")
        }
    }

    private var activeLanguageSummary: String {
        if appState.isRecording,
           case .translation(let targetLanguage) = appState.activeInputMode {
            return "\(settings.inputLanguage.rawValue) → \(targetLanguage.label)"
        }
        return settings.inputLanguage.rawValue
    }

    // MARK: - Main content

    private var hasVisibleContent: Bool {
        appState.isRecording || appState.isDownloading || showActiveStatus
            || appState.pendingReplacement != nil
            || appState.pendingMedicalDraft != nil
            || !appState.lastInsertedText.isEmpty
    }

    private var mainContent: some View {
        VStack(spacing: 6) {
            if appState.isRecording {
                recordingRow
            }
            if appState.isDownloading {
                downloadSection
            }
            if showActiveStatus {
                activeStatusRow
            }
            if let pendingReplacement = appState.pendingReplacement {
                pendingReplacementRow(pendingReplacement)
            }
            if let draft = appState.pendingMedicalDraft {
                medicalDraftRow(draft)
            }
            if !appState.lastInsertedText.isEmpty {
                lastInsertedRow
            }
        }
    }

    private var showActiveStatus: Bool {
        switch appState.phase {
        case .loadingModel, .transcribing, .processing, .inserting, .error: return true
        default: return false
        }
    }

    private var recordingRow: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text(
                    appState.activeInputMode.isTranslation
                        ? L("menubar.listening_translation")
                        : L("menubar.listening")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                WaveformView(level: appState.audioLevel)
                    .frame(width: 40, height: 16)
            }

            if !appState.rawTranscription.isEmpty {
                Text(appState.rawTranscription)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var activeStatusRow: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    private var lastInsertedRow: some View {
        HStack(spacing: 6) {
            Text(appState.lastInsertedText)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(appState.lastInsertedText, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("common.copy_clipboard"))
        }
    }

    private func pendingReplacementRow(_ replacement: DeferredReplacement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if replacement.state == .formatting {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: replacementIcon(for: replacement))
                        .font(.system(size: 11))
                        .foregroundStyle(replacementColor(for: replacement))
                }
                Text(replacement.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            if let formattedText = replacement.formattedText {
                HStack(spacing: 6) {
                    if replacement.state == .ready {
                        Button(action: onApplyPendingReplacement) {
                            Text(L("menubar.replace_formatted"))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    Button {
                        TextInserter.copyToClipboard(formattedText)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L("common.copy_clipboard"))

                    Spacer()
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func medicalDraftRow(_ draft: PendingMedicalDraft) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(L("medical_draft.review_title"), systemImage: "checkmark.shield")
                .font(.caption.weight(.semibold))
            Text(draft.text)
                .font(.system(size: 11))
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Button(L("medical_draft.confirm_insert"), action: onConfirmMedicalDraft)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: [.command])
                Button {
                    TextInserter.copyToClipboard(draft.text)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L("common.copy_clipboard"))
                .accessibilityLabel(L("common.copy_clipboard"))
                Button(L("common.discard"), role: .destructive, action: onDiscardMedicalDraft)
                    .buttonStyle(.plain)
                    .controlSize(.small)
                Spacer()
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: appState.downloadProgress)
                .progressViewStyle(.linear)
            HStack {
                Text(appState.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            if !appState.downloadDetailText.isEmpty {
                Text(appState.downloadDetailText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Bottom

    private var bottomActions: some View {
        HStack {
            Button(action: onOpenSettings) {
                Label(L("common.settings"), systemImage: "gear")
            }
            .buttonStyle(.plain)
            .font(.caption)
            Spacer()
            Button(action: onQuit) {
                Label(L("common.quit"), systemImage: "xmark.circle")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch appState.phase {
        case .loadingModel: return .blue
        case .transcribing, .processing: return .orange
        case .inserting: return .yellow
        case .error: return .red
        default: return .gray
        }
    }

    private func replacementIcon(for replacement: DeferredReplacement) -> String {
        switch replacement.state {
        case .ready: return "sparkles"
        case .expired: return "clock.arrow.circlepath"
        case .copied: return "doc.on.doc"
        case .failed: return "exclamationmark.triangle.fill"
        case .formatting: return "ellipsis"
        }
    }

    private func replacementColor(for replacement: DeferredReplacement) -> Color {
        switch replacement.state {
        case .ready: return .orange
        case .expired: return .secondary
        case .copied: return .blue
        case .failed: return .red
        case .formatting: return .secondary
        }
    }
}

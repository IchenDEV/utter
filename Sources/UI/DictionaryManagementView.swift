import SwiftUI

private enum DictionaryFilter: String, CaseIterable {
    case all
    case learned
    case manual
    case pending

    var label: String { L("dictionary.filter.\(rawValue)") }
}
struct DictionaryManagementView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var dictionary = PersonalDictionary.shared
    @State private var filter: DictionaryFilter = .all
    @State private var searchText = ""
    @State private var newOriginal = ""
    @State private var newReplacement = ""
    @State private var statusMessage = ""
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            addRow
            filterRow
            entriesList
            footer
        }
        .alert(L("dictionary.clear_learned_confirm"), isPresented: $showClearConfirmation) {
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("common.clear"), role: .destructive) {
                dictionary.clearLearnedEntries()
            }
        } message: {
            Text(L("common.cannot_undo"))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(L("dictionary.title"), systemImage: "text.book.closed")
                    .font(.headline)
                Spacer()
                if ProductEdition.current.capabilities.correctionLearning {
                    Toggle(L("dictionary.auto_learning"), isOn: $settings.enableCorrectionLearning)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            Text(L("dictionary.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField(L("dictionary.spoken_form"), text: $newOriginal)
                .textFieldStyle(.roundedBorder)
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            TextField(L("dictionary.preferred_form"), text: $newReplacement)
                .textFieldStyle(.roundedBorder)
            Button(L("common.add"), action: addEntry)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canAdd)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            Picker(L("dictionary.filter"), selection: $filter) {
                ForEach(DictionaryFilter.allCases, id: \.self) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)

            TextField(L("dictionary.search"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
        }
    }

    private var entriesList: some View {
        Group {
            if filteredEntries.isEmpty {
                Text(L("dictionary.empty"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            DictionaryEntryRow(
                                entry: entry,
                                onSave: { dictionary.updateEntry(id: entry.id, original: $0, replacement: $1) },
                                onToggle: { dictionary.setEntryEnabled(id: entry.id, enabled: $0) },
                                onApprove: { dictionary.approveEntry(id: entry.id) },
                                onDelete: { dictionary.removeEntry(id: entry.id) }
                            )
                            if entry.id != filteredEntries.last?.id { Divider() }
                        }
                    }
                }
                .frame(minHeight: 110, maxHeight: 190)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if ProductEdition.current.capabilities.dictionaryTransfer {
                Button(L("dictionary.import"), action: importEntries)
                Button(L("dictionary.export"), action: exportEntries)
                    .disabled(dictionary.entries.isEmpty)
            }
            if ProductEdition.current.capabilities.correctionLearning {
                Button(L("dictionary.clear_learned"), role: .destructive) {
                    showClearConfirmation = true
                }
                .disabled(!dictionary.entries.contains { $0.origin == .learned })
            }
            Spacer()
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .controlSize(.small)
    }

    private var canAdd: Bool {
        let original = newOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        return !original.isEmpty && !replacement.isEmpty && original != replacement
    }

    private var filteredEntries: [DictionaryEntry] {
        dictionary.entries
            .filter { entry in
                switch filter {
                case .all: return true
                case .learned: return entry.origin == .learned
                case .manual: return entry.origin == .manual
                case .pending: return entry.status == .pending
                }
            }
            .filter { entry in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                return query.isEmpty
                    || entry.original.localizedCaseInsensitiveContains(query)
                    || entry.replacement.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == .pending }
                return (lhs.lastSeenAt ?? lhs.createdAt) > (rhs.lastSeenAt ?? rhs.createdAt)
            }
    }

    private func addEntry() {
        guard dictionary.addEntry(original: newOriginal, replacement: newReplacement) != nil else { return }
        newOriginal = ""
        newReplacement = ""
        statusMessage = L("dictionary.added")
    }

    private func importEntries() {
        do {
            guard let data = try DictionaryFilePanel.importData() else { return }
            let count = try dictionary.importEntries(from: data)
            statusMessage = String(format: L("dictionary.imported_fmt"), count)
        } catch {
            statusMessage = L("dictionary.import_failed")
        }
    }

    private func exportEntries() {
        do {
            if try DictionaryFilePanel.export(dictionary.exportData()) {
                statusMessage = L("dictionary.exported")
            }
        } catch {
            statusMessage = L("dictionary.export_failed")
        }
    }
}

private struct DictionaryEntryRow: View {
    let entry: DictionaryEntry
    let onSave: (String, String) -> Void
    let onToggle: (Bool) -> Void
    let onApprove: () -> Void
    let onDelete: () -> Void
    @State private var original: String
    @State private var replacement: String

    init(
        entry: DictionaryEntry,
        onSave: @escaping (String, String) -> Void,
        onToggle: @escaping (Bool) -> Void,
        onApprove: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onToggle = onToggle
        self.onApprove = onApprove
        self.onDelete = onDelete
        _original = State(initialValue: entry.original)
        _replacement = State(initialValue: entry.replacement)
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { entry.enabled }, set: onToggle))
                .labelsHidden()
                .controlSize(.small)
            TextField(L("dictionary.spoken_form"), text: $original)
                .textFieldStyle(.plain)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            TextField(L("dictionary.preferred_form"), text: $replacement)
                .textFieldStyle(.plain)
            Text(entry.origin == .manual
                 ? L("dictionary.manual_badge")
                 : String(format: L("dictionary.learned_badge_fmt"), entry.evidenceCount))
                .font(.caption2)
                .foregroundStyle(entry.status == .pending ? .orange : .secondary)
                .frame(minWidth: 54, alignment: .trailing)
            if isDirty {
                Button(L("dictionary.save")) { onSave(original, replacement) }
                    .controlSize(.mini)
            }
            if entry.status == .pending {
                Button(L("dictionary.approve"), action: onApprove)
                    .controlSize(.mini)
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("common.delete"))
            .accessibilityLabel(L("common.delete"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contextMenu {
            if entry.status == .pending { Button(L("dictionary.approve"), action: onApprove) }
            Button(L("common.delete"), role: .destructive, action: onDelete)
        }
    }

    private var isDirty: Bool {
        original != entry.original || replacement != entry.replacement
    }
}

import SwiftUI

struct OfflineEditionSummaryView: View {
    private let validation = OfflineModelBundle.validate()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: validation.isReady ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundStyle(validation.isReady ? .green : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(ProductEdition.localizedName)
                    .font(.headline)
                Text(L("edition.offline_summary"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(validation.localizedMessage)
                    .font(.caption)
                    .foregroundStyle(validation.isReady ? Color.secondary : Color.orange)
            }
            Spacer()
            Text(String(format: L("edition.minimum_memory"), ProductEdition.current.minimumMemoryGB))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }
}

struct IndustryLexiconView: View {
    @State private var searchText = ""
    private let lexicon = IndustryLexicon.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("industry.lexicon.title"), systemImage: "cross.case.fill")
                    .font(.headline)
                Spacer()
                TextField(L("industry.lexicon.search"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .accessibilityLabel(L("industry.lexicon.search"))
            }

            Text(L("industry.lexicon.read_only_help"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(lexicon.sourceVersion) · \(lexicon.updatedAt)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if filteredTerms.isEmpty {
                Text(L("industry.lexicon.no_results"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredTerms) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(item.term)
                                .font(.body)
                                .textSelection(.enabled)
                            if !item.aliases.isEmpty {
                                Text(item.aliases.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Text(categoryLabel(item.category))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .accessibilityElement(children: .combine)
                        if item.id != filteredTerms.last?.id { Divider() }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
            }
        }
    }

    private var filteredTerms: [IndustryLexiconTerm] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return lexicon.terms }
        return lexicon.terms.filter {
            $0.term.localizedCaseInsensitiveContains(query)
                || $0.aliases.contains { $0.localizedCaseInsensitiveContains(query) }
                || categoryLabel($0.category).localizedCaseInsensitiveContains(query)
        }
    }

    private func categoryLabel(_ category: String) -> String {
        L("industry.lexicon.category.\(category)")
    }
}

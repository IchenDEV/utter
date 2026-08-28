import SwiftUI

struct IndustryLexiconView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var searchText = ""
    @State private var showsTerms = false

    private let catalog = IndustryLexiconCatalog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label(L("industry.lexicon.title"), systemImage: "books.vertical")
                    .font(.headline)
                Spacer()
                Picker(L("industry.lexicon.selection"), selection: $settings.industryLexicon) {
                    ForEach(IndustryLexiconID.allCases) { industry in
                        Label(industry.label, systemImage: industry.symbolName)
                            .tag(industry)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
                .accessibilityLabel(L("industry.lexicon.selection"))
            }

            Text(L("industry.lexicon.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let pack = activePack {
                Label(
                    String(format: L("industry.lexicon.term_count_fmt"), pack.terms.count),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(L("industry.lexicon.\(pack.id.rawValue).description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup(
                    L("industry.lexicon.preview"),
                    isExpanded: $showsTerms
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(L("industry.lexicon.search"), text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L("industry.lexicon.search"))

                        termsList(pack)
                    }
                    .padding(.top, 8)
                }
                .font(.caption)
            } else {
                Label(L("industry.lexicon.inactive"), systemImage: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: settings.industryLexicon) { _, _ in
            searchText = ""
        }
    }

    private var activePack: IndustryLexiconPack? {
        catalog.pack(for: settings.industryLexicon)
    }

    private func termsList(_ pack: IndustryLexiconPack) -> some View {
        let terms = filteredTerms(in: pack)
        return Group {
            if terms.isEmpty {
                Text(L("industry.lexicon.no_results"))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(terms) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(item.term)
                                    .textSelection(.enabled)
                                if !item.aliases.isEmpty {
                                    Text(item.aliases.joined(separator: " · "))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .accessibilityElement(children: .combine)
                            if item.id != terms.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 170)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
            }
        }
    }

    private func filteredTerms(in pack: IndustryLexiconPack) -> [IndustryLexiconTerm] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return pack.terms }
        return pack.terms.filter { item in
            item.term.localizedCaseInsensitiveContains(query)
                || item.aliases.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

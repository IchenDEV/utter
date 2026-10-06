import SwiftUI
import UtterMobile

@MainActor
struct DictionaryView: View {
    @ObservedObject var controller: MobileController
    @State private var original = ""
    @State private var replacement = ""
    var body: some View {
        Form {
            Section {
                TextField(L("ios.dictionary.original"), text: $original,
                          prompt: Text(L("ios.dictionary.original")).foregroundColor(Color(uiColor: .label)))
                    .accessibilityIdentifier("dictionary.original")
                TextField(L("ios.dictionary.replacement"), text: $replacement,
                          prompt: Text(L("ios.dictionary.replacement")).foregroundColor(Color(uiColor: .label)))
                    .accessibilityIdentifier("dictionary.replacement")
                Button(L("ios.dictionary.add")) {
                    if controller.addDictionaryEntry(original: original, replacement: replacement) {
                        original = ""; replacement = ""
                    }
                }.disabled(!controller.libraryReady || original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || original == replacement)
                    .accessibilityIdentifier("dictionary.add")
            } footer: { mobileSectionFooter("ios.dictionary.notice") }
            ForEach(controller.dictionaryEntries) { entry in
                HStack { Text(entry.original); Spacer(); Text(entry.replacement) }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("dictionary.entry.\(entry.id)")
                    .swipeActions {
                        Button(L("ios.action.delete"), role: .destructive) { controller.deleteDictionaryEntry(entry.id) }
                            .accessibilityIdentifier("dictionary.delete.\(entry.id)")
                    }
            }
        }.tint(.primary)
            .scrollEdgeEffectHidden()
            .navigationTitle(L("ios.dictionary.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

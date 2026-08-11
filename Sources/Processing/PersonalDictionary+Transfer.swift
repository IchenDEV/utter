import Foundation

extension PersonalDictionary {
    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }

    @discardableResult
    func importEntries(from data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode([DictionaryEntry].self, from: data)
        var count = 0
        for entry in imported {
            guard !normalizedImportedTerm(entry.original).isEmpty,
                  !normalizedImportedTerm(entry.replacement).isEmpty else { continue }
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = entry
            } else if let index = entries.firstIndex(where: {
                $0.original.caseInsensitiveCompare(entry.original) == .orderedSame
            }) {
                entries[index] = entry
            } else {
                entries.append(entry)
            }
            count += 1
        }
        save()
        return count
    }
}
private func normalizedImportedTerm(_ text: String) -> String {
    text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

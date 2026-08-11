import Foundation

extension PersonalDictionary {
    func clearLearnedEntries() {
        entries.removeAll { $0.origin == .learned }
        save()
    }

    @discardableResult
    func recordLearnedCandidate(_ candidate: LearnedCorrectionCandidate) -> UUID? {
        removePreviousEvidence(for: candidate)

        if entries.contains(where: {
            $0.origin == .manual
                && $0.original.caseInsensitiveCompare(candidate.original) == .orderedSame
        }) {
            save()
            return nil
        }

        let now = Date()
        let hasConflict = entries.contains {
            $0.origin == .learned
                && $0.original.caseInsensitiveCompare(candidate.original) == .orderedSame
                && $0.replacement.caseInsensitiveCompare(candidate.replacement) != .orderedSame
        }
        if let index = entries.firstIndex(where: {
            $0.origin == .learned
                && $0.original.caseInsensitiveCompare(candidate.original) == .orderedSame
                && $0.replacement.caseInsensitiveCompare(candidate.replacement) == .orderedSame
        }) {
            merge(candidate, intoEntryAt: index, now: now)
            if hasConflict { markLearnedMappingsPending(for: candidate.original) }
            save()
            return entries[index].id
        }

        if hasConflict { markLearnedMappingsPending(for: candidate.original) }

        let entry = DictionaryEntry(
            original: candidate.original,
            replacement: candidate.replacement,
            origin: .learned,
            status: candidate.confidence >= 0.92 && !hasConflict ? .active : .pending,
            confidence: candidate.confidence,
            evidenceCount: 1,
            lastSeenAt: now,
            languageCode: candidate.languageCode,
            appScopes: candidate.bundleIdentifier.map { [$0] } ?? [],
            evidenceRecordIDs: [candidate.sourceRecordID]
        )
        entries.append(entry)
        save()
        return entry.id
    }
}

private extension PersonalDictionary {
    func merge(_ candidate: LearnedCorrectionCandidate, intoEntryAt index: Int, now: Date) {
        if !entries[index].evidenceRecordIDs.contains(candidate.sourceRecordID) {
            entries[index].evidenceRecordIDs.append(candidate.sourceRecordID)
        }
        entries[index].evidenceCount = max(
            entries[index].evidenceCount,
            entries[index].evidenceRecordIDs.count
        )
        entries[index].confidence = max(entries[index].confidence, candidate.confidence)
        entries[index].lastSeenAt = now
        entries[index].languageCode = candidate.languageCode ?? entries[index].languageCode
        if let bundleIdentifier = candidate.bundleIdentifier,
           !entries[index].appScopes.contains(bundleIdentifier) {
            entries[index].appScopes.append(bundleIdentifier)
        }
        if entries[index].confidence >= 0.92 || entries[index].evidenceCount >= 2 {
            entries[index].status = .active
        }
    }

    func removePreviousEvidence(for candidate: LearnedCorrectionCandidate) {
        for index in entries.indices.reversed() where entries[index].origin == .learned {
            guard let evidenceIndex = entries[index].evidenceRecordIDs.firstIndex(
                of: candidate.sourceRecordID
            ) else { continue }
            let sameMapping = entries[index].original.caseInsensitiveCompare(candidate.original) == .orderedSame
                && entries[index].replacement.caseInsensitiveCompare(candidate.replacement) == .orderedSame
            guard !sameMapping else { continue }
            entries[index].evidenceRecordIDs.remove(at: evidenceIndex)
            entries[index].evidenceCount = entries[index].evidenceRecordIDs.count
            if entries[index].evidenceCount == 0, entries[index].status == .pending {
                entries.remove(at: index)
            }
        }
    }

    func markLearnedMappingsPending(for original: String) {
        for index in entries.indices where entries[index].origin == .learned
            && entries[index].original.caseInsensitiveCompare(original) == .orderedSame {
            entries[index].status = .pending
        }
    }
}

import Foundation

package enum DictionaryEntryOrigin: String, Codable, CaseIterable, Sendable {
    case manual
    case learned
}
package enum DictionaryEntryStatus: String, Codable, CaseIterable, Sendable {
    case active
    case pending
}

package struct DictionaryEntry: Codable, Identifiable, Sendable {
    package var id: UUID
    package var original: String
    package var replacement: String
    package var enabled: Bool
    package var origin: DictionaryEntryOrigin
    package var status: DictionaryEntryStatus
    package var confidence: Double
    package var evidenceCount: Int
    package var createdAt: Date
    package var lastSeenAt: Date?
    package var languageCode: String?
    package var appScopes: [String]
    package var evidenceRecordIDs: [UUID]

    package var isEffective: Bool {
        enabled && status == .active
    }

    package init(
        id: UUID = UUID(),
        original: String,
        replacement: String,
        enabled: Bool = true,
        origin: DictionaryEntryOrigin = .manual,
        status: DictionaryEntryStatus = .active,
        confidence: Double = 1,
        evidenceCount: Int = 1,
        createdAt: Date = Date(),
        lastSeenAt: Date? = nil,
        languageCode: String? = nil,
        appScopes: [String] = [],
        evidenceRecordIDs: [UUID] = []
    ) {
        self.id = id
        self.original = original
        self.replacement = replacement
        self.enabled = enabled
        self.origin = origin
        self.status = status
        self.confidence = confidence
        self.evidenceCount = evidenceCount
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.languageCode = languageCode
        self.appScopes = appScopes
        self.evidenceRecordIDs = evidenceRecordIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, original, replacement, enabled, origin, status, confidence
        case evidenceCount, createdAt, lastSeenAt, languageCode, appScopes, evidenceRecordIDs
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        original = try container.decode(String.self, forKey: .original)
        replacement = try container.decode(String.self, forKey: .replacement)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        origin = try container.decodeIfPresent(DictionaryEntryOrigin.self, forKey: .origin) ?? .manual
        status = try container.decodeIfPresent(DictionaryEntryStatus.self, forKey: .status) ?? .active
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1
        evidenceCount = try container.decodeIfPresent(Int.self, forKey: .evidenceCount) ?? 1
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        appScopes = try container.decodeIfPresent([String].self, forKey: .appScopes) ?? []
        evidenceRecordIDs = try container.decodeIfPresent([UUID].self, forKey: .evidenceRecordIDs) ?? []
    }
}

package struct LearnedCorrectionCandidate: Equatable, Sendable {
    package let original: String
    package let replacement: String
    package let confidence: Double
    package let sourceRecordID: UUID
    package let languageCode: String?
    package let bundleIdentifier: String?

    package init(original: String, replacement: String, confidence: Double, sourceRecordID: UUID, languageCode: String? = nil, bundleIdentifier: String? = nil) {
        self.original = original
        self.replacement = replacement
        self.confidence = confidence
        self.sourceRecordID = sourceRecordID
        self.languageCode = languageCode
        self.bundleIdentifier = bundleIdentifier
    }
}

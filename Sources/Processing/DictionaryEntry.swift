import Foundation

enum DictionaryEntryOrigin: String, Codable, CaseIterable, Sendable {
    case manual
    case learned
}
enum DictionaryEntryStatus: String, Codable, CaseIterable, Sendable {
    case active
    case pending
}

struct DictionaryEntry: Codable, Identifiable, Sendable {
    var id: UUID
    var original: String
    var replacement: String
    var enabled: Bool
    var origin: DictionaryEntryOrigin
    var status: DictionaryEntryStatus
    var confidence: Double
    var evidenceCount: Int
    var createdAt: Date
    var lastSeenAt: Date?
    var languageCode: String?
    var appScopes: [String]
    var evidenceRecordIDs: [UUID]

    var isEffective: Bool {
        enabled && status == .active
    }

    init(
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

    init(from decoder: Decoder) throws {
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

struct LearnedCorrectionCandidate: Equatable, Sendable {
    let original: String
    let replacement: String
    let confidence: Double
    let sourceRecordID: UUID
    let languageCode: String?
    let bundleIdentifier: String?
}

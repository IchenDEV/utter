import Foundation

package enum DeferredReplacementState: Equatable, Sendable {
    case formatting
    case ready
    case expired
    case copied
    case failed
}

package struct DeferredReplacement: Equatable {
    package let id: UUID
    package let historyRecordID: UUID
    package let rawText: String
    package let insertedText: String
    package let targetPID: Int32?
    package let targetBundleIdentifier: String?
    package let targetAppName: String
    package let createdAt: Date
    package let expiresAt: Date
    package var formattedText: String?
    package var state: DeferredReplacementState
    package var message: String
    package var context: InputContext?
    package let formatKind: TextFormatKind

    package init(
        historyRecordID: UUID,
        rawText: String,
        insertedText: String,
        targetPID: Int32? = nil, targetBundleIdentifier: String? = nil, targetAppName: String = "",
        message: String,
        context: InputContext? = nil,
        formatKind: TextFormatKind = .plainParagraph,
        createdAt: Date = Date(),
        expirationInterval: TimeInterval = DeferredReplacementPolicy.expirationInterval
    ) {
        self.id = UUID()
        self.historyRecordID = historyRecordID
        self.rawText = rawText
        self.insertedText = insertedText
        self.targetPID = targetPID
        self.targetBundleIdentifier = targetBundleIdentifier
        self.targetAppName = targetAppName
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(expirationInterval)
        self.formattedText = nil
        self.state = .formatting
        self.message = message
        self.context = context
        self.formatKind = formatKind
    }

    package var hasFormattedText: Bool {
        guard let formattedText else { return false }
        return !formattedText.isEmpty
    }
}

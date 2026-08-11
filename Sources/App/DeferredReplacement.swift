import Foundation
import AppKit

enum DeferredReplacementState {
    case formatting
    case ready
    case expired
    case copied
    case failed
}

struct DeferredReplacement {
    let id: UUID
    let rawText: String
    let insertedText: String
    let targetPID: pid_t?
    let targetBundleIdentifier: String?
    let targetAppName: String
    let createdAt: Date
    let expiresAt: Date
    var formattedText: String?
    var state: DeferredReplacementState
    var message: String
    var context: InputContext?
    let formatKind: TextFormatKind

    init(
        rawText: String,
        insertedText: String,
        targetApp: NSRunningApplication?,
        message: String,
        context: InputContext? = nil,
        formatKind: TextFormatKind = .plainParagraph,
        createdAt: Date = Date(),
        expirationInterval: TimeInterval = DeferredReplacementPolicy.expirationInterval
    ) {
        self.id = UUID()
        self.rawText = rawText
        self.insertedText = insertedText
        self.targetPID = targetApp?.processIdentifier
        self.targetBundleIdentifier = targetApp?.bundleIdentifier
        self.targetAppName = targetApp?.localizedName ?? ""
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(expirationInterval)
        self.formattedText = nil
        self.state = .formatting
        self.message = message
        self.context = context
        self.formatKind = formatKind
    }

    var targetApplication: NSRunningApplication? {
        guard let targetPID else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.processIdentifier == targetPID }
    }

    var hasFormattedText: Bool {
        guard let formattedText else { return false }
        return !formattedText.isEmpty
    }
}

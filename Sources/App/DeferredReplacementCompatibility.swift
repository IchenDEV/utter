import AppKit
import Foundation
import UtterContracts

extension DeferredReplacement {
    init(historyRecordID: UUID, rawText: String, insertedText: String, targetApp: NSRunningApplication?,
         message: String, context: InputContext? = nil, formatKind: TextFormatKind = .plainParagraph,
         createdAt: Date = Date(), expirationInterval: TimeInterval = DeferredReplacementPolicy.expirationInterval) {
        self.init(historyRecordID: historyRecordID, rawText: rawText, insertedText: insertedText,
                  targetPID: targetApp?.processIdentifier, targetBundleIdentifier: targetApp?.bundleIdentifier,
                  targetAppName: targetApp?.localizedName ?? "", message: message, context: context,
                  formatKind: formatKind, createdAt: createdAt, expirationInterval: expirationInterval)
    }

    @MainActor var targetApplication: NSRunningApplication? {
        guard let targetPID else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.processIdentifier == targetPID }
    }
}

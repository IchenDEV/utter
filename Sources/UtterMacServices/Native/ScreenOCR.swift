import UtterContracts
import UtterMediaContracts
import AppKit
import ScreenCaptureKit

package enum ScreenOCR {
    package static func capture(mode: ScreenContextMode, maxLength: Int = 2000,
                                excludedWindowIDs: Set<UInt32> = [], log: Log) async -> ScreenContextSnapshot {
        guard !Task.isCancelled else { return .empty }
        guard await checkScreenCapturePermission() else {
            return ScreenContextSnapshot(text: "", image: nil, status: .permissionDenied)
        }
        let displays: [CapturedDisplay]
        do { displays = try await captureDisplays(excludedWindowIDs: excludedWindowIDs) }
        catch {
            log.error("[ScreenOCR] display capture failed")
            return ScreenContextSnapshot(text: "", image: nil, status: .captureFailed)
        }
        guard !Task.isCancelled else { return .empty }
        do {
            var texts: [String] = []
            for display in displays {
                try Task.checkCancellation()
                texts.append(try await recognizeText(in: display.image))
            }
            try Task.checkCancellation()
            let text = String(texts.filter { !$0.isEmpty }.joined(separator: "\n\n").prefix(max(0, maxLength)))
            let image = mode == .multimodal ? compose(displays) : nil
            guard mode != .multimodal || image != nil else {
                return ScreenContextSnapshot(text: "", image: nil, status: .captureFailed)
            }
            log.info("[ScreenOCR] read \(displays.count) displays, \(text.count) characters")
            return ScreenContextSnapshot(text: text, image: image)
        } catch {
            log.error("[ScreenOCR] text recognition failed")
            return ScreenContextSnapshot(text: "", image: nil, status: .recognitionFailed)
        }
    }

    package static func captureAndRecognize(maxLength: Int = 2000, log: Log) async -> String {
        await capture(mode: .ocr, maxLength: maxLength, log: log).text
    }

    package static func checkScreenCapturePermission() async -> Bool {
        do { _ = try await SCShareableContent.current; return true }
        catch { return false }
    }

    package static func requestPermissionIfNeeded() {
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    private static func captureDisplays(excludedWindowIDs: Set<UInt32>) async throws -> [CapturedDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        let exclusions = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let displays = content.displays.sorted {
            let lhs = CGDisplayBounds($0.displayID), rhs = CGDisplayBounds($1.displayID)
            return lhs.minY == rhs.minY ? lhs.minX < rhs.minX : lhs.minY < rhs.minY
        }
        guard !displays.isEmpty else { throw CocoaError(.fileReadUnknown) }
        var captured: [CapturedDisplay] = []
        for display in displays {
            try Task.checkCancellation()
            let filter = SCContentFilter(display: display, excludingWindows: exclusions)
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try Task.checkCancellation()
            captured.append(CapturedDisplay(image: image, bounds: CGDisplayBounds(display.displayID)))
        }
        return captured
    }
}

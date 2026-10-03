import UtterContracts
import UtterMediaContracts
import Foundation
import AppKit
import Vision
import ScreenCaptureKit

package enum ScreenOCR {

    package static func capture(mode: ScreenContextMode, maxLength: Int = 2000, log: Log) async -> ScreenContextSnapshot {
        guard !Task.isCancelled, await checkScreenCapturePermission() else {
            log.info("[ScreenOCR] screen capture permission not granted")
            return .empty
        }

        guard !Task.isCancelled, let image = await captureMainScreen(log: log) else {
            log.info("[ScreenOCR] screen capture failed")
            return .empty
        }

        guard !Task.isCancelled else { return .empty }
        switch mode {
        case .ocr:
            let text = await recognizeText(in: image, log: log)
            log.info("[ScreenOCR] OCR extracted \(text.count) chars")
            return ScreenContextSnapshot(text: String(text.prefix(maxLength)), image: nil)
        case .multimodal:
            let text = await recognizeText(in: image, log: log)
            log.info(
                "[ScreenOCR] captured multimodal image and \(text.count) OCR chars"
            )
            return ScreenContextSnapshot(
                text: String(text.prefix(maxLength)),
                image: image
            )
        }
    }

    /// Captures the main screen and runs OCR, returning extracted text (truncated to `maxLength`).
    /// Silently returns empty if screen capture permission has not been granted.
    package static func captureAndRecognize(maxLength: Int = 2000, log: Log) async -> String {
        await capture(mode: .ocr, maxLength: maxLength, log: log).text
    }

    package static func checkScreenCapturePermission() async -> Bool {
        do {
            _ = try await SCShareableContent.current
            return true
        } catch {
            return false
        }
    }

    package static func requestPermissionIfNeeded() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: - Capture via ScreenCaptureKit

    private static func captureMainScreen(log: Log) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = content.displays.first else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            log.error("[ScreenOCR] capture error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - OCR

    private static func recognizeText(in image: CGImage, log: Log) async -> String {
        guard !Task.isCancelled else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            guard !Task.isCancelled else { return "" }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } catch {
            log.error("[ScreenOCR] OCR error: \(error.localizedDescription)")
            return ""
        }
    }
}

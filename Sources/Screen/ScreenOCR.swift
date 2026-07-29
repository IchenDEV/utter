import Foundation
import AppKit
import Vision
import ScreenCaptureKit

enum ScreenOCR {

    static func capture(mode: ScreenContextMode, maxLength: Int = 2000) async -> ScreenContextSnapshot {
        guard await checkScreenCapturePermission() else {
            Log.info("[ScreenOCR] screen capture permission not granted")
            return .empty
        }

        guard let image = await captureMainScreen() else {
            Log.info("[ScreenOCR] screen capture failed")
            return .empty
        }

        switch mode {
        case .ocr:
            let text = await recognizeText(in: image)
            Log.info("[ScreenOCR] OCR extracted \(text.count) chars")
            return ScreenContextSnapshot(text: String(text.prefix(maxLength)), image: nil)
        case .multimodal:
            let text = await recognizeText(in: image)
            Log.info(
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
    static func captureAndRecognize(maxLength: Int = 2000) async -> String {
        await capture(mode: .ocr, maxLength: maxLength).text
    }

    static func checkScreenCapturePermission() async -> Bool {
        do {
            _ = try await SCShareableContent.current
            return true
        } catch {
            return false
        }
    }

    static func requestPermissionIfNeeded() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: - Capture via ScreenCaptureKit

    private static func captureMainScreen() async -> CGImage? {
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
            Log.error("[ScreenOCR] capture error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - OCR

    private static func recognizeText(in image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    Log.error("[ScreenOCR] OCR error: \(error.localizedDescription)")
                    continuation.resume(returning: "")
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let lines = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                continuation.resume(returning: text)
            }

            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                Log.error("[ScreenOCR] perform failed: \(error.localizedDescription)")
                continuation.resume(returning: "")
            }
        }
    }
}

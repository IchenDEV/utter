import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import AppKit
import Vision
import XCTest
import UtterContracts
import UtterMediaContracts
@testable import UtterMacServices

@MainActor
final class ScreenReliabilityTests: XCTestCase {
    func testAccurateOCRReadsSyntheticChineseAndEnglishMailInOrder() async throws {
        let image = try makeImage("周五下午三点开会\nPlease confirm the meeting.")
        let text = try await ScreenOCR.recognizeText(in: image)
        XCTAssertTrue(text.contains("周五下午三点开会"), text)
        XCTAssertTrue(text.contains("Please confirm the meeting"), text)
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "周五")).lowerBound,
                          try XCTUnwrap(text.range(of: "Please")).lowerBound)
    }

    func testCompositeIncludesEveryDisplayAndBoundsTheImage() throws {
        let image = try makeImage("Synthetic display")
        let displays = [ScreenOCR.CapturedDisplay(image: image, bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080)),
            ScreenOCR.CapturedDisplay(image: image, bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440))]
        let composed = try XCTUnwrap(ScreenOCR.compose(displays))
        XCTAssertEqual(composed.width, 1600)
        XCTAssertEqual(composed.height, Int(1440.0 * 1600 / 4480))
    }

    func testWindowIdentityExclusionsAndFailureStatusPassThroughTheService() async throws {
        var captured: [Set<UInt32>] = []
        let service = ScopedScreenCapture(isCurrent: { true }, capture: { _, exclusions in
            captured.append(exclusions)
            return ScreenContextSnapshot(text: "", image: nil, status: .permissionDenied)
        }, checkPermission: { false }, requestPermission: {})
        service.excludeWindow(42)
        service.excludeWindow(42)
        let denied = try await service.capture(mode: .ocr)
        XCTAssertEqual(denied.status, .permissionDenied)
        service.includeWindow(42)
        _ = try await service.capture(mode: .ocr)
        XCTAssertEqual(captured, [Set([42]), Set<UInt32>()])
        await service.close()
        service.excludeWindow(99)
        do { _ = try await service.capture(mode: .ocr); XCTFail("Closed capture was admitted") }
        catch is CancellationError {}
        XCTAssertEqual(captured.count, 2)
    }

    func testOCRDoesNotPublishAfterCancellation() async throws {
        let image = try makeImage("This result must be discarded")
        let task = Task { try await ScreenOCR.recognizeText(in: image) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled OCR was returned") }
        catch is CancellationError {}
    }

    private func makeImage(_ text: String) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 400, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 400))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (text as NSString).draw(in: CGRect(x: 40, y: 160, width: 1100, height: 200),
            withAttributes: [.font: NSFont.systemFont(ofSize: 38), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(context.makeImage())
    }
}

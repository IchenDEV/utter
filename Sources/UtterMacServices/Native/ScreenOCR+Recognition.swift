import CoreGraphics
import Vision

extension ScreenOCR {
    package static func recognizeText(in image: CGImage) async throws -> String {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
            .filter { supported.contains($0) }
        request.automaticallyDetectsLanguage = true
        return try await withTaskCancellationHandler {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            try Task.checkCancellation()
            let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            var rows: [[VNRecognizedTextObservation]] = []
            for observation in observations {
                if let last = rows.last?.first, abs(last.boundingBox.midY - observation.boundingBox.midY) < 0.015 {
                    rows[rows.count - 1].append(observation)
                } else { rows.append([observation]) }
            }
            return rows.flatMap { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
                .compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } onCancel: { request.cancel() }
    }

    struct CapturedDisplay {
        let image: CGImage
        let bounds: CGRect
    }

    static func compose(_ displays: [CapturedDisplay], maximumDimension: CGFloat = 1600) -> CGImage? {
        let bounds = displays.reduce(CGRect.null) { $0.union($1.bounds) }
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(1, maximumDimension / max(bounds.width, bounds.height))
        guard let context = CGContext(data: nil, width: max(1, Int(bounds.width * scale)),
            height: max(1, Int(bounds.height * scale)), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale))
        for display in displays {
            let rect = CGRect(x: (display.bounds.minX - bounds.minX) * scale,
                y: (bounds.maxY - display.bounds.maxY) * scale,
                width: display.bounds.width * scale, height: display.bounds.height * scale)
            context.draw(display.image, in: rect)
        }
        return context.makeImage()
    }
}

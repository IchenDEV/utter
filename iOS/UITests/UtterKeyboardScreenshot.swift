import XCTest

/// Screen pixels addressed in interface points. Landscape screenshots arrive rotated 90° from the interface.
struct KeyboardScreenshot {
    private let width: Int, height: Int, scale: CGFloat, landscape: Bool
    private var data: [UInt8]

    init?(landscape: Bool) {
        let image = XCUIScreen.main.screenshot().image
        guard let cg = image.cgImage else { return nil }
        width = cg.width; height = cg.height; scale = image.scale; self.landscape = landscape
        data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !drawn { return nil }
    }

    func color(_ x: CGFloat, _ y: CGFloat) -> [Int] {
        let column = landscape ? width - 1 - Int(y * scale) : Int(x * scale)
        let row = landscape ? Int(x * scale) : Int(y * scale)
        let offset = (min(max(row, 0), height - 1) * width + min(max(column, 0), width - 1)) * 4
        return [Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2])]
    }

    private func distance(_ a: [Int], _ b: [Int]) -> Int { zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } }

    /// How far the first row of a key is inset from its left edge: a direct measure of the corner curve.
    func cornerInset(left: CGFloat, top: CGFloat) -> CGFloat {
        let fill = color(left + 40, top + 8), outside = color(left - 3, top + 30)
        var x = left - 1
        while x < left + 30 {
            let sample = color(x, top + 0.25)
            if distance(sample, fill) <= distance(sample, outside) { return x - left }
            x += 0.5
        }
        return 30
    }
}

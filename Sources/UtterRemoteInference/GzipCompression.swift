import Compression
import Foundation

package enum Gzip {
    package static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        guard let deflated = deflate(data) else { return nil }

        var result = Data(capacity: 10 + deflated.count + 8)
        result.append(contentsOf: [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        result.append(deflated)
        var crc = crc32(data)
        withUnsafeBytes(of: &crc) { result.append(contentsOf: $0) }
        var size = UInt32(truncatingIfNeeded: data.count)
        withUnsafeBytes(of: &size) { result.append(contentsOf: $0) }
        return result
    }

    package static func decompress(_ data: Data) -> Data? {
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b else { return nil }

        var offset = 10
        let flags = data[3]
        if flags & 0x04 != 0 {
            guard data.count >= offset + 2 else { return nil }
            offset += 2 + Int(data[offset]) | (Int(data[offset + 1]) << 8)
        }
        if flags & 0x08 != 0 { while offset < data.count, data[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x10 != 0 { while offset < data.count, data[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x02 != 0 { offset += 2 }

        guard offset < data.count - 8 else { return nil }
        return inflate(Data(data[offset..<(data.count - 8)]))
    }

    private static func deflate(_ data: Data) -> Data? {
        let dstSize = max(data.count + 1024, 65536)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstSize)
        defer { dst.deallocate() }
        let written = data.withUnsafeBytes { src -> Int in
            guard let base = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_encode_buffer(dst, dstSize, base, data.count, nil, COMPRESSION_ZLIB)
        }
        return written > 0 ? Data(bytes: dst, count: written) : nil
    }

    private static func inflate(_ data: Data) -> Data? {
        var capacity = max(data.count * 8, 65536)
        while capacity <= 50_000_000 {
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            let written = data.withUnsafeBytes { src -> Int in
                guard let base = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(dst, capacity, base, data.count, nil, COMPRESSION_ZLIB)
            }
            if written == 0 { dst.deallocate(); return nil }
            if written < capacity {
                let result = Data(bytes: dst, count: written)
                dst.deallocate()
                return result
            }
            dst.deallocate()
            capacity *= 2
        }
        return nil
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }

    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
}

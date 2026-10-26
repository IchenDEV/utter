import Foundation

struct CaptureFormatTraits: Equatable {
    let sampleRate: Double
    let channelCount: UInt32

    var isUsable: Bool { sampleRate.isFinite && sampleRate > 0 && channelCount > 0 }
}

/// Picks the format to tap and record after the input device was set.
///
/// `AVAudioEngine` caches the client format of the default aggregate device it
/// builds on first access to `inputNode`. Moving the unit to another device does
/// not refresh it, so tapping with the cached format on hardware running at a
/// different rate installs no tap and delivers no frames. The hardware format is
/// authoritative; the client format is only a fallback while the device is still
/// reporting nothing.
enum CaptureFormatChoice: Equatable {
    case hardware
    case client
    case unusable

    static func choose(hardware: CaptureFormatTraits, client: CaptureFormatTraits) -> CaptureFormatChoice {
        if hardware.isUsable { return .hardware }
        if client.isUsable { return .client }
        return .unusable
    }
}

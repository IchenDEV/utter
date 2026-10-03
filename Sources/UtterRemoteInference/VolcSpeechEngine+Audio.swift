import Foundation
import AVFoundation
import UtterContracts
import UtterMediaContracts

extension VolcSpeechEngine {
    // MARK: - Audio conversion

    func convertToPCM16k(url: URL) throws -> Data {
        let srcFile  = try AVAudioFile(forReading: url)
        let srcFormat = srcFile.processingFormat

        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw VolcASRError.audioConversionFailed
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            throw VolcASRError.audioConversionFailed
        }

        let ratio          = 16000.0 / srcFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(srcFile.length) * ratio) + 100
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: estimatedFrames) else {
            throw VolcASRError.audioConversionFailed
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            let frameCount: AVAudioFrameCount = 4096
            guard let readBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try srcFile.read(into: readBuffer)
                if readBuffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return readBuffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if let error { throw error }

        let byteCount = Int(outputBuffer.frameLength) * 2
        guard let int16Data = outputBuffer.int16ChannelData else {
            throw VolcASRError.audioConversionFailed
        }
        return Data(bytes: int16Data[0], count: byteCount)
    }

    // MARK: - Language mapping

    func volcLanguage(from whisperCode: String?) -> String? {
        switch whisperCode {
        case "zh":  return "zh-CN"
        case "en":  return "en-US"
        case "ja":  return "ja-JP"
        case "ko":  return "ko-KR"
        case "yue": return "yue-CN"
        case "de":  return "de-DE"
        case "fr":  return "fr-FR"
        case "es":  return "es-MX"
        case "pt":  return "pt-BR"
        case "ru":  return "ru-RU"
        case "it":  return "it-IT"
        case "nl":  return "nl-NL"
        case "pl":  return "pl-PL"
        case "tr":  return "tr-TR"
        case "vi":  return "vi-VN"
        case "th":  return "th-TH"
        case "ar":  return "ar-SA"
        case "id":  return "id-ID"
        default:    return nil
        }
    }
}

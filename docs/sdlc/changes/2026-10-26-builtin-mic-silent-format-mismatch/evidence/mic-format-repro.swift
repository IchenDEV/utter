import AVFoundation
import CoreAudio
import AudioToolbox

// 复现脚本: 先 setInputDevice(内置麦克风) 再装 tap, 对比 outputFormat / inputFormat。
// 仅统计 RMS,不落盘。

func deviceID(forUID uid: String) -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
    for id in ids {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(id, &a, 0, nil, &s, &value) == noErr,
           let cf = value?.takeUnretainedValue(), (cf as String) == uid { return id }
    }
    return nil
}

func run(label: String, useHardwareFormat: Bool) {
    let engine = AVAudioEngine()
    let node = engine.inputNode
    var id = deviceID(forUID: "BuiltInMicrophoneDevice")!
    AudioUnitSetProperty(node.audioUnit!, kAudioOutputUnitProperty_CurrentDevice,
                         kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))

    let out = node.outputFormat(forBus: 0)
    let hw = node.inputFormat(forBus: 0)
    print("[\(label)] outputFormat=\(out.sampleRate)Hz/\(out.channelCount)ch  inputFormat(hw)=\(hw.sampleRate)Hz/\(hw.channelCount)ch")

    let format = useHardwareFormat ? hw : out
    var frames = 0
    var peak: Float = 0
    var changes = 0
    let obs = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in changes += 1 }
    node.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
        frames += Int(buffer.frameLength)
        if let ch = buffer.floatChannelData {
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(ch[0][i])) }
        }
    }
    engine.prepare()
    do { try engine.start() } catch { print("[\(label)] engine start failed: \(error)"); return }
    RunLoop.current.run(until: Date().addingTimeInterval(2.0))
    node.removeTap(onBus: 0)
    engine.stop()
    NotificationCenter.default.removeObserver(obs)
    print("[\(label)] tapFormat=\(format.sampleRate)Hz  frames=\(frames)  peak=\(peak)  configChanges=\(changes)")
}

let status = AVCaptureDevice.authorizationStatus(for: .audio)
print("mic authorization status: \(status.rawValue) (3 = authorized)")
guard status == .authorized else { print("not authorized for this host process; aborting"); exit(2) }

run(label: "current-code (outputFormat)", useHardwareFormat: false)
run(label: "candidate-fix (inputFormat)", useHardwareFormat: true)

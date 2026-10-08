import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import UtterContracts
import UtterMediaContracts

extension AudioCaptureManager {
    // MARK: - Mid-session failover

    func startFailoverMonitor() {
        stopFailoverMonitor()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.evaluateInputHealth()
        }
        RunLoop.main.add(timer, forMode: .common)
        failoverTimer = timer
    }

    func stopFailoverMonitor() {
        failoverTimer?.invalidate()
        failoverTimer = nil
    }

    func evaluateInputHealth() {
        guard isRunning, !usesRemoteMic else { return }
        let action = MicFailoverDecision.decide(
            activeUID: activeInputUID,
            devices: AudioInputDevices.available(),
            preferredUID: preferredInputUID,
            systemDefaultUID: AudioInputDevices.systemDefaultUID(),
            lidClosed: ClamshellState.isClosed
        )
        switch action {
        case .keep:
            break
        case .switchTo(let uid):
            switchInput(to: uid)
        case .fail:
            handleInputUnavailable()
        }
    }

    func switchInput(to uid: String) {
        let name = AudioInputDevices.available().first(where: { $0.uid == uid })?.name ?? uid
        log.info("[AudioCapture] switching to fallback input")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        setInputDevice(uid: uid)
        guard installCaptureTap() else {
            handleInputUnavailable()
            return
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            log.error("[AudioCapture] fallback engine start failed: \(error.localizedDescription)")
            handleInputUnavailable()
            return
        }
        activeInputUID = uid
        log.info("[AudioCapture] fallback input active: \(name)")
        onAutoSwitch?()
    }

    func handleInputUnavailable() {
        log.error("[AudioCapture] active input lost with no fallback")
        stop()
        onInputUnavailable?()
    }

    // MARK: - Device Management

    package static func availableMicrophones() -> [(id: String, name: String)] {
        AudioInputDevices.available().map { (id: $0.uid, name: $0.name) }
    }

    func setInputDevice(uid: String) {
        guard let deviceID = AudioInputDevices.deviceID(forUID: uid) else { return }
        guard let audioUnit = engine.inputNode.audioUnit else { return }
        var id = deviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }
}

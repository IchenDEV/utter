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
            evaluateLiveness()
        case .switchTo(let uid):
            switchInput(to: uid)
        case .fail:
            handleInputUnavailable()
        }
    }

    /// A tap that never receives frames leaves a "running" engine that records
    /// silence. Rebuild it once from the hardware format, then report the failure.
    func evaluateLiveness() {
        switch CaptureLiveness.decide(
            elapsed: Date().timeIntervalSince(captureStartedAt),
            framesReceived: lastActivity.frameCount,
            retriesUsed: livenessRetries
        ) {
        case .healthy, .wait:
            break
        case .retry:
            livenessRetries += 1
            log.info("[AudioCapture] no audio frames after \(CaptureLiveness.graceSeconds) s; restarting capture")
            guard let uid = activeInputUID, restartCapture(on: uid) else {
                handleInputUnavailable(.noAudioReceived)
                return
            }
        case .fail:
            log.error("[AudioCapture] no audio frames after restart")
            handleInputUnavailable(.noAudioReceived)
        }
    }

    func switchInput(to uid: String) {
        let name = AudioInputDevices.available().first(where: { $0.uid == uid })?.name ?? uid
        log.info("[AudioCapture] switching to fallback input")
        guard restartCapture(on: uid) else {
            handleInputUnavailable()
            return
        }
        log.info("[AudioCapture] fallback input active: \(name)")
        onAutoSwitch?()
    }

    /// Rebuilds the tap on `uid` with a freshly read hardware format.
    func restartCapture(on uid: String) -> Bool {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        setInputDevice(uid: uid)
        guard let format = currentCaptureFormat(allowClientFallback: false) else {
            log.error("[AudioCapture] no usable hardware format on restart")
            return false
        }
        installCaptureTap(format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            log.error("[AudioCapture] engine restart failed: \(error.localizedDescription)")
            return false
        }
        activeInputUID = uid
        captureStartedAt = Date()
        return true
    }

    func handleInputUnavailable(_ reason: AudioCaptureStartFailure = .noUsableInput) {
        log.error("[AudioCapture] active input unavailable: \(reason)")
        stop()
        onInputUnavailable?(reason)
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

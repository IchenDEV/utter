import Foundation
import CoreBluetooth
import Combine
import UtterContracts

extension XiaomiRemoteMicBridge {
    // MARK: - Control protocol

    func handleControl(_ data: Data, attempt: UInt64) {
        guard handshake.accepts(attempt) else { return }
        let bytes = Array(data)
        guard let opcode = bytes.first.flatMap(RemoteMicControlOpcode.init(rawValue:)) else { return }

        switch opcode {
        case .capabilities:
            guard let parsed = RemoteMicCapabilities.parse(data) else {
                failAttempt(reason: L("remote_mic.error.invalid_response"))
                return
            }
            capabilities = parsed
            guard RemoteMicProtocol.supportsAudio(sampleRate: parsed.sampleRate) else {
                failAttempt(reason: L("remote_mic.error.unsupported_codec"))
                return
            }
            guard handshake.confirmCapabilities(parsed) else {
                failAttempt(reason: L("remote_mic.error.unsupported_codec"))
                return
            }
            finishInitializationIfReady()
        case .startSearch:
            guard handshake.isReady, isActive else { return }
            // `START_SEARCH` (0x08) is the device announcing itself, not a
            // host-side microphone open. A device-driven session needs no host
            // request, so keep the channel open; the session latches on
            // AUDIO_START so a short press is not lost.
            openMicrophoneIfNeeded()
        case .streamStart:
            guard handshake.isReady, isActive else { return }
            guard let start = RemoteMicStreamStart.parse(data) else { return }
            capabilities.selectedCodec = start.codec
            capabilities.sampleRate = start.codec == 0x02 ? 16_000 : 8_000
            streamID = start.streamID
            guard RemoteMicProtocol.supportsAudio(sampleRate: capabilities.sampleRate) else {
                failAttempt(reason: L("remote_mic.error.unsupported_codec"))
                return
            }
            if session.isLive {
                // The app already opened this session; the remote is now
                // streaming it, so keep it alive past the remote's timeout.
                streamAnnounced = true
                if hostInitiated { startExtending() }
                return
            }
            // Latch synchronously: the pipeline start is asynchronous, and a
            // stop or disconnect may arrive before it commits.
            hostInitiated = false
            streamAnnounced = true
            streamGainDB = gainDB()
            let token = session.press()
            onVoiceKeyPressed?(token)
        case .streamStop:
            if hostInitiated, session.isLive, !streamAnnounced { return }
            cancelExtend()
            // Release before clearing state so endCapture can still close the
            // microphone; previously the reset ran first and made that
            // unreachable, leaving microphoneOpened set.
            let wasLive = session.release()
            preRoll.reset()
            accumulator.reset()
            pendingSync = nil
            decoder.reset()
            if wasLive { onVoiceKeyReleased?() }
        case .sync:
            guard bytes.count >= 7 else { return }
            let bits = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
            pendingSync = (Int(Int16(bitPattern: bits)), Int(bytes[6]))
            accumulator.reset()
        }
    }

    func handleAudio(_ data: Data, attempt: UInt64) {
        guard handshake.accepts(attempt) else { return }
        guard handshake.isReady else { return }
        let frames = accumulator.append(data, frameSize: capabilities.frameSize)
        for frame in frames {
            if let pendingSync {
                decoder.reset(predictor: pendingSync.predictor, stepIndex: pendingSync.stepIndex)
                self.pendingSync = nil
            }
            let samples = RemoteMicPCM.process(
                decoder.decode(frame),
                gainDB: streamGainDB
            )
            // Route through the shared rule so the behaviour a test asserts is
            // the behaviour the bridge runs.
            switch RemoteMicAudioRouting.destination(for: session.phase) {
            case .forward:
                onSamples?(samples)
            case .preRoll:
                preRoll.append(samples)
            case .drop:
                break
            }
        }
    }

    /// Sends the capability request only once both notify subscriptions are
    /// confirmed, and only once per attempt.
    func requestCapabilitiesIfReady() {
        guard handshake.shouldRequestCapabilities else { return }
        handshake.markCapabilitiesRequested()
        startTimeout(
            seconds: Self.initializationTimeout,
            generation: generation,
            reason: L("remote_mic.error.initialization_timeout"),
            isSatisfied: { [weak self] in self?.handshake.isReady ?? false }
        )
        _ = write(RemoteMicProtocol.getCapabilities)
    }

    func finishInitializationIfReady() {
        guard handshake.isReady else { return }
        cancelTimeout()
        reconnectAttempts = 0
        state = .ready(deviceName: peripheral?.name ?? "MI RC")
        if session.isLive { openMicrophoneIfNeeded() }
    }
}

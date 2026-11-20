import AVFoundation

/// Owns the single `AVAudioEngine` shared by microphone capture and speech
/// playback. Voice-processing I/O (echo cancellation) is enabled so Jarvis can
/// keep listening while it speaks — the basis of barge-in — and all speech is
/// played through the same engine so the canceller knows what to remove.
final class AudioEngineHub: @unchecked Sendable {
    static let shared = AudioEngineHub()

    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// Kokoro's native output format; system-voice audio is converted to it.
    let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private(set) var isRunning = false
    private(set) var voiceProcessingEnabled = false
    private var tapInstalled = false
    private let lock = NSLock()
    private var scheduledBuffers = 0

    /// Microphone buffers (called on the audio thread).
    var onInputBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Fired on the main queue when queued playback has drained.
    var onPlaybackDrained: (() -> Void)?

    private init() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isRunning = false
            self?.tapInstalled = false
            try? self?.start(captureMicrophone: true)
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.isRunning = false
            self.tapInstalled = false
            try? self.start(captureMicrophone: true)
        }
    }

    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: [])
    }

    func start(captureMicrophone: Bool) throws {
        if isRunning {
            if captureMicrophone { installTapIfNeeded() } else { removeTap() }
            return
        }
        try configureSession()

        if !voiceProcessingEnabled {
            do {
                try engine.inputNode.setVoiceProcessingEnabled(true)
                voiceProcessingEnabled = true
                // Keep other audio (music) at full volume while we listen.
                engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration =
                    AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
            } catch {
                Log.voice.error("Voice processing unavailable: \(error.localizedDescription)")
            }
        }

        if player.engine == nil { engine.attach(player) }
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        if captureMicrophone { installTapIfNeeded() }
        engine.prepare()
        try engine.start()
        if engine.isRunning { player.play() }
        isRunning = true
    }

    private func installTapIfNeeded() {
        guard !tapInstalled else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.onInputBuffer?(buffer)
        }
        tapInstalled = true
    }

    private func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    func setMicrophoneCapture(_ enabled: Bool) {
        if enabled { installTapIfNeeded() } else { removeTap() }
    }

    func stop() {
        removeTap()
        player.stop()
        engine.stop()
        isRunning = false
    }

    // MARK: Playback

    /// Queue mono float samples at 24 kHz.
    func play(samples: [Float], completion: (() -> Void)? = nil) {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            completion?()
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        schedule(buffer, completion: completion)
    }

    /// Queue any PCM buffer (converted to the playback format when needed).
    func play(buffer: AVAudioPCMBuffer, completion: (() -> Void)? = nil) {
        if buffer.format == playbackFormat {
            schedule(buffer, completion: completion)
        } else if let converted = Self.convert(buffer, to: playbackFormat) {
            schedule(converted, completion: completion)
        } else {
            completion?()
        }
    }

    private var generation = 0

    private func schedule(_ buffer: AVAudioPCMBuffer, completion: (() -> Void)?) {
        if !engine.isRunning {
            isRunning = false
            try? start(captureMicrophone: tapInstalled)
        }
        // AVAudioPlayerNode raises an exception if played while the engine is stopped
        // (e.g. during an audio interruption): drop the audio instead of crashing.
        guard engine.isRunning else {
            DispatchQueue.main.async { completion?() }
            return
        }
        lock.lock(); scheduledBuffers += 1; let gen = generation; lock.unlock()
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            let current = gen == self.generation
            if current && self.scheduledBuffers > 0 { self.scheduledBuffers -= 1 }
            let remaining = self.scheduledBuffers
            self.lock.unlock()
            guard current else { return } // dropped by stopPlayback()
            DispatchQueue.main.async {
                completion?()
                if remaining == 0 { self.onPlaybackDrained?() }
            }
        }
        if !player.isPlaying && engine.isRunning { player.play() }
    }

    /// Stop speech immediately (barge-in) and drop everything queued.
    func stopPlayback() {
        lock.lock(); generation += 1; scheduledBuffers = 0; lock.unlock()
        player.stop()
        if engine.isRunning { player.play() }
    }

    var isPlaying: Bool {
        lock.lock(); defer { lock.unlock() }
        return scheduledBuffers > 0
    }

    static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return (status == .error || error != nil) ? nil : out
    }

    // MARK: Interruptions

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo, let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            isRunning = false
        case .ended:
            let capture = tapInstalled
            tapInstalled = false
            try? start(captureMicrophone: capture || true)
        @unknown default:
            break
        }
    }
}

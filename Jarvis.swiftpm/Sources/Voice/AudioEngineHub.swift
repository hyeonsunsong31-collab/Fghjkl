import AVFoundation

/// Owns the single `AVAudioEngine` shared by microphone capture and speech
/// playback. Voice-processing I/O (echo cancellation) is enabled so Jarvis can
/// keep listening while it speaks — the basis of barge-in — and all speech is
/// played through the same engine so the canceller knows what to remove.
///
/// Crash-safety rules (AVAudioEngine raises Objective-C exceptions that Swift
/// cannot catch):
/// - every engine mutation happens on the **main thread**; calls from other
///   threads (e.g. the speech synthesizer's buffer callback) are hopped there;
/// - a tap is always removed before one is installed (two taps on one bus is fatal);
/// - after a configuration change / interruption the engine is rebuilt once,
///   debounced, instead of from inside the notification;
/// - nothing is scheduled or played unless the engine is running.
final class AudioEngineHub: @unchecked Sendable {
    static let shared = AudioEngineHub()

    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// Kokoro's native output format; system-voice audio is converted to it.
    let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private(set) var isRunning = false
    private(set) var voiceProcessingEnabled = false
    private var wantsCapture = false
    private var tapInstalled = false
    private var playerConnected = false
    private var restartScheduled = false
    private let lock = NSLock()
    private var scheduledBuffers = 0
    private var generation = 0
    /// When the audio queued so far should have finished playing (main thread).
    private var expectedDrain = Date.distantPast

    /// Microphone buffers (called on the realtime audio thread, never on the main actor).
    var onInputBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    /// Fired on the main queue when queued playback has drained.
    var onPlaybackDrained: (() -> Void)?

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRestart()
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.scheduleRestart()
        }
    }

    /// Run `work` on the main thread (immediately when already there).
    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async { work() } }
    }

    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: [])
    }

    // MARK: Lifecycle (main thread)

    /// Start the engine (if needed) and capture the microphone or not.
    func start(captureMicrophone: Bool) throws {
        guard Thread.isMainThread else {
            onMain { try? self.start(captureMicrophone: captureMicrophone) }
            return
        }
        wantsCapture = captureMicrophone
        try ensureRunning()
        applyCapture()
    }

    /// Turn microphone capture on or off without touching playback.
    func setMicrophoneCapture(_ enabled: Bool) {
        onMain {
            self.wantsCapture = enabled
            if enabled && !self.isRunning { try? self.ensureRunning() }
            self.applyCapture()
        }
    }

    func stop() {
        onMain {
            self.wantsCapture = false
            self.removeTap()
            self.player.stop()
            self.engine.stop()
            self.isRunning = false
        }
    }

    /// Bring the engine up with voice processing and the speech player connected.
    private func ensureRunning() throws {
        if isRunning && engine.isRunning { return }
        isRunning = false
        CrashLog.breadcrumb("audio: session")
        try configureSession()

        if !voiceProcessingEnabled {
            CrashLog.breadcrumb("audio: voice processing")
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

        CrashLog.breadcrumb("audio: connect player")
        if player.engine == nil { engine.attach(player) }
        if !playerConnected {
            engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
            playerConnected = true
        }
        // The input format can change with voice processing or a new route: (re)install the tap
        // only once the graph is configured.
        removeTap()
        if wantsCapture { installTap() }
        CrashLog.breadcrumb("audio: engine start")
        engine.prepare()
        try engine.start()
        isRunning = engine.isRunning
        if isRunning { player.play() }
    }

    private func applyCapture() {
        guard isRunning else { return }
        if wantsCapture {
            if !tapInstalled { installTap() }
        } else {
            removeTap()
        }
    }

    private func installTap() {
        CrashLog.breadcrumb("audio: microphone tap")
        // Removing first is always safe and prevents the fatal "tap already installed" exception.
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // No microphone (permission denied, no input route): capture nothing instead of crashing.
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.onInputBuffer?(buffer)
        }
        tapInstalled = true
    }

    private func removeTap() {
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    /// Rebuild the engine once, shortly after a configuration change or media reset.
    private func scheduleRestart() {
        onMain {
            guard !self.restartScheduled else { return }
            self.restartScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.restartScheduled = false
                self.rebuild()
            }
        }
    }

    private var recentRebuilds: [Date] = []

    private func rebuild() {
        // Only an engine that the system actually stopped needs rebuilding; never loop.
        if engine.isRunning && isRunning { return }
        let now = Date()
        recentRebuilds = recentRebuilds.filter { now.timeIntervalSince($0) < 10 }
        guard recentRebuilds.count < 4 else {
            Log.voice.error("Audio engine keeps reconfiguring; pausing restarts")
            return
        }
        recentRebuilds.append(now)
        let capture = wantsCapture
        removeTap()
        player.stop()
        engine.stop()
        isRunning = false
        wantsCapture = capture
        do {
            try ensureRunning()
        } catch {
            Log.voice.error("Audio engine restart failed: \(error.localizedDescription)")
        }
    }

    // MARK: Playback

    /// Queue mono float samples at 24 kHz (any thread).
    func play(samples: [Float], completion: (() -> Void)? = nil) {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData else {
            if let completion { onMain(completion) }
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { channel[0].update(from: base, count: samples.count) }
        }
        onMain { self.schedule(buffer, completion: completion) }
    }

    /// Queue any PCM buffer, converted to the playback format when needed (any thread).
    func play(buffer: AVAudioPCMBuffer, completion: (() -> Void)? = nil) {
        let ready: AVAudioPCMBuffer?
        if buffer.format == playbackFormat {
            ready = buffer
        } else {
            ready = Self.convert(buffer, to: playbackFormat)
        }
        guard let ready, ready.frameLength > 0 else {
            if let completion { onMain(completion) }
            return
        }
        onMain { self.schedule(ready, completion: completion) }
    }

    /// Main thread only.
    private func schedule(_ buffer: AVAudioPCMBuffer, completion: (() -> Void)?) {
        if !isRunning || !engine.isRunning {
            do { try ensureRunning() } catch { Log.voice.error("Playback engine failed: \(error.localizedDescription)") }
        }
        // AVAudioPlayerNode raises an exception if used while the engine is stopped
        // (e.g. during an audio interruption): drop the audio instead of crashing.
        guard engine.isRunning, playerConnected, buffer.format.channelCount == playbackFormat.channelCount else {
            completion?()
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
        if !player.isPlaying { player.play() }
        // Safety net: if playback stalls (callbacks never arrive), report "drained" anyway
        // so Jarvis does not stay in the speaking state forever.
        let duration: Double = Double(buffer.frameLength) / max(1, buffer.format.sampleRate)
        expectedDrain = max(Date(), expectedDrain).addingTimeInterval(duration)
        let deadline = expectedDrain.addingTimeInterval(2)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, deadline.timeIntervalSinceNow)) { [weak self] in
            self?.forceDrainIfStalled(generation: gen, deadline: deadline)
        }
    }

    private func forceDrainIfStalled(generation gen: Int, deadline: Date) {
        let now = Date()
        guard now >= deadline, now >= expectedDrain.addingTimeInterval(2) else { return }
        lock.lock()
        let stalled = gen == generation && scheduledBuffers > 0
        if stalled { scheduledBuffers = 0 }
        lock.unlock()
        if stalled {
            Log.voice.error("Playback callbacks stalled; treating speech as finished")
            onPlaybackDrained?()
        }
    }

    /// Stop speech immediately (barge-in) and drop everything queued.
    func stopPlayback() {
        lock.lock(); generation += 1; scheduledBuffers = 0; lock.unlock()
        onMain {
            guard self.player.engine != nil else { return }
            self.player.stop()
            if self.engine.isRunning && self.playerConnected { self.player.play() }
        }
    }

    var isPlaying: Bool {
        lock.lock(); defer { lock.unlock() }
        return scheduledBuffers > 0
    }

    static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0,
              let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
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

    // MARK: Interruptions (main thread)

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo, let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            isRunning = false
        case .ended:
            scheduleRestart()
        @unknown default:
            break
        }
    }
}

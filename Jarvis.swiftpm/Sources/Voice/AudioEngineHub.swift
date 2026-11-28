import AVFoundation
import os

/// Owns the single `AVAudioEngine` shared by microphone capture and speech
/// playback. Voice-processing I/O (echo cancellation) is enabled so Jarvis can
/// keep listening while it speaks — the basis of barge-in — and all speech is
/// played through the same engine so the canceller knows what to remove.
///
/// Threading: every engine and audio-session operation runs on one private
/// **serial audio queue**, never on the main thread. Starting voice-processing
/// I/O takes seconds; on the main thread it froze the screen, the keyboard and
/// speech callbacks each time the engine (re)started (first reply, microphone
/// watchdog restarts, route changes). Other threads read lock-protected
/// snapshots (`isRunning`, `isCapturing`, `voiceProcessingEnabled`, `isPlaying`).
///
/// Crash-safety rules (AVAudioEngine raises Objective-C exceptions that Swift
/// cannot catch):
/// - every engine mutation happens on the audio queue, in order;
/// - a tap is always removed before one is installed (two taps on one bus is fatal);
/// - after a configuration change / interruption the engine is rebuilt once,
///   debounced, instead of from inside the notification;
/// - nothing is scheduled or played unless the engine is running.
final class AudioEngineHub: @unchecked Sendable {
    static let shared = AudioEngineHub()

    enum HubError: LocalizedError {
        case notRunning
        var errorDescription: String? { "The audio engine did not start" }
    }

    /// User preference: echo cancellation (voice-processing I/O). On by default; the
    /// speech watchdog turns it off when it leaves the microphone silent.
    static let voiceProcessingKey = "JarvisVoiceProcessing"
    static var voiceProcessingPreferred: Bool {
        get { UserDefaults.standard.object(forKey: voiceProcessingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: voiceProcessingKey) }
    }

    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// Kokoro's native output format; system-voice audio is converted to it.
    let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

    private let queue = DispatchQueue(label: "jarvis.audio-engine", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Bool>()

    // Engine state — audio queue only.
    private var running = false
    private var voiceProcessing = false
    private var wantsCapture = false
    private var tapInstalled = false
    private var playerConnected = false
    private var restartScheduled = false
    private var recentRebuilds: [Date] = []
    private var deferredRebuild = false
    /// When the audio queued so far should have finished playing.
    private var expectedDrain = Date.distantPast

    // Snapshots for other threads — guarded by `lock`.
    private let lock = NSLock()
    private var snapRunning = false
    private var snapCapturing = false
    private var snapVoiceProcessing = false
    private var scheduledBuffers = 0
    private var generation = 0

    /// Microphone buffers (called on the realtime audio thread, never on the main actor).
    var onInputBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    /// Fired on the main queue when queued playback has drained.
    var onPlaybackDrained: (() -> Void)?

    private init() {
        queue.setSpecific(key: queueKey, value: true)
        let center = NotificationCenter.default
        // Notifications arrive on arbitrary threads; their work hops to the audio queue.
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            guard let hub = self else { return }
            let raw: UInt? = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            hub.onQueue { hub.handleInterruption(raw) }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            guard let hub = self else { return }
            hub.onQueue { hub.scheduleRestart() }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let hub = self else { return }
            hub.onQueue { hub.scheduleRestart() }
        }
    }

    /// Run `work` on the audio queue (immediately when already there).
    private func onQueue(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == true { work() } else { queue.async(execute: work) }
    }

    /// Publish the engine state for other threads (audio queue).
    private func publish() {
        let isOn: Bool = running && engine.isRunning
        let capturing: Bool = isOn && tapInstalled
        let vp: Bool = voiceProcessing
        lock.lock()
        snapRunning = isOn
        snapCapturing = capturing
        snapVoiceProcessing = vp
        lock.unlock()
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return snapRunning
    }

    /// Is the microphone tap live on a running engine?
    var isCapturing: Bool {
        lock.lock(); defer { lock.unlock() }
        return snapCapturing
    }

    var voiceProcessingEnabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return snapVoiceProcessing
    }

    var isPlaying: Bool {
        lock.lock(); defer { lock.unlock() }
        return scheduledBuffers > 0
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: [])
    }

    // MARK: Lifecycle (audio queue)

    /// Start the engine (if needed) and capture the microphone or not. Waits on the audio
    /// queue — the main thread stays free while voice processing starts up.
    func start(captureMicrophone: Bool) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            onQueue {
                self.wantsCapture = captureMicrophone
                do {
                    try self.ensureRunning()
                    self.applyCapture()
                    self.publish()
                    c.resume()
                } catch {
                    self.publish()
                    c.resume(throwing: error)
                }
            }
        }
    }

    /// Turn microphone capture on or off without touching playback.
    func setMicrophoneCapture(_ enabled: Bool) {
        onQueue {
            self.wantsCapture = enabled
            if enabled && !(self.running && self.engine.isRunning) { try? self.ensureRunning() }
            self.applyCapture()
            self.publish()
        }
    }

    /// Rebuild the engine and resume capture (used by the speech watchdog).
    func restartCapture() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            onQueue {
                self.removeTap()
                self.player.stop()
                self.engine.stop()
                self.running = false
                self.wantsCapture = true
                do {
                    try self.ensureRunning()
                    self.applyCapture()
                    self.publish()
                    c.resume()
                } catch {
                    self.publish()
                    c.resume(throwing: error)
                }
            }
        }
    }

    /// Turn echo cancellation on or off (the engine is rebuilt).
    func setVoiceProcessing(_ enabled: Bool) {
        Self.voiceProcessingPreferred = enabled
        onQueue {
            guard enabled != self.voiceProcessing else { return }
            let capture = self.wantsCapture
            self.removeTap()
            self.player.stop()
            self.engine.stop()
            self.running = false
            self.wantsCapture = capture
            do {
                try self.ensureRunning()
                self.applyCapture()
            } catch {
                Log.voice.error("Audio engine restart failed: \(error.localizedDescription, privacy: .public)")
            }
            self.publish()
        }
    }

    func stop() {
        onQueue {
            self.wantsCapture = false
            self.removeTap()
            self.player.stop()
            self.engine.stop()
            self.running = false
            self.publish()
        }
    }

    /// Bring the engine up with voice processing and the speech player connected (audio queue).
    private func ensureRunning() throws {
        if running && engine.isRunning { return }
        running = false
        CrashLog.breadcrumb("audio: session")
        try configureSession()

        let wantVoiceProcessing = Self.voiceProcessingPreferred
        if wantVoiceProcessing != voiceProcessing {
            CrashLog.breadcrumb("audio: voice processing")
            do {
                try engine.inputNode.setVoiceProcessingEnabled(wantVoiceProcessing)
                voiceProcessing = wantVoiceProcessing
                if wantVoiceProcessing {
                    // Keep other audio (music) at full volume while we listen.
                    engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration =
                        AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
                }
            } catch {
                Log.voice.error("Voice processing unavailable: \(error.localizedDescription, privacy: .public)")
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
        let began = Date()
        engine.prepare()
        try engine.start()
        running = engine.isRunning
        guard running else { throw HubError.notRunning }
        player.play()
        let mode: String = voiceProcessing ? "on" : "off"
        let secs = String(format: "%.2f", Date().timeIntervalSince(began))
        Log.voice.info("Audio engine running (echo cancellation \(mode, privacy: .public), capture \(self.tapInstalled, privacy: .public)) after \(secs, privacy: .public)s, off the main thread")
    }

    private func applyCapture() {
        guard running else { return }
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

    /// Rebuild the engine once, shortly after a configuration change or media reset (audio queue).
    private func scheduleRestart() {
        guard !restartScheduled else { return }
        restartScheduled = true
        queue.asyncAfter(deadline: .now() + 0.35) {
            self.restartScheduled = false
            self.rebuild()
        }
    }

    private func rebuild() {
        // Only an engine that the system actually stopped needs rebuilding; never loop.
        if engine.isRunning && running { return }
        let now = Date()
        recentRebuilds = recentRebuilds.filter { now.timeIntervalSince($0) < 10 }
        guard recentRebuilds.count < 4 else {
            // Pause, but never give up: try again once things have settled.
            Log.voice.error("Audio engine keeps reconfiguring; retrying in 5 s")
            if !deferredRebuild {
                deferredRebuild = true
                queue.asyncAfter(deadline: .now() + 5) {
                    self.deferredRebuild = false
                    self.rebuild()
                }
            }
            return
        }
        recentRebuilds.append(now)
        let capture = wantsCapture
        removeTap()
        player.stop()
        engine.stop()
        running = false
        wantsCapture = capture
        do {
            try ensureRunning()
        } catch {
            Log.voice.error("Audio engine restart failed: \(error.localizedDescription)")
        }
        publish()
    }

    // MARK: Playback

    /// Queue mono float samples at 24 kHz (any thread).
    func play(samples: [Float], completion: (() -> Void)? = nil) {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData else {
            if let completion { DispatchQueue.main.async(execute: completion) }
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { channel[0].update(from: base, count: samples.count) }
        }
        let gen = reserve()
        onQueue { self.schedule(buffer, generation: gen, completion: completion) }
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
            if let completion { DispatchQueue.main.async(execute: completion) }
            return
        }
        let gen = reserve()
        onQueue { self.schedule(ready, generation: gen, completion: completion) }
    }

    /// Count a buffer as playing from the moment it is handed over, so `isPlaying` is right even
    /// while the audio queue is still starting the engine.
    private func reserve() -> Int {
        lock.lock(); defer { lock.unlock() }
        scheduledBuffers += 1
        return generation
    }

    /// A buffer finished (or never reached the player). Returns the buffers still playing, or
    /// nil when `stopPlayback()` already dropped it.
    private func release(_ gen: Int) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard gen == generation else { return nil }
        if scheduledBuffers > 0 { scheduledBuffers -= 1 }
        return scheduledBuffers
    }

    private func finished(remaining: Int?, completion: (() -> Void)?) {
        guard let remaining else { return }
        DispatchQueue.main.async {
            completion?()
            if remaining == 0 { self.onPlaybackDrained?() }
        }
    }

    /// Audio queue only.
    private func schedule(_ buffer: AVAudioPCMBuffer, generation gen: Int, completion: (() -> Void)?) {
        lock.lock(); let dropped = gen != generation; lock.unlock()
        guard !dropped else { return } // stopPlayback() while it waited for the queue
        if !running || !engine.isRunning {
            do { try ensureRunning() } catch { Log.voice.error("Playback engine failed: \(error.localizedDescription)") }
            publish()
        }
        // AVAudioPlayerNode raises an exception if used while the engine is stopped
        // (e.g. during an audio interruption): drop the audio instead of crashing.
        guard engine.isRunning, playerConnected, buffer.format.channelCount == playbackFormat.channelCount else {
            finished(remaining: release(gen), completion: completion)
            return
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.finished(remaining: self.release(gen), completion: completion)
        }
        if !player.isPlaying { player.play() }
        // Safety net: if playback stalls (callbacks never arrive), report "drained" anyway
        // so Jarvis does not stay in the speaking state forever.
        let duration: Double = Double(buffer.frameLength) / max(1, buffer.format.sampleRate)
        expectedDrain = max(Date(), expectedDrain).addingTimeInterval(duration)
        let deadline = expectedDrain.addingTimeInterval(2)
        queue.asyncAfter(deadline: .now() + max(0.1, deadline.timeIntervalSinceNow)) { [weak self] in
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
            DispatchQueue.main.async { self.onPlaybackDrained?() }
        }
    }

    /// Stop speech immediately (barge-in) and drop everything queued.
    func stopPlayback() {
        lock.lock(); generation += 1; scheduledBuffers = 0; lock.unlock()
        onQueue {
            guard self.player.engine != nil else { return }
            self.player.stop()
            if self.engine.isRunning && self.playerConnected { self.player.play() }
        }
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

    // MARK: Interruptions (audio queue)

    private func handleInterruption(_ raw: UInt?) {
        guard let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            running = false
            publish()
        case .ended:
            scheduleRestart()
        @unknown default:
            break
        }
    }
}

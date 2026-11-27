import AVFoundation
import Speech
import os

enum LanguageMode: String, Codable, CaseIterable {
    case auto, korean, english
}

/// Thread-safe bridge between the realtime audio tap and the recognisers. It also
/// keeps simple health figures of the microphone signal for the service's watchdog.
private final class AudioRouter: @unchecked Sendable {
    struct Health {
        var sinceLastBuffer: Double
        var sinceLastSound: Double
        var buffers: Int
        var speaking: Bool
    }

    private let lock = NSLock()
    private var requests: [DetectedLanguage: SFSpeechAudioBufferRecognitionRequest] = [:]
    private var vad = VoiceActivityDetector()
    private var lastMeterTime: Double = 0
    private var lastBufferTime: Double = 0
    private var lastSoundTime: Double = 0
    private var buffers = 0
    var onVAD: ((VoiceActivityDetector.Event) -> Void)?
    var onLevel: ((Float) -> Void)?

    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?, for language: DetectedLanguage) {
        lock.lock(); requests[language] = request; lock.unlock()
    }

    func clearRequests() {
        lock.lock(); requests.removeAll(); lock.unlock()
    }

    func resetHealth() {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock(); lastBufferTime = now; lastSoundTime = now; buffers = 0; lock.unlock()
    }

    func health() -> Health {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock(); defer { lock.unlock() }
        return Health(sinceLastBuffer: now - lastBufferTime, sinceLastSound: now - lastSoundTime,
                      buffers: buffers, speaking: vad.isSpeaking)
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = Array(requests.values)
        lock.unlock()
        for r in current { r.append(buffer) }

        guard let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        let samples = UnsafeBufferPointer(start: data[0], count: n)
        let level = VoiceActivityDetector.level(samples)
        var peak: Float = 0
        for s in samples { peak = max(peak, abs(s)) }
        let duration = Double(n) / max(1, buffer.format.sampleRate)
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        lastBufferTime = now
        // Exact digital silence (all zeros) means the microphone path is broken, not a quiet room.
        if peak > 0 { lastSoundTime = now }
        buffers += 1
        let event = vad.process(levelDB: level, duration: duration)
        let meter = vad.meter
        let sendMeter = now - lastMeterTime > 0.05
        if sendMeter { lastMeterTime = now }
        lock.unlock()
        if let event { DispatchQueue.main.async { self.onVAD?(event) } }
        if sendMeter { DispatchQueue.main.async { self.onLevel?(meter) } }
    }
}

/// A recognition error reduced to plain values (safe to pass between threads and to log).
private struct SpeechFailure {
    let domain: String
    let code: Int
    let message: String

    init(_ error: Error) {
        let ns = error as NSError
        domain = ns.domain
        code = ns.code
        message = ns.localizedDescription
    }

    /// "No speech detected": the normal end of a session that heard silence.
    var isNoSpeech: Bool { domain == "kAFAssistantErrorDomain" && code == 1110 }
    var summary: String { "\(domain) \(code)" }
}

/// On-device speech recognition for Korean and English **at the same time**.
///
/// Both recognisers hear the same audio; the language whose hypothesis is more
/// confident wins, so input/output language switches automatically
/// (requirements 2 & 25). In wake-only mode it scans partial transcripts for
/// "wake up Jarvis"; in conversation mode an energy VAD endpoints utterances and
/// reports speech onsets so Jarvis can be interrupted (requirement 13).
///
/// Reliability rules (every launch must listen, not just some):
/// - `start()` is idempotent and retries the microphone with back-off when iOS
///   refuses the audio session (common right after launch inside Swift Playground);
/// - each language's recogniser is restarted **on its own**: one ending never
///   cuts off the other, and a normal "no speech" ending restarts at once;
/// - only quick, real failures back off (per language). Repeated ones switch that
///   language to server recognition, and if the two recognisers turn out to cancel
///   each other on this device, Jarvis listens with one language at a time;
/// - a watchdog restarts the audio input when the microphone stops delivering
///   audio, and turns echo cancellation off when it delivers only digital silence.
@MainActor
final class SpeechInputService {
    enum ListeningMode { case wakeOnly, conversation }

    struct Hypothesis {
        var text: String
        var confidence: Double
        var isFinal: Bool
    }

    private final class Session: @unchecked Sendable {
        let language: DetectedLanguage
        let request: SFSpeechAudioBufferRecognitionRequest
        let onDevice: Bool
        var task: SFSpeechRecognitionTask?
        var latest: Hypothesis?
        var ended = false
        let started = Date()
        init(language: DetectedLanguage, request: SFSpeechAudioBufferRecognitionRequest, onDevice: Bool) {
            self.language = language
            self.request = request
            self.onDevice = onDevice
        }
    }

    /// Per-language recovery state.
    private struct LanguageHealth {
        var quickFailures = 0
        var useServer = false
        var disabledUntil = Date.distantPast
    }

    var onPartial: ((String) -> Void)?
    var onUtterance: ((String, DetectedLanguage, Double) -> Void)?
    var onWake: ((WakeWordMatcher.Match) -> Void)?
    var onSpeechActivity: ((Bool) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?

    var mode: ListeningMode = .wakeOnly { didSet { if oldValue != mode && isRunning { restartAll() } } }
    var languageMode: LanguageMode = .auto { didSet { if oldValue != languageMode && isRunning { restartAll() } } }
    var preferredLanguage: DetectedLanguage = Locale.preferredLanguages.first?.hasPrefix("ko") == true ? .korean : .english
    var contextualStrings: [String] = ["Jarvis", "자비스", "wake up Jarvis", "hologram", "torus", "3D"]

    private(set) var isRunning = false
    private(set) var isAuthorized = false
    private var starting = false
    private var wantsRunning = false
    private let recognizers: [DetectedLanguage: SFSpeechRecognizer]
    private var sessions: [DetectedLanguage: Session] = [:]
    private var health: [DetectedLanguage: LanguageHealth] = [:]
    private var pendingBegins: [DetectedLanguage: Task<Void, Never>] = [:]
    /// Set when the two recognisers turn out to cancel each other on this device.
    private(set) var oneLanguageAtATime = false
    private var conflictStrikes: [Date] = []
    private var engineRecoveries: [Date] = []
    private let router = AudioRouter()
    private let wakeMatcher = WakeWordMatcher()
    private var finalizing = false
    private var finalizeDeadline: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    /// Second endpoint: the words stopped changing (a short "네" / "yes", or a level detector
    /// kept busy by background sound).
    private var stabilityTask: Task<Void, Never>?
    private var lastPartial = ""
    /// Any words recognised since launch (then the microphone path demonstrably works).
    private var heardAnything = false

    init() {
        var r: [DetectedLanguage: SFSpeechRecognizer] = [:]
        if let en = SFSpeechRecognizer(locale: Locale(identifier: "en-GB")) { r[.english] = en }
        if let ko = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")) { r[.korean] = ko }
        recognizers = r
        router.onVAD = { [weak self] event in self?.handleVAD(event) }
        router.onLevel = { [weak self] level in self?.onLevel?(level) }
    }

    // MARK: Permissions

    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in c.resume(returning: status == .authorized) }
        }
        let mic = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in c.resume(returning: granted) }
        }
        isAuthorized = speech && mic
        if !isAuthorized {
            Log.voice.error("Permissions: speech=\(speech, privacy: .public) microphone=\(mic, privacy: .public)")
        }
        return isAuthorized
    }

    // MARK: Lifecycle

    /// Start listening. Idempotent: any number of calls from anywhere start it once.
    func start() async {
        wantsRunning = true
        guard !isRunning, !starting else { return }
        starting = true
        defer { starting = false }
        if !isAuthorized { _ = await requestAuthorization() }
        guard wantsRunning else { return }
        guard isAuthorized else {
            onError?("음성 인식·마이크 권한이 꺼져 있습니다 (설정 › Swift Playground) · Speech or microphone permission denied")
            return
        }
        let hub = AudioEngineHub.shared
        let router = self.router
        // @Sendable: called on the realtime audio thread, so it must not inherit main-actor isolation.
        hub.onInputBuffer = { @Sendable (buffer: AVAudioPCMBuffer) in router.handle(buffer) }
        var attempt = 0
        while true {
            CrashLog.breadcrumb("audio: starting microphone")
            do {
                try hub.start(captureMicrophone: true)
                break
            } catch {
                attempt += 1
                let reason = error.localizedDescription
                Log.voice.error("Microphone start failed (attempt \(attempt, privacy: .public)): \(reason, privacy: .public)")
                if attempt >= 6 {
                    onError?("마이크를 시작하지 못했습니다 · Microphone unavailable: \(reason)")
                    return
                }
                // iOS often refuses the audio session for a moment right after launch: try again.
                let delay: Double = 0.6 * pow(2, Double(attempt - 1))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard wantsRunning else { return }
            }
        }
        isRunning = true
        router.resetHealth()
        let languages: String = wantedLanguages.map { $0.rawValue }.joined(separator: "+")
        Log.voice.info("Listening started (\(languages, privacy: .public))")
        CrashLog.breadcrumb("speech: starting recognizers")
        beginAll()
        startWatchdog()
        CrashLog.breadcrumb("speech: listening")
    }

    /// Make sure Jarvis is listening (start it, or with `restart` begin recognition afresh).
    func ensureListening(restart: Bool = false) {
        guard isRunning else {
            Task { await start() }
            return
        }
        if !AudioEngineHub.shared.isCapturing {
            recoverAudio(reason: "microphone capture was off")
        } else if restart {
            restartAll()
        }
    }

    func stop() {
        wantsRunning = false
        isRunning = false
        watchdog?.cancel()
        finalizeDeadline?.cancel()
        finalizing = false
        cancelAll()
        AudioEngineHub.shared.setMicrophoneCapture(false)
    }

    /// The user typed or spoke in `language`: listen for it first.
    func noteLanguage(_ language: DetectedLanguage) {
        guard language != preferredLanguage else { return }
        preferredLanguage = language
        if isRunning && oneLanguageAtATime && languageMode == .auto && !finalizing { restartAll() }
    }

    // MARK: Sessions

    private static func other(_ language: DetectedLanguage) -> DetectedLanguage {
        language == .korean ? .english : .korean
    }

    /// Languages to listen for right now.
    private var wantedLanguages: [DetectedLanguage] {
        var list: [DetectedLanguage]
        switch languageMode {
        case .english:
            list = [.english]
        case .korean:
            // While asleep also catch the English wake phrase, unless only one recogniser can run.
            list = (mode == .wakeOnly && !oneLanguageAtATime) ? [.korean, .english] : [.korean]
        case .auto:
            list = oneLanguageAtATime ? [preferredLanguage] : [preferredLanguage, Self.other(preferredLanguage)]
        }
        list = list.filter { recognizers[$0] != nil }
        let now = Date()
        let enabled = list.filter { (health[$0]?.disabledUntil ?? .distantPast) <= now }
        return enabled.isEmpty ? Array(list.prefix(1)) : enabled
    }

    private func beginAll() {
        guard isRunning else { return }
        finalizing = false
        for language in wantedLanguages where sessions[language] == nil { begin(language) }
    }

    private func begin(_ language: DetectedLanguage) {
        pendingBegins[language]?.cancel()
        pendingBegins[language] = nil
        guard isRunning, !finalizing, sessions[language] == nil, let recognizer = recognizers[language] else { return }
        guard recognizer.isAvailable else {
            scheduleBegin(language, after: 1.5)
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let useServer: Bool = health[language]?.useServer ?? false
        let onDevice: Bool = recognizer.supportsOnDeviceRecognition && !useServer
        request.requiresOnDeviceRecognition = onDevice
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings
        let session = Session(language: language, request: request, onDevice: onDevice)
        sessions[language] = session
        router.setRequest(request, for: language)
        // @Sendable: the Speech framework calls this on its own queue.
        session.task = recognizer.recognitionTask(with: request) { @Sendable [weak self] (result: SFSpeechRecognitionResult?, error: Error?) in
            let hypothesis: Hypothesis? = result.map { (r: SFSpeechRecognitionResult) -> Hypothesis in
                let segments = r.bestTranscription.segments
                var total: Double = 0
                for segment in segments { total += Double(segment.confidence) }
                let confidence: Double = segments.isEmpty ? 0 : total / Double(segments.count)
                return Hypothesis(text: r.bestTranscription.formattedString, confidence: confidence, isFinal: r.isFinal)
            }
            let failure: SpeechFailure? = error.map { SpeechFailure($0) }
            DispatchQueue.main.async {
                self?.handle(hypothesis, failure: failure, session: session)
            }
        }
    }

    private func scheduleBegin(_ language: DetectedLanguage, after seconds: Double) {
        pendingBegins[language]?.cancel()
        pendingBegins[language] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.pendingBegins[language] = nil
            self.begin(language)
        }
    }

    /// Stop one language's session (its callbacks are ignored from now on).
    private func end(_ language: DetectedLanguage) {
        guard let s = sessions.removeValue(forKey: language) else { return }
        router.setRequest(nil, for: language)
        s.request.endAudio()
        s.task?.cancel()
    }

    private func cancelAll() {
        stabilityTask?.cancel()
        lastPartial = ""
        for t in pendingBegins.values { t.cancel() }
        pendingBegins.removeAll()
        router.clearRequests()
        for s in sessions.values {
            s.request.endAudio()
            s.task?.cancel()
        }
        sessions.removeAll()
    }

    /// Begin recognition afresh for every wanted language.
    func restartAll() {
        finalizeDeadline?.cancel()
        cancelAll()
        finalizing = false
        guard isRunning else { return }
        // A moment for the cancelled tasks to wind down before the new ones start.
        for language in wantedLanguages { scheduleBegin(language, after: 0.15) }
    }

    // MARK: Results

    private func handle(_ hypothesis: Hypothesis?, failure: SpeechFailure?, session: Session) {
        let language = session.language
        guard isRunning, sessions[language] === session else { return }
        if let h = hypothesis, !h.text.isEmpty {
            session.latest = h
            heardAnything = true
            health[language, default: LanguageHealth()].quickFailures = 0
        }
        let ended: Bool = failure != nil || hypothesis?.isFinal == true

        switch mode {
        case .wakeOnly:
            if let text = hypothesis?.text, let match = wakeMatcher.match(text) {
                Log.voice.info("Wake phrase heard (\(language.rawValue, privacy: .public))")
                cancelAll()
                onWake?(match)
                // `onWake` normally switches to conversation mode, which restarts recognition itself.
                if isRunning && sessions.isEmpty && pendingBegins.isEmpty {
                    for l in wantedLanguages { scheduleBegin(l, after: 0.15) }
                }
                return
            }
            if ended { sessionEnded(session, failure: failure) }
        case .conversation:
            if finalizing {
                if ended { session.ended = true }
                let done: Bool = sessions.values.allSatisfy { $0.ended || $0.latest?.isFinal == true }
                if done { deliverUtterance() }
                return
            }
            if let best = bestHypothesis() {
                onPartial?(best.0)
                if best.0 != lastPartial {
                    lastPartial = best.0
                    armStabilityEndpoint()
                }
            }
            let heardText: Bool = !(session.latest?.text.isEmpty ?? true)
            if hypothesis?.isFinal == true && failure == nil && heardText {
                // The recogniser endpointed by itself.
                finalize()
            } else if ended {
                sessionEnded(session, failure: failure)
            }
        }
    }

    /// A session ended on its own: restart that language only, backing off on real failures.
    private func sessionEnded(_ session: Session, failure: SpeechFailure?) {
        let language = session.language
        end(language)
        let lived: Double = Date().timeIntervalSince(session.started)
        let heardText: Bool = !(session.latest?.text.isEmpty ?? true)
        let quick: Bool = lived < 2 && !heardText && !(failure?.isNoSpeech ?? false)
        var h = health[language, default: LanguageHealth()]
        if quick {
            h.quickFailures += 1
            let what: String = failure?.summary ?? "ended"
            let secs = String(format: "%.1f", lived)
            let count: Int = h.quickFailures
            Log.voice.error("Speech \(language.rawValue, privacy: .public) stopped after \(secs, privacy: .public)s: \(what, privacy: .public) (x\(count, privacy: .public))")
            // A recogniser that dies right away while the other one runs: they may be cancelling each other.
            if !sessions.isEmpty { noteConflict() }
            if h.quickFailures >= 3 && session.onDevice && !h.useServer {
                h.useServer = true
                Log.voice.info("Speech \(language.rawValue, privacy: .public): trying server recognition")
            }
            if h.quickFailures >= 6 {
                if wantedLanguages.count > 1 {
                    h.disabledUntil = Date().addingTimeInterval(60)
                    h.quickFailures = 0
                    Log.voice.error("Speech \(language.rawValue, privacy: .public) paused for 60 s after repeated failures")
                } else if oneLanguageAtATime && languageMode == .auto {
                    // The only language we listen for keeps failing: try the other one.
                    h.quickFailures = 0
                    health[language] = h
                    preferredLanguage = Self.other(language)
                    Log.voice.error("Speech \(language.rawValue, privacy: .public) keeps failing; listening in the other language")
                    restartAll()
                    return
                }
            }
            if h.quickFailures == 4 { reportFailure(failure) }
        } else {
            h.quickFailures = 0
        }
        health[language] = h
        let delay: Double = h.quickFailures == 0 ? 0.1 : min(8, 0.4 * pow(2, Double(h.quickFailures - 1)))
        if isRunning && wantedLanguages.contains(language) { scheduleBegin(language, after: delay) }
    }

    /// Three quick failures with both recognisers running → listen with one language at a time.
    private func noteConflict() {
        guard !oneLanguageAtATime, languageMode != .english else { return }
        let now = Date()
        conflictStrikes = conflictStrikes.filter { now.timeIntervalSince($0) < 30 } + [now]
        guard conflictStrikes.count >= 3 else { return }
        oneLanguageAtATime = true
        conflictStrikes.removeAll()
        Log.voice.error("Two recognisers interfere on this device; listening in one language at a time")
        restartAll()
    }

    private func reportFailure(_ failure: SpeechFailure?) {
        let code: String = failure?.summary ?? "-"
        onError?("음성 인식이 계속 실패합니다 (\(code)). 설정 › 일반 › 키보드 › 받아쓰기가 켜져 있는지 확인해 주십시오 · Speech recognition keeps failing; make sure Dictation is on.")
    }

    // MARK: Endpointing

    private func handleVAD(_ event: VoiceActivityDetector.Event) {
        switch event {
        case .speechStarted:
            onSpeechActivity?(true)
        case .speechEnded(let duration):
            onSpeechActivity?(false)
            guard isRunning else { return }
            // Wake-only sessions keep running: the wake phrase is matched on partial results as
            // they arrive, and cutting a session at the end of speech could drop a slow
            // recogniser's "…Jarvis". The watchdog recycles long sessions instead.
            if mode == .conversation && duration > 0.25 { finalize() }
        }
    }

    private func armStabilityEndpoint() {
        stabilityTask?.cancel()
        let snapshot = lastPartial
        stabilityTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.mode == .conversation, !self.finalizing, self.lastPartial == snapshot, !snapshot.isEmpty else { return }
            self.finalize()
        }
    }

    /// End the current utterance: flush the recognisers and wait briefly for final results.
    func finalize() {
        guard mode == .conversation, !finalizing, !sessions.isEmpty else { return }
        finalizing = true
        router.clearRequests()
        for s in sessions.values { s.request.endAudio() }
        finalizeDeadline?.cancel()
        finalizeDeadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard let self, self.finalizing else { return }
            self.deliverUtterance()
        }
    }

    private func deliverUtterance() {
        finalizeDeadline?.cancel()
        let choice = bestHypothesis()
        cancelAll()
        finalizing = false
        if let (text, language, confidence) = choice {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                preferredLanguage = language
                onUtterance?(trimmed, language, confidence)
            }
        }
        beginAll()
    }

    /// Choose between the Korean and English hypotheses.
    private func bestHypothesis() -> (String, DetectedLanguage, Double)? {
        var best: (String, DetectedLanguage, Double, Double)?
        for (language, session) in sessions {
            guard let h = session.latest, !h.text.isEmpty else { continue }
            let hangul = Hangul.hangulRatio(h.text)
            var score: Double = h.confidence > 0 ? h.confidence : 0.5
            if language == .korean { score += hangul > 0.5 ? 0.12 : -0.25 }
            if language == .english {
                if hangul > 0 { score -= 0.3 }
                if h.text.split(separator: " ").count >= 2 { score += 0.04 }
            }
            if language == preferredLanguage { score += 0.05 }
            if best == nil || score > best!.3 { best = (h.text, language, h.confidence, score) }
        }
        return best.map { ($0.0, $0.1, $0.2) }
    }

    // MARK: Watchdog

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                self.checkHealth()
            }
        }
    }

    private func checkHealth() {
        guard isRunning else { return }
        let hub = AudioEngineHub.shared
        let signal = router.health()
        // The microphone stopped delivering audio (interruption, route change, the Playground host…).
        if signal.sinceLastBuffer > 3 {
            recoverAudio(reason: "no microphone audio for \(Int(signal.sinceLastBuffer)) s")
            return
        }
        // Echo cancellation delivering only digital silence: fall back to the plain microphone.
        if hub.voiceProcessingEnabled && !heardAnything && signal.buffers > 200 && signal.sinceLastSound > 6 && !hub.isPlaying {
            Log.voice.error("Microphone delivers digital silence with echo cancellation; turning it off")
            onError?("에코 제거를 끄고 마이크를 다시 연결했습니다 · Echo cancellation was muting the microphone; it is now off.")
            hub.setVoiceProcessing(false)
            router.resetHealth()
            restartAll()
            return
        }
        guard !finalizing else { return }
        let wanted = wantedLanguages
        let now = Date()
        // Recycle long sessions (or long wake-mode transcripts) while the user is silent; begin
        // missing ones; drop unwanted ones.
        for (language, s) in sessions where !signal.speaking {
            let old: Bool = now.timeIntervalSince(s.started) > 55
            let wordy: Bool = mode == .wakeOnly && (s.latest?.text.count ?? 0) > 120
            guard old || wordy else { continue }
            end(language)
            scheduleBegin(language, after: 0.1)
        }
        for language in Array(sessions.keys) where !wanted.contains(language) { end(language) }
        for language in wanted where sessions[language] == nil && pendingBegins[language] == nil { begin(language) }
    }

    /// Restart the audio input (rate-limited so a broken route cannot cause a restart storm).
    private func recoverAudio(reason: String) {
        let now = Date()
        engineRecoveries = engineRecoveries.filter { now.timeIntervalSince($0) < 60 }
        guard engineRecoveries.count < 5 else { return }
        engineRecoveries.append(now)
        Log.voice.error("Restarting audio input: \(reason, privacy: .public)")
        do {
            try AudioEngineHub.shared.restartCapture()
            router.resetHealth()
            restartAll()
        } catch {
            let message = error.localizedDescription
            Log.voice.error("Audio input restart failed: \(message, privacy: .public)")
        }
    }
}

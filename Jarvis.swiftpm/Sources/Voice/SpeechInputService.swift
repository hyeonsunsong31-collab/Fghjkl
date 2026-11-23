import AVFoundation
import Speech

enum LanguageMode: String, Codable, CaseIterable {
    case auto, korean, english
}

/// Thread-safe bridge between the realtime audio tap and the recognisers.
private final class AudioRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [SFSpeechAudioBufferRecognitionRequest] = []
    private var vad = VoiceActivityDetector()
    private var lastMeterTime = Date.distantPast
    var onVAD: ((VoiceActivityDetector.Event) -> Void)?
    var onLevel: ((Float) -> Void)?

    func setRequests(_ r: [SFSpeechAudioBufferRecognitionRequest]) {
        lock.lock(); requests = r; lock.unlock()
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = requests
        lock.unlock()
        for r in current { r.append(buffer) }

        guard let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        let level = VoiceActivityDetector.level(UnsafeBufferPointer(start: data[0], count: n))
        let duration = Double(n) / max(1, buffer.format.sampleRate)
        lock.lock()
        let event = vad.process(levelDB: level, duration: duration)
        let meter = vad.meter
        lock.unlock()
        if let event { DispatchQueue.main.async { self.onVAD?(event) } }
        let now = Date()
        if now.timeIntervalSince(lastMeterTime) > 0.05 {
            lastMeterTime = now
            DispatchQueue.main.async { self.onLevel?(meter) }
        }
    }
}

/// On-device speech recognition for Korean and English **at the same time**.
///
/// Both recognisers hear the same audio; the language whose hypothesis is
/// more confident wins, so input/output language switches automatically
/// (requirement 2 & 25). In wake-only mode it scans partial transcripts for
/// "wake up Jarvis"; in conversation mode an energy VAD endpoints utterances
/// and reports speech onsets so Jarvis can be interrupted (requirement 13).
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
        var task: SFSpeechRecognitionTask?
        var latest: Hypothesis?
        let started = Date()
        init(language: DetectedLanguage, request: SFSpeechAudioBufferRecognitionRequest) {
            self.language = language
            self.request = request
        }
    }

    var onPartial: ((String) -> Void)?
    var onUtterance: ((String, DetectedLanguage, Double) -> Void)?
    var onWake: ((WakeWordMatcher.Match) -> Void)?
    var onSpeechActivity: ((Bool) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?

    var mode: ListeningMode = .wakeOnly { didSet { if oldValue != mode && isRunning { restartSessions() } } }
    var languageMode: LanguageMode = .auto { didSet { if oldValue != languageMode && isRunning { restartSessions() } } }
    var preferredLanguage: DetectedLanguage = .english
    var contextualStrings: [String] = ["Jarvis", "자비스", "hologram", "torus", "3D"]

    private(set) var isRunning = false
    private(set) var isAuthorized = false
    private let recognizers: [DetectedLanguage: SFSpeechRecognizer]
    private var sessions: [DetectedLanguage: Session] = [:]
    private let router = AudioRouter()
    private let wakeMatcher = WakeWordMatcher()
    private var finalizing = false
    private var finalizeDeadline: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

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
        return isAuthorized
    }

    // MARK: Lifecycle

    func start() async {
        guard !isRunning else { return }
        if !isAuthorized { _ = await requestAuthorization() }
        guard isAuthorized else {
            onError?("Speech or microphone permission denied")
            return
        }
        let hub = AudioEngineHub.shared
        let router = self.router
        // @Sendable: called on the realtime audio thread, so it must not inherit main-actor isolation.
        hub.onInputBuffer = { @Sendable (buffer: AVAudioPCMBuffer) in router.handle(buffer) }
        CrashLog.breadcrumb("audio: starting microphone")
        do {
            try hub.start(captureMicrophone: true)
        } catch {
            onError?("Audio engine failed: \(error.localizedDescription)")
            return
        }
        isRunning = true
        CrashLog.breadcrumb("speech: starting recognizers")
        beginSessions()
        startWatchdog()
        CrashLog.breadcrumb("speech: listening")
    }

    func stop() {
        isRunning = false
        watchdog?.cancel()
        finalizeDeadline?.cancel()
        cancelSessions()
        AudioEngineHub.shared.setMicrophoneCapture(false)
    }

    private var activeLanguages: [DetectedLanguage] {
        switch languageMode {
        case .english: return [.english]
        case .korean: return mode == .wakeOnly ? [.english, .korean] : [.korean]
        case .auto: return [.english, .korean]
        }
    }

    private func beginSessions() {
        guard isRunning else { return }
        finalizing = false
        var requests: [SFSpeechAudioBufferRecognitionRequest] = []
        for language in activeLanguages {
            guard let recognizer = recognizers[language], recognizer.isAvailable else { continue }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            request.addsPunctuation = true
            request.taskHint = .dictation
            request.contextualStrings = contextualStrings
            let session = Session(language: language, request: request)
            // @Sendable: the Speech framework calls this on its own queue.
            session.task = recognizer.recognitionTask(with: request) { @Sendable [weak self] (result: SFSpeechRecognitionResult?, error: Error?) in
                let hypothesis: Hypothesis? = result.map { (r: SFSpeechRecognitionResult) -> Hypothesis in
                    let segments = r.bestTranscription.segments
                    var total: Double = 0
                    for segment in segments { total += Double(segment.confidence) }
                    let confidence: Double = segments.isEmpty ? 0 : total / Double(segments.count)
                    return Hypothesis(text: r.bestTranscription.formattedString, confidence: confidence, isFinal: r.isFinal)
                }
                let failed: Bool = error != nil
                DispatchQueue.main.async {
                    self?.handle(hypothesis, failed: failed, language: language, session: session)
                }
            }
            sessions[language] = session
            requests.append(request)
        }
        router.setRequests(requests)
    }

    private func cancelSessions() {
        router.setRequests([])
        for s in sessions.values {
            s.request.endAudio()
            s.task?.cancel()
        }
        sessions.removeAll()
    }

    func restartSessions() {
        cancelSessions()
        beginSessions()
    }

    /// Periodically recycle long-running sessions (recognisers are not meant to run forever).
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.isRunning, !self.finalizing else { continue }
                let oldest = self.sessions.values.map(\.started).min() ?? Date()
                if Date().timeIntervalSince(oldest) > 50 || self.sessions.isEmpty {
                    self.restartSessions()
                }
            }
        }
    }

    // MARK: Results

    private func handle(_ hypothesis: Hypothesis?, failed: Bool, language: DetectedLanguage, session: Session) {
        guard isRunning, sessions[language] === session else { return }
        if let h = hypothesis {
            session.latest = h
            if !failed { consecutiveFailures = 0 }
        }

        switch mode {
        case .wakeOnly:
            if let text = hypothesis?.text, let match = wakeMatcher.match(text) {
                cancelSessions()
                onWake?(match)
                // `onWake` usually switches to conversation mode, which restarts sessions itself.
                if sessions.isEmpty { beginSessions() }
                return
            }
            if failed || hypothesis?.isFinal == true { restartSessionLater(afterFailure: failed) }
        case .conversation:
            if !finalizing, let best = bestHypothesis(includePartial: true) {
                onPartial?(best.0)
            }
            if finalizing {
                if sessions.values.allSatisfy({ $0.latest?.isFinal == true || $0.task?.state == .completed || $0.task == nil }) {
                    deliverUtterance()
                }
            } else if failed {
                restartSessionLater(afterFailure: true)
            } else if hypothesis?.isFinal == true {
                // The recogniser endpointed by itself.
                finalize()
            }
        }
    }

    private var restartPending = false
    private var consecutiveFailures = 0

    /// Restart recognition shortly; after repeated failures back off (0.3 s doubling up to 10 s)
    /// instead of hammering the Speech framework in a tight loop.
    private func restartSessionLater(afterFailure: Bool = false) {
        guard !restartPending else { return }
        restartPending = true
        if afterFailure { consecutiveFailures += 1 }
        let exponent = Double(min(max(consecutiveFailures - 1, 0), 6))
        let delay: Double = afterFailure ? min(10, 0.3 * pow(2, exponent)) : 0.3
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            self.restartPending = false
            if self.isRunning && !self.finalizing { self.restartSessions() }
        }
    }

    private func handleVAD(_ event: VoiceActivityDetector.Event) {
        switch event {
        case .speechStarted:
            onSpeechActivity?(true)
        case .speechEnded(let duration):
            onSpeechActivity?(false)
            guard isRunning else { return }
            if mode == .conversation, duration > 0.25 { finalize() }
            else if mode == .wakeOnly { restartSessionLater() }
        }
    }

    /// End the current utterance: flush the recognisers and wait briefly for final results.
    func finalize() {
        guard mode == .conversation, !finalizing, !sessions.isEmpty else { return }
        finalizing = true
        router.setRequests([])
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
        let choice = bestHypothesis(includePartial: true)
        cancelSessions()
        finalizing = false
        if let (text, language, confidence) = choice {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                preferredLanguage = language
                onUtterance?(trimmed, language, confidence)
            }
        }
        beginSessions()
    }

    /// Choose between the Korean and English hypotheses.
    private func bestHypothesis(includePartial: Bool) -> (String, DetectedLanguage, Double)? {
        var best: (String, DetectedLanguage, Double, Double)?
        for (language, session) in sessions {
            guard let h = session.latest, !h.text.isEmpty, includePartial || h.isFinal else { continue }
            let hangul = Hangul.hangulRatio(h.text)
            var score = h.confidence > 0 ? h.confidence : 0.5
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
}

import AVFoundation

/// Generation counter readable from any thread (the synthesizer calls back on its own queue).
private final class PlaybackToken: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return current }
    func advance() { lock.lock(); current += 1; lock.unlock() }
}

/// State of one `AVSpeechSynthesizer.write` rendering, shared with its background callback.
/// Guarantees the continuation is resumed exactly once (end marker, cancel or timeout).
private final class RenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var gotAudio = false
    private var done = false

    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

    var isDone: Bool { lock.lock(); defer { lock.unlock() }; return done }

    func markAudio() { lock.lock(); gotAudio = true; lock.unlock() }

    func finish() {
        lock.lock()
        guard !done, let c = continuation else { lock.unlock(); return }
        done = true
        continuation = nil
        let result = gotAudio
        lock.unlock()
        c.resume(returning: result)
    }
}

/// Speaks Jarvis' replies.
///
/// - English: **Kokoro-82M** British male neural voice (George by default);
///   until the model is installed, the best installed en-GB male system voice.
/// - Korean: the best installed ko-KR male system voice, formal register.
///
/// All audio is routed through `AudioEngineHub` (echo-cancelled), sentence by
/// sentence, so speech starts quickly while the language model is still
/// generating and can be cut off instantly (barge-in).
@MainActor
final class SpeechOutputService: NSObject, AVSpeechSynthesizerDelegate {
    var muted = false
    var englishVoice = "bm_george"
    /// Multiplier from the cerebellum / user preference.
    var rate: Float = 1
    private(set) var kokoroReady = false
    private(set) var isSpeaking = false {
        didSet {
            if oldValue && !isSpeaking { lastSpeechEnd = Date() }
            if oldValue != isSpeaking { onSpeakingChanged?(isSpeaking) }
        }
    }
    private var lastSpeechEnd = Date.distantPast
    var onSpeakingChanged: ((Bool) -> Void)?
    /// Text currently being spoken (used to reject our own echo during barge-in detection).
    private(set) var currentText = ""
    /// Sentences spoken recently (for rejecting our own voice picked up by the microphone).
    private var spokenHistory: [(text: String, time: Date)] = []

    private let synthesizer = AVSpeechSynthesizer()
    /// Test switch (launch argument -JarvisForceDirectSpeech YES): always exercise the
    /// direct-synthesizer fallback after rendering, the path that used to crash.
    private let forceDirectSpeech = UserDefaults.standard.bool(forKey: "JarvisForceDirectSpeech")
    private var queue: [(text: String, language: DetectedLanguage)] = []
    private var pumping = false
    private var generation = 0
    private let token = PlaybackToken()
    private var streamBuffer = ""
    private var directSpeechContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
        AudioEngineHub.shared.onPlaybackDrained = { [weak self] in
            guard let self else { return }
            if self.queue.isEmpty && !self.pumping { self.isSpeaking = false; self.currentText = "" }
        }
    }

    func setKokoroReady(_ ready: Bool) { kokoroReady = ready }

    // MARK: Public API

    /// Speak a complete text.
    func speak(_ text: String, language: DetectedLanguage) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        for sentence in Self.sentences(clean) { queue.append((sentence, language)) }
        pump()
    }

    /// Streaming: append newly generated text; complete sentences are spoken immediately.
    func appendStream(_ delta: String, language: DetectedLanguage) {
        streamBuffer += delta
        var sentences = Self.sentences(streamBuffer)
        guard sentences.count > 1 || Self.endsSentence(streamBuffer) else { return }
        let tail = Self.endsSentence(streamBuffer) ? "" : (sentences.popLast() ?? "")
        for s in sentences { queue.append((s, language)) }
        streamBuffer = tail
        pump()
    }

    func finishStream(language: DetectedLanguage) {
        let rest = streamBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        streamBuffer = ""
        if !rest.isEmpty { queue.append((rest, language)) }
        pump()
    }

    /// Stop immediately and discard everything queued.
    func stop() {
        generation += 1
        token.advance()
        queue.removeAll()
        streamBuffer = ""
        synthesizer.stopSpeaking(at: .immediate)
        directSpeechContinuation?.resume()
        directSpeechContinuation = nil
        AudioEngineHub.shared.stopPlayback()
        pumping = false
        isSpeaking = false
        currentText = ""
    }

    /// Is `heard` most likely Jarvis' own voice (echo) rather than the user?
    /// True when most of its words were spoken by Jarvis in the last few seconds.
    func isLikelyEcho(_ heard: String, within seconds: TimeInterval = 8) -> Bool {
        let now = Date()
        // Echo is only physically possible while (or just after) the speaker is playing.
        guard isSpeaking || now.timeIntervalSince(lastSpeechEnd) < 1.5 else { return false }
        let recent = spokenHistory.filter { now.timeIntervalSince($0.time) < seconds }.map(\.text).joined(separator: " ") + " " + currentText
        let spokenWords = Set(TextEncoder.tokens(recent))
        let heardWords = TextEncoder.tokens(heard)
        guard heardWords.count >= 2, !spokenWords.isEmpty else { return false }
        let overlap = heardWords.filter { spokenWords.contains($0) }.count
        return Double(overlap) / Double(heardWords.count) >= 0.7
    }

    // MARK: Pipeline

    private func pump() {
        guard !pumping else { return }
        guard !queue.isEmpty else { return }
        if muted { queue.removeAll(); return }
        pumping = true
        isSpeaking = true
        let gen = generation
        Task { [weak self] in
            guard let self else { return }
            while gen == self.generation, !self.queue.isEmpty {
                let item = self.queue.removeFirst()
                self.currentText = item.text
                self.spokenHistory.append((item.text, Date()))
                if self.spokenHistory.count > 12 { self.spokenHistory.removeFirst(self.spokenHistory.count - 12) }
                if item.language == .english && self.kokoroReady {
                    CrashLog.breadcrumb("speech: Kokoro synthesis")
                    let voice = self.englishVoice, speed = self.rate
                    let samples = (try? await KokoroEngine.shared.synthesize(item.text, voice: voice, speed: speed)) ?? []
                    guard gen == self.generation else { break }
                    if samples.isEmpty {
                        await self.speakWithSystemVoice(item.text, language: item.language, generation: gen)
                    } else {
                        AudioEngineHub.shared.play(samples: samples)
                    }
                } else {
                    await self.speakWithSystemVoice(item.text, language: item.language, generation: gen)
                }
            }
            if gen == self.generation {
                self.pumping = false
                if !AudioEngineHub.shared.isPlaying && self.queue.isEmpty { self.isSpeaking = false }
            }
        }
    }

    /// A fresh utterance every time: AVSpeechSynthesizer raises a fatal exception
    /// ("AVSpeechUtterance shouldn't be enqueued twice") if one instance is reused.
    private func makeUtterance(_ text: String, language: DetectedLanguage) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: language)
        let base: Float = AVSpeechUtteranceDefaultSpeechRate
        let scaled: Float = base * (language == .korean ? 1.0 : 0.96) * rate
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, scaled))
        utterance.pitchMultiplier = language == .korean ? 0.92 : 0.9
        utterance.prefersAssistiveTechnologySettings = false
        return utterance
    }

    /// Render a system voice into buffers routed through the echo-cancelled engine;
    /// if that yields no audio, let the synthesizer speak directly.
    private func speakWithSystemVoice(_ text: String, language: DetectedLanguage, generation gen: Int) async {
        CrashLog.breadcrumb("speech: system voice render")
        let rendered = await renderThroughEngine(makeUtterance(text, language: language), generation: gen,
                                                 timeout: 4 + Double(text.count) * 0.12)
        guard !rendered || forceDirectSpeech, gen == generation else { return }
        CrashLog.breadcrumb("speech: direct synthesizer fallback")
        synthesizer.stopSpeaking(at: .immediate)
        let direct = makeUtterance(text, language: language)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            directSpeechContinuation?.resume()
            directSpeechContinuation = c
            synthesizer.speak(direct)
        }
    }

    private func renderThroughEngine(_ utterance: AVSpeechUtterance, generation gen: Int, timeout: TimeInterval) async -> Bool {
        let token = self.token
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let state = RenderState(c)
            // Explicitly @Sendable: runs on the synthesizer's queue, never on the main actor.
            synthesizer.write(utterance) { @Sendable (buffer: AVAudioBuffer) in
                guard !state.isDone, let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    state.finish() // end of utterance
                    return
                }
                state.markAudio()
                if token.value == gen { AudioEngineHub.shared.play(buffer: pcm) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { state.finish() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.directSpeechContinuation?.resume()
            self.directSpeechContinuation = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.directSpeechContinuation?.resume()
            self.directSpeechContinuation = nil
        }
    }

    // MARK: Voices

    /// Best installed male voice for the language (premium > enhanced > default).
    static func bestVoice(for language: DetectedLanguage) -> AVSpeechSynthesisVoice? {
        let code = language == .korean ? "ko-KR" : "en-GB"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == code }
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch v.quality {
            case .premium: s += 30
            case .enhanced: s += 20
            default: s += 10
            }
            if v.gender == .male { s += 25 }
            if language == .english && ["Daniel", "Arthur", "Oliver", "Malcolm"].contains(where: { v.name.contains($0) }) { s += 6 }
            if v.voiceTraits.contains(.isNoveltyVoice) { s -= 100 }
            return s
        }
        return voices.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: code)
    }

    /// Names of the installed system voices (for Settings / diagnostics).
    static func voiceSummary(for language: DetectedLanguage) -> String {
        guard let v = bestVoice(for: language) else { return "—" }
        let q: String
        switch v.quality {
        case .premium: q = "Premium"
        case .enhanced: q = "Enhanced"
        default: q = "Default"
        }
        return "\(v.name) (\(q))"
    }

    // MARK: Sentence segmentation

    static func endsSentence(_ s: String) -> Bool {
        guard let last = s.trimmingCharacters(in: .whitespaces).last else { return false }
        return ".!?。…\n".contains(last)
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            let isEnd = ".!?。…\n".contains(ch)
            if isEnd {
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if ch == ".", next.isNumber { continue }
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.count >= 2 { out.append(s); current = "" }
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }
}

import AVFoundation

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
        didSet { if oldValue != isSpeaking { onSpeakingChanged?(isSpeaking) } }
    }
    var onSpeakingChanged: ((Bool) -> Void)?
    /// Text currently being spoken (used to reject our own echo during barge-in detection).
    private(set) var currentText = ""

    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [(text: String, language: DetectedLanguage)] = []
    private var pumping = false
    private var generation = 0
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
                if item.language == .english && self.kokoroReady {
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

    /// Render a system voice into buffers routed through the echo-cancelled engine.
    private func speakWithSystemVoice(_ text: String, language: DetectedLanguage, generation gen: Int) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: language)
        let base = AVSpeechUtteranceDefaultSpeechRate
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                             min(AVSpeechUtteranceMaximumSpeechRate, base * (language == .korean ? 1.0 : 0.96) * rate))
        utterance.pitchMultiplier = language == .korean ? 0.92 : 0.9
        utterance.prefersAssistiveTechnologySettings = false

        let rendered: Bool = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            var gotAudio = false
            var finished = false
            synthesizer.write(utterance) { buffer in
                guard !finished else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    finished = true
                    c.resume(returning: gotAudio)
                    return
                }
                gotAudio = true
                if gen == self.generation { AudioEngineHub.shared.play(buffer: pcm) }
            }
        }
        if !rendered && gen == generation {
            // Fallback: let the synthesizer play directly.
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                directSpeechContinuation = c
                synthesizer.speak(utterance)
            }
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

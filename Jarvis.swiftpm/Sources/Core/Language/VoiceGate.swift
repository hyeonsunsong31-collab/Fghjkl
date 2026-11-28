import Foundation

/// Decides which recognised speech reaches Jarvis, and when speech may interrupt it.
///
/// On a real device the microphone also hears Jarvis' own voice, keyboard clicks while the user
/// types, and room noise. Without a gate those fragments became "commands" that cancelled what the
/// user had just typed or asked, so neither typing nor talking seemed to work.
enum VoiceGate {
    struct Context {
        var jarvisSpeaking = false
        /// Seconds since Jarvis last finished speaking (large when it hasn't spoken).
        var secondsSinceSpeechEnded: Double = 999
        /// What Jarvis said in the last few seconds (including what it is saying now).
        var spokenRecently = ""
        /// The text field is focused or the user typed in the last seconds.
        var typing = false
        /// The user holds the push-to-talk button: everything heard is meant for Jarvis.
        var pushToTalk = false
        var secondsSinceLastUtterance: Double = 999
        var lastUtterance = ""
        /// The user cut Jarvis off a moment ago: what follows is the user's own speech.
        var userInterrupted = false
    }

    enum Decision: Equatable {
        case accept
        case drop(String)
    }

    static let bargeInWords = ["stop", "wait", "cancel", "enough", "quiet", "shut up", "hold on", "pause", "jarvis",
                               "그만", "잠깐", "멈춰", "취소", "조용", "자비스", "스톱", "중지"]
    static let fillers: Set<String> = ["uh", "um", "umm", "hmm", "hm", "mm", "mhm", "ah", "oh", "er", "erm", "huh", "eh", "ha",
                                       "어", "음", "아", "응", "흠", "으", "에", "오", "엄", "흐음", "아아"]
    /// Short replies that are complete commands on their own.
    static let shortReplies: Set<String> = ["yes", "no", "yeah", "yep", "nope", "ok", "okay", "stop", "pause", "next", "cancel", "sure",
                                            "네", "예", "응", "아니", "아니요", "아뇨", "그만", "다음", "취소", "좋아"]

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Does the text speak to Jarvis by name?
    static func addressed(_ text: String) -> Bool {
        let t = tokens(text)
        if t.contains(where: { WakeWordMatcher.isJarvis($0) }) { return true }
        return ["자비스", "쟈비스", "재비스"].contains { text.contains($0) }
    }

    static func containsBargeInWord(_ text: String) -> Bool {
        let lower = " " + tokens(text).joined(separator: " ") + " "
        for w in bargeInWords {
            if w.unicodeScalars.allSatisfy({ $0.isASCII }) {
                if lower.contains(" " + w + " ") { return true }
            } else if text.contains(w) {
                return true
            }
        }
        return addressed(text)
    }

    /// "Stop" / "cancel" / "그만": may interrupt anything at once.
    static func isStopCommand(_ text: String) -> Bool {
        let t = tokens(text)
        guard t.count <= 4 else { return false }
        let stops: Set<String> = ["stop", "cancel", "enough", "quiet", "그만", "그만해", "취소", "멈춰", "중지", "스톱", "조용히", "조용"]
        return t.contains { stops.contains($0) }
    }

    /// Share of the heard words that Jarvis itself just said (0…1).
    static func echoSimilarity(_ heard: String, spoken: String) -> Double {
        let h = tokens(heard)
        let s = Set(tokens(spoken))
        guard !h.isEmpty, !s.isEmpty else { return 0 }
        let overlap = h.filter { s.contains($0) }.count
        return Double(overlap) / Double(h.count)
    }

    /// Words any two English sentences tend to share; they say nothing about an echo.
    static let functionWords: Set<String> = ["a", "an", "the", "and", "or", "to", "of", "in", "on", "at", "it", "is", "be",
                                             "i", "you", "your", "me", "my", "we", "for", "are", "with", "this", "that",
                                             "have", "has", "was", "will", "can", "all", "now", "sir", "please", "so", "do"]

    /// Like `echoSimilarity`, counting only content words ("cube", "weather", "큐브").
    static func contentSimilarity(_ heard: String, spoken: String) -> Double {
        func content(_ t: [String]) -> [String] {
            let kept = t.filter { !functionWords.contains($0) }
            return kept.isEmpty ? t : kept
        }
        let h = content(tokens(heard))
        let s = Set(content(tokens(spoken)))
        guard !h.isEmpty, !s.isEmpty else { return 0 }
        let overlap = h.filter { s.contains($0) }.count
        return Double(overlap) / Double(h.count)
    }

    /// While Jarvis talks: is this plainly the user's own sentence rather than Jarvis heard back?
    static func unlikeSpeech(_ text: String, spoken: String) -> Bool {
        guard tokens(text).count >= 2 else { return false }
        guard !spoken.isEmpty else { return true }
        return echoSimilarity(text, spoken: spoken) < 0.4 && contentSimilarity(text, spoken: spoken) < 0.4
    }

    /// Should this finished utterance become a command?
    static func utterance(_ text: String, confidence: Double, context c: Context) -> Decision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = tokens(trimmed)
        guard !words.isEmpty else { return .drop("empty") }
        if words.allSatisfy({ fillers.contains($0) }) { return .drop("filler") }
        let named = addressed(trimmed)
        let echoWindow = c.jarvisSpeaking || c.secondsSinceSpeechEnded < 2.5
        if echoWindow && !c.spokenRecently.isEmpty {
            let similarity = echoSimilarity(trimmed, spoken: c.spokenRecently)
            // Jarvis hearing itself (also when the echo contains its name, e.g. "Jarvis at your service").
            if similarity >= 0.6 && (words.count >= 2 || !named) { return .drop("echo") }
        }
        if c.pushToTalk { return .accept }
        // While Jarvis talks the microphone mostly hears Jarvis itself. An interruption, speech
        // addressed to Jarvis, or a sentence plainly unlike what Jarvis is saying gets through.
        if c.jarvisSpeaking && !containsBargeInWord(trimmed) && !unlikeSpeech(trimmed, spoken: c.spokenRecently) {
            return .drop("while speaking")
        }
        if c.secondsSinceSpeechEnded < 0.7 && !c.userInterrupted && !named && !isStopCommand(trimmed)
            && !unlikeSpeech(trimmed, spoken: c.spokenRecently) {
            return .drop("speech tail")
        }
        // The microphone hears the keyboard: while typing, only speech addressed to Jarvis counts.
        if c.typing && !named && !isStopCommand(trimmed) { return .drop("typing") }
        if c.secondsSinceLastUtterance < 2.5 && tokens(c.lastUtterance) == words { return .drop("duplicate") }
        if words.count == 1 && confidence > 0 && confidence < 0.3 && !shortReplies.contains(words[0]) && !named {
            return .drop("unclear")
        }
        return .accept
    }

    /// May this partial transcript cut Jarvis off mid-sentence?
    static func bargeIn(partial: String, context c: Context) -> Bool {
        guard c.jarvisSpeaking else { return false }
        let words = tokens(partial)
        guard !words.isEmpty, !words.allSatisfy({ fillers.contains($0) }) else { return false }
        let similarity = echoSimilarity(partial, spoken: c.spokenRecently)
        if containsBargeInWord(partial) && similarity < 0.6 { return true }
        // A clearly different sentence (not an echo) also interrupts.
        return words.count >= 4 && similarity < 0.3
    }
}

extension WakeWordMatcher {
    /// "Jarvis, open YouTube" / "Hey Jarvis …" / "자비스 음악 틀어줘": a command addressed by name,
    /// accepted even while Jarvis is asleep (only the name and at least one more word).
    func matchNamePrefix(_ transcript: String) -> Match? {
        let original = transcript.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !original.isEmpty else { return nil }
        var i = 0
        let lead: Set<String> = ["hey", "ok", "okay", "hi", "yo", "oi"]
        while i < original.count - 1 && lead.contains(original[i].lowercased().filter { $0.isLetter }) { i += 1 }
        let first = original[i]
        let letters = first.lowercased().filter { $0.isLetter }
        // Korean: "자비스", "자비스야", "자비스," — possibly glued to the command ("자비스음악틀어줘").
        for name in ["자비스", "쟈비스", "재비스"] where first.hasPrefix(name) {
            var rest = String(first.dropFirst(name.count))
            for vocative in ["야", "아", "님"] where rest.hasPrefix(vocative) { rest.removeFirst(vocative.count) }
            rest = rest.trimmingCharacters(in: CharacterSet.punctuationCharacters)
            let tail = ([rest] + original[(i + 1)...]).filter { !$0.isEmpty }.joined(separator: " ")
                .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
            return tail.count >= 2 ? Match(trailingCommand: tail, confidence: 0.8, language: .korean) : nil
        }
        guard Self.isJarvis(letters), i + 1 < original.count else { return nil }
        let tail = original[(i + 1)...].joined(separator: " ").trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        guard tail.count >= 2 else { return nil }
        return Match(trailingCommand: tail, confidence: 0.75, language: .english)
    }
}

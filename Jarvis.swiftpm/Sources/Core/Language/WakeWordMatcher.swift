import Foundation

/// Detects the wake phrase **"wake up Jarvis"** in streaming speech transcripts,
/// tolerating recogniser errors ("wake up jervis", "wakeup javis", "wake of
/// Jarvis") and Korean renderings ("웨이크 업 자비스", "자비스 일어나").
struct WakeWordMatcher {
    struct Match: Equatable {
        /// Text spoken after the wake phrase (a command to run immediately), if any.
        var trailingCommand: String
        var confidence: Double
        var language: DetectedLanguage
    }

    static let canonical = "wake up jarvis"
    static let response = "Jarvis at your service, sir."

    private static let wakeVariants: Set<String> = ["wake", "wakes", "woke", "weak", "wait", "make", "wade", "way"]
    private static let upVariants: Set<String> = ["up", "app", "op", "a", "of", "upp"]
    private static let koreanPhrases = ["웨이크업자비스", "웨이크업쟈비스", "웨이크업자비즈", "자비스일어나", "자비스깨어나", "자비스기상", "자비스일어나세요", "자비스깨어나라",
                                        "일어나자비스", "깨어나자비스"]
    /// "Jarvis" as the Korean recogniser writes it (also with a vocative: "자비스야").
    private static let koreanJarvis = ["자비스", "쟈비스", "재비스", "자비즈", "자비쓰"]
    /// The Korean recogniser often keeps English words in Latin letters ("Wake up 자비스").
    private static let latinToHangul: [(String, String)] = [("wake up", "웨이크업"), ("wake-up", "웨이크업"), ("wakeup", "웨이크업"), ("jarvis", "자비스")]

    /// Is `word` a plausible recognition of "Jarvis"?
    static func isJarvis(_ word: String) -> Bool {
        let w = word.lowercased().filter { $0.isLetter }
        if w.isEmpty { return false }
        if koreanJarvis.contains(where: { w.hasPrefix($0) }) { return true }
        if ["jarvis", "jervis", "javis", "jarvas", "jarviss", "jarvish", "jarvi", "jarves", "jarvus", "garvis", "travis", "charvis", "jaravis"].contains(w) { return true }
        if FuzzyMatch.distance(w, "jarvis") <= 2 && (w.hasPrefix("j") || w.hasPrefix("ch") || w.hasPrefix("g")) { return true }
        return FuzzyMatch.phoneticKey(w) == FuzzyMatch.phoneticKey("jarvis")
    }

    func match(_ transcript: String) -> Match? {
        if let m = matchEnglish(transcript) { return m }
        return matchKorean(transcript)
    }

    private func matchEnglish(_ transcript: String) -> Match? {
        let original = transcript.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let tokens = original.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        guard !tokens.isEmpty else { return nil }

        for i in tokens.indices {
            // "wake up jarvis" (3 tokens) or "wakeup jarvis" (2 tokens)
            var jarvisIndex: Int?
            var confidence = 0.0
            if i + 2 < tokens.count, Self.wakeVariants.contains(tokens[i]), Self.upVariants.contains(tokens[i + 1]), Self.isJarvis(tokens[i + 2]) {
                jarvisIndex = i + 2
                confidence = tokens[i] == "wake" && tokens[i + 1] == "up" && tokens[i + 2] == "jarvis" ? 1 : 0.8
            } else if i + 1 < tokens.count, ["wakeup", "wakup", "wakeapp"].contains(tokens[i]), Self.isJarvis(tokens[i + 1]) {
                jarvisIndex = i + 1
                confidence = 0.85
            } else if i + 2 < tokens.count, Self.isJarvis(tokens[i]), Self.wakeVariants.contains(tokens[i + 1]), Self.upVariants.contains(tokens[i + 2]) {
                // "Jarvis, wake up"
                jarvisIndex = i + 2
                confidence = 0.75
            }
            guard let j = jarvisIndex else { continue }
            let rest = original[(j + 1)...].joined(separator: " ")
                .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
            return Match(trailingCommand: rest, confidence: confidence, language: .english)
        }
        return nil
    }

    private func matchKorean(_ transcript: String) -> Match? {
        var unified = transcript
        for (latin, hangul) in Self.latinToHangul {
            unified = unified.replacingOccurrences(of: latin, with: hangul, options: .caseInsensitive)
        }
        let compact = unified.replacingOccurrences(of: " ", with: "")
            .filter { !$0.isPunctuation }
        guard Hangul.hangulRatio(compact) > 0 else { return nil }
        let jamoCompact = Array(Hangul.decompose(compact))
        var best: (phrase: String, end: Int, score: Double)?
        for phrase in Self.koreanPhrases {
            let p = Array(Hangul.decompose(phrase))
            guard jamoCompact.count >= p.count - 2 else { continue }
            // Slide a window of the phrase length (±1) over the transcript.
            for len in max(1, p.count - 1)...(p.count + 1) where len <= jamoCompact.count {
                for start in 0...(jamoCompact.count - len) {
                    let window = Array(jamoCompact[start..<(start + len)])
                    let d = FuzzyMatch.distance(window, p)
                    let score = 1 - Double(d) / Double(p.count)
                    if score >= 0.8, score > (best?.score ?? 0) {
                        best = (phrase, start + len, score)
                    }
                }
            }
        }
        guard let b = best else { return nil }
        // Map the jamo end index back to a character offset in the compact string.
        var jamoCount = 0
        var charEnd = compact.endIndex
        for idx in compact.indices {
            jamoCount += Hangul.decompose(String(compact[idx])).count
            if jamoCount >= b.end { charEnd = compact.index(after: idx); break }
        }
        var rest = String(compact[charEnd...])
        // Drop vocative/sentence endings left over ("요", "라").
        for suffix in ["요", "라", "세요"] where rest.hasPrefix(suffix) { rest.removeFirst(suffix.count) }
        return Match(trailingCommand: rest, confidence: b.score, language: .korean)
    }
}

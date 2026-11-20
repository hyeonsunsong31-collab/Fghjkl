import Foundation

/// Pronunciation dictionary in misaki format: word → phonemes, or word → {POS: phonemes}.
final class PronunciationLexicon {
    enum Entry: Equatable {
        case simple(String)
        case heteronym([String: String])

        func resolve(pos: String?) -> String? {
            switch self {
            case .simple(let p): return p
            case .heteronym(let map):
                if let pos, let p = map[pos] { return p }
                return map["DEFAULT"] ?? map.values.first
            }
        }
    }

    private(set) var entries: [String: Entry] = [:]

    init() {}

    /// Load one or more misaki JSON dictionaries (later ones do not override earlier ones).
    func load(jsonData: Data) throws {
        guard let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return }
        for (word, value) in obj where entries[word] == nil {
            if let s = value as? String {
                entries[word] = .simple(s)
            } else if let d = value as? [String: Any] {
                var map: [String: String] = [:]
                for (k, v) in d { if let s = v as? String { map[k] = s } }
                if !map.isEmpty { entries[word] = .heteronym(map) }
            }
        }
    }

    func add(_ word: String, _ phonemes: String) { entries[word] = .simple(phonemes) }

    func lookup(_ word: String, pos: String? = nil) -> String? {
        if let e = entries[word] { return e.resolve(pos: pos) }
        let lower = word.lowercased()
        if let e = entries[lower] { return e.resolve(pos: pos) }
        let cap = lower.prefix(1).uppercased() + lower.dropFirst()
        if let e = entries[cap] { return e.resolve(pos: pos) }
        return nil
    }

    var count: Int { entries.count }
}

/// British-English grapheme-to-phoneme front-end for Kokoro-82M.
///
/// Pipeline: normalise → split words/punctuation → special cases → misaki GB
/// dictionaries (gold, then silver) → suffix stemming (-s, -ed, -ing) →
/// neural G2P fallback (Core ML BART, US phonemes converted to GB) →
/// rule-based letter-to-sound as a last resort → Kokoro token ids.
final class KokoroPhonemizer {
    let lexicon: PronunciationLexicon
    /// Kokoro phoneme vocabulary (character → id).
    let vocab: [Character: Int]
    /// Optional neural fallback for out-of-vocabulary words (returns US phonemes).
    var neuralFallback: ((String) -> String?)?

    static let padID = 0
    static let maxTokens = 128

    static let specials: [String: String] = [
        "jarvis": "ʤˈɑːvɪs", "a": "ɐ", "ipad": "ˈIpad", "iphone": "ˈIfQn", "ios": "ˌIˌQˈɛs", "ai": "ˌAˈI",
        "usdz": "jˌuːˌɛsdˌiːzˈɛd", "wi-fi": "wˈIfI", "wifi": "wˈIfI", "kakaotalk": "kˈɑːkaʊtˌɔːk",
        "okay": "ˌQkˈA", "ok": "ˌQkˈA", "sir": "sˈɜː"
    ]

    init(lexicon: PronunciationLexicon, vocab: [Character: Int]) {
        self.lexicon = lexicon
        self.vocab = vocab
    }

    /// Parse Kokoro's `vocab_index.json` ({"vocab": {char: id}}).
    static func loadVocab(jsonData: Data) throws -> [Character: Int] {
        guard let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let table = (obj["vocab"] as? [String: Any]) ?? (obj as [String: Any]?) else { return [:] }
        var out: [Character: Int] = [:]
        for (k, v) in table {
            guard k.count == 1, let ch = k.first else { continue }
            if let n = v as? Int { out[ch] = n } else if let n = v as? NSNumber { out[ch] = n.intValue }
        }
        return out
    }

    // MARK: Text → phonemes

    func phonemize(_ text: String) -> String {
        let normalized = EnglishNormalizer.normalize(expandContractions(text))
        var result = ""
        var word = ""
        func flushWord() {
            guard !word.isEmpty else { return }
            if !result.isEmpty && !result.hasSuffix(" ") { result += " " }
            result += phonemes(forWord: word)
            word = ""
        }
        for ch in normalized {
            if ch.isLetter || ch == "'" || ch == "-" && !word.isEmpty {
                word.append(ch)
            } else if ch.isNumber {
                word.append(ch)
            } else {
                flushWord()
                if let p = Self.punctuation(ch) {
                    while result.hasSuffix(" ") { result.removeLast() }
                    result += p
                    if p != " " { result += " " }
                } else if ch.isWhitespace, !result.hasSuffix(" ") {
                    result += " "
                }
            }
        }
        flushWord()
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func punctuation(_ ch: Character) -> String? {
        switch ch {
        case ",", "，", "、": return ","
        case ".", "。": return "."
        case "!", "！": return "!"
        case "?", "？": return "?"
        case ";", "；": return ";"
        case ":", "：": return ":"
        case "—", "–": return "—"
        case "…": return "…"
        default: return nil
        }
    }

    func expandContractions(_ text: String) -> String {
        // Dictionaries cover most contractions directly; only normalise curly apostrophes.
        text.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
    }

    func phonemes(forWord raw: String) -> String {
        let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'-"))
        guard !word.isEmpty else { return "" }
        let lower = word.lowercased()
        if let s = Self.specials[lower] { return s }
        if let p = lexicon.lookup(word) { return p }
        if word.contains("-") {
            return word.split(separator: "-").map { phonemes(forWord: String($0)) }.joined(separator: " ")
        }
        if let p = stemAndLookup(lower) { return p }
        if word.count > 1, word == word.uppercased(), word.allSatisfy({ $0.isLetter }) {
            // Acronym: spell it out.
            return word.map { lexicon.lookup(String($0)) ?? String($0).lowercased() }.joined()
        }
        if let neural = neuralFallback?(lower), !neural.isEmpty { return Self.americanToBritish(neural) }
        return RuleG2P.convert(lower)
    }

    // MARK: Suffix stemming (misaki-style)

    func stemAndLookup(_ w: String) -> String? {
        // -s / -es / -ies
        if w.hasSuffix("ies"), w.count > 4, let p = lexicon.lookup(String(w.dropLast(3)) + "y") { return p + "z" }
        if w.hasSuffix("es"), w.count > 3, let p = lexicon.lookup(String(w.dropLast(2))) {
            return p + (Self.endsWithSibilant(p) ? "ɪz" : "z")
        }
        if w.hasSuffix("s"), !w.hasSuffix("ss"), w.count > 2, let p = lexicon.lookup(String(w.dropLast())) {
            if Self.endsWithSibilant(p) { return p + "ɪz" }
            return p + (Self.endsVoiceless(p) ? "s" : "z")
        }
        // -ed
        if w.hasSuffix("ied"), w.count > 4, let p = lexicon.lookup(String(w.dropLast(3)) + "y") { return p + "d" }
        if w.hasSuffix("ed"), w.count > 3 {
            let stem = String(w.dropLast(2))
            let candidates = [stem, stem + "e", Self.undouble(stem)].compactMap { $0 }
            for c in candidates {
                if let p = lexicon.lookup(c) {
                    if p.hasSuffix("t") || p.hasSuffix("d") { return p + "ɪd" }
                    return p + (Self.endsVoiceless(p) ? "t" : "d")
                }
            }
        }
        // -ing
        if w.hasSuffix("ing"), w.count > 4 {
            let stem = String(w.dropLast(3))
            let candidates = [stem, stem + "e", Self.undouble(stem)].compactMap { $0 }
            for c in candidates { if let p = lexicon.lookup(c) { return p + "ɪŋ" } }
        }
        // -ly, -er, -est
        if w.hasSuffix("ly"), w.count > 4, let p = lexicon.lookup(String(w.dropLast(2))) { return p + "li" }
        return nil
    }

    static func undouble(_ stem: String) -> String? {
        guard stem.count >= 3, let last = stem.last, stem.dropLast().last == last, !"aeiou".contains(last) else { return nil }
        return String(stem.dropLast())
    }

    static func endsWithSibilant(_ p: String) -> Bool {
        guard let l = p.last else { return false }
        return "szʃʒʧʤ".contains(l)
    }

    static func endsVoiceless(_ p: String) -> Bool {
        guard let l = p.last else { return false }
        return "ptkfθ".contains(l)
    }

    /// Convert US-style misaki phonemes (from the neural G2P) to the GB inventory.
    static func americanToBritish(_ us: String) -> String {
        var s = us
        let rules: [(String, String)] = [
            ("ɜɹ", "ɜː"), ("ɑɹ", "ɑː"), ("ɔɹ", "ɔː"), ("ɪɹ", "ɪə"), ("ɛɹ", "ɛə"), ("ʊɹ", "ʊə"),
            ("O", "Q"), ("æ", "a"), ("ɾ", "t"), ("ᵻ", "ɪ"), ("ʔ", "t")
        ]
        for (a, b) in rules { s = s.replacingOccurrences(of: a, with: b) }
        // Non-rhotic: drop ɹ that is not followed by a vowel.
        let vowels = Set("aeiouAIOQWYɑɒɔəɛɜɪʊʌᵊ")
        var out = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            if c == "ɹ" {
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                let nextIsVowel = next.map { vowels.contains($0) || $0 == "ˈ" || $0 == "ˌ" } ?? false
                if !nextIsVowel { continue }
            }
            if c == "ɑ" && (i + 1 >= chars.count || chars[i + 1] != "ː") { out.append("ɒ"); continue }
            out.append(c)
        }
        return out
    }

    // MARK: Tokens

    func tokenIDs(_ phonemes: String) -> [Int] {
        phonemes.compactMap { vocab[$0] }
    }

    /// Split text into chunks whose token sequences (plus BOS/EOS) fit the model window.
    func chunks(for text: String, maxTokens: Int = KokoroPhonemizer.maxTokens - 2) -> [(text: String, ids: [Int])] {
        var output: [(String, [Int])] = []
        for sentence in Self.sentences(text) {
            let ids = tokenIDs(phonemize(sentence))
            if ids.isEmpty { continue }
            if ids.count <= maxTokens {
                output.append((sentence, ids))
                continue
            }
            // Split long sentences at commas, then at word boundaries.
            var pieces = sentence.components(separatedBy: ", ").filter { !$0.isEmpty }
            if pieces.count == 1 { pieces = sentence.split(separator: " ").map(String.init) }
            var current = ""
            for piece in pieces {
                let candidate = current.isEmpty ? piece : current + (sentence.contains(", ") ? ", " : " ") + piece
                if tokenIDs(phonemize(candidate)).count > maxTokens, !current.isEmpty {
                    output.append((current, Array(tokenIDs(phonemize(current)).prefix(maxTokens))))
                    current = piece
                } else {
                    current = candidate
                }
            }
            if !current.isEmpty { output.append((current, Array(tokenIDs(phonemize(current)).prefix(maxTokens)))) }
        }
        return output
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            if ".!?;\n".contains(ch) {
                // Don't split decimals ("3.5") or abbreviations ("Mr.").
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if ch == ".", next.isNumber { continue }
                let lastWord = current.split(separator: " ").last.map { String($0).lowercased() } ?? ""
                if ch == ".", EnglishNormalizer.abbreviations[lastWord] != nil { continue }
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(s) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }
}

/// Last-resort rule-based English letter-to-sound conversion (GB inventory).
enum RuleG2P {
    static let rules: [(String, String)] = [
        ("tion", "ʃən"), ("sion", "ʒən"), ("ough", "ɔː"), ("augh", "ɔː"), ("igh", "I"), ("eigh", "A"),
        ("sch", "sk"), ("tch", "ʧ"), ("dge", "ʤ"), ("ture", "ʧə"),
        ("sh", "ʃ"), ("ch", "ʧ"), ("th", "θ"), ("ph", "f"), ("wh", "w"), ("ck", "k"), ("ng", "ŋ"), ("qu", "kw"),
        ("ee", "iː"), ("ea", "iː"), ("oo", "uː"), ("ou", "W"), ("ow", "Q"), ("ai", "A"), ("ay", "A"),
        ("oi", "Y"), ("oy", "Y"), ("au", "ɔː"), ("aw", "ɔː"), ("ie", "iː"), ("ue", "uː"), ("ew", "juː"),
        ("ar", "ɑː"), ("or", "ɔː"), ("er", "ə"), ("ir", "ɜː"), ("ur", "ɜː"),
        ("a", "a"), ("e", "ɛ"), ("i", "ɪ"), ("o", "ɒ"), ("u", "ʌ"),
        ("c", "k"), ("x", "ks"), ("j", "ʤ"), ("g", "ɡ"), ("q", "k"), ("y", "j"),
        ("b", "b"), ("d", "d"), ("f", "f"), ("h", "h"), ("k", "k"), ("l", "l"), ("m", "m"), ("n", "n"),
        ("p", "p"), ("r", "ɹ"), ("s", "s"), ("t", "t"), ("v", "v"), ("w", "w"), ("z", "z")
    ]

    static func convert(_ word: String) -> String {
        var w = word.lowercased().filter { $0.isLetter }
        guard !w.isEmpty else { return "" }
        // Silent final e lengthens the previous vowel (make, time, home, cute).
        var magicE = false
        if w.count > 3, w.hasSuffix("e"), let prev = w.dropLast().last, !"aeiou".contains(prev) {
            w.removeLast(); magicE = true
        }
        var out = ""
        var i = w.startIndex
        while i < w.endIndex {
            var matched = false
            for (g, p) in rules where w[i...].hasPrefix(g) {
                var phon = p
                // Final -y as a vowel.
                if g == "y", w.index(after: i) == w.endIndex, out.count > 0 { phon = "i" }
                out += phon
                i = w.index(i, offsetBy: g.count)
                matched = true
                break
            }
            if !matched { i = w.index(after: i) }
        }
        if magicE {
            let long: [Character: String] = ["a": "A", "ɛ": "iː", "ɪ": "I", "ɒ": "Q", "ʌ": "juː"]
            if let idx = out.lastIndex(where: { long[$0] != nil }) {
                out.replaceSubrange(idx...idx, with: long[out[idx]]!)
            }
        }
        // Primary stress before the first vowel.
        let vowels = Set("aeiouAIOQWYɑɒɔəɛɜɪʊʌ")
        if let v = out.firstIndex(where: { vowels.contains($0) }) { out.insert("ˈ", at: v) }
        return out
    }
}

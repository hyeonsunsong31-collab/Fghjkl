import Foundation

/// String similarity helpers used for robust command and wake-word matching.
enum FuzzyMatch {
    /// Levenshtein distance over arbitrary equatable sequences.
    static func distance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    static func distance(_ a: String, _ b: String) -> Int {
        distance(Array(a), Array(b))
    }

    /// 1 − normalised edit distance, computed on jamo for Hangul text.
    static func similarity(_ a: String, _ b: String) -> Double {
        let ja = Array(Hangul.decompose(a.lowercased())), jb = Array(Hangul.decompose(b.lowercased()))
        let longest = max(ja.count, jb.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(distance(ja, jb)) / Double(longest)
    }

    /// Does `word` approximately equal `target`? Short words must match exactly.
    static func approximately(_ word: String, _ target: String) -> Bool {
        if word == target { return true }
        let n = target.count
        if n < 6 { return false }
        let allowed = n >= 9 ? 2 : 1
        return abs(word.count - n) <= allowed && distance(word, target) <= allowed
    }

    /// Crude English phonetic key (consonant skeleton with common confusions merged).
    static func phoneticKey(_ word: String) -> String {
        var s = word.lowercased().filter { $0.isLetter }
        let replacements: [(String, String)] = [("ph", "f"), ("ck", "k"), ("qu", "kw"), ("wh", "w"), ("sh", "s"),
                                                ("ch", "j"), ("tr", "j"), ("dg", "j"), ("gh", ""), ("kn", "n")]
        for (a, b) in replacements { s = s.replacingOccurrences(of: a, with: b) }
        var out = ""
        for (i, ch) in s.enumerated() {
            var c = ch
            switch c {
            case "c", "q": c = "k"
            case "z": c = "s"
            case "v": c = "f"
            case "y" where i > 0: c = "i"
            default: break
            }
            if "aeiou".contains(c) {
                if i == 0 { out.append("a") }
                continue
            }
            if out.last != c { out.append(c) }
        }
        return out
    }
}

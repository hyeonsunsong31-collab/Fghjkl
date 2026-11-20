import Foundation

/// Hangul utilities: syllable ↔ jamo decomposition for fuzzy Korean matching.
enum Hangul {
    static let syllableBase: UInt32 = 0xAC00
    static let syllableEnd: UInt32 = 0xD7A3
    static let leads: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let vowels: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    static let tails: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map { Optional($0) }

    static func isSyllable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= syllableBase && scalar.value <= syllableEnd
    }

    static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        isSyllable(scalar) || (0x3131...0x318E).contains(scalar.value) || (0x1100...0x11FF).contains(scalar.value)
    }

    /// Decompose Hangul syllables into compatibility jamo; other characters pass through.
    static func decompose(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            guard isSyllable(s) else { out.append(s); continue }
            let index = Int(s.value - syllableBase)
            let lead = index / (21 * 28)
            let vowel = (index % (21 * 28)) / 28
            let tail = index % 28
            out.append(contentsOf: String(leads[lead]).unicodeScalars)
            out.append(contentsOf: String(vowels[vowel]).unicodeScalars)
            if let t = tails[tail] { out.append(contentsOf: String(t).unicodeScalars) }
        }
        return String(out)
    }

    /// Fraction of letters that are Hangul.
    static func hangulRatio(_ text: String) -> Double {
        var hangul = 0, letters = 0
        for s in text.unicodeScalars {
            if isHangul(s) { hangul += 1; letters += 1 }
            else if s.properties.isAlphabetic { letters += 1 }
        }
        return letters == 0 ? 0 : Double(hangul) / Double(letters)
    }

    /// Does the final syllable have a batchim (final consonant)? Used to choose
    /// Korean particles (을/를, 이/가, 은/는, 으로/로).
    static func hasBatchim(_ word: String) -> Bool {
        guard let last = word.unicodeScalars.last(where: { isSyllable($0) }) else { return false }
        return (last.value - syllableBase) % 28 != 0
    }

    static func objectParticle(for word: String) -> String { hasBatchim(word) ? "을" : "를" }
    static func subjectParticle(for word: String) -> String { hasBatchim(word) ? "이" : "가" }
    static func topicParticle(for word: String) -> String { hasBatchim(word) ? "은" : "는" }
}

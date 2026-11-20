import Foundation

/// The two default languages of Jarvis.
enum DetectedLanguage: String, Codable, CaseIterable {
    case korean = "ko"
    case english = "en"

    var localeIdentifier: String { self == .korean ? "ko-KR" : "en-GB" }
    var displayName: String { self == .korean ? "한국어" : "English" }
}

/// Heuristic language identification for Korean/English input.
///
/// The app layer refines this with `NLLanguageRecognizer`; this core version is
/// deterministic and testable. Mixed input (e.g. "3D 공간 열어줘") counts as
/// Korean as soon as Hangul carries meaningful weight, because the grammatical
/// frame of such sentences is Korean.
enum LanguageDetector {
    struct Result: Equatable {
        var language: DetectedLanguage
        var confidence: Double
        var hangulRatio: Double
    }

    static func detect(_ text: String, previous: DetectedLanguage = .english) -> Result {
        let ratio = Hangul.hangulRatio(text)
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }.count
        guard letters > 0 else {
            return Result(language: previous, confidence: 0.3, hangulRatio: 0)
        }
        if ratio >= 0.2 {
            return Result(language: .korean, confidence: min(1, 0.6 + ratio * 0.4), hangulRatio: ratio)
        }
        if ratio > 0 {
            return Result(language: .korean, confidence: 0.55, hangulRatio: ratio)
        }
        // Latin-only text. Very short words like "ok" are ambiguous → keep previous.
        if letters <= 2 {
            return Result(language: previous, confidence: 0.4, hangulRatio: 0)
        }
        return Result(language: .english, confidence: min(1, 0.6 + Double(min(letters, 40)) / 100), hangulRatio: 0)
    }
}

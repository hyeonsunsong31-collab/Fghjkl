import Foundation

/// A violation of the output-control constraints.
enum ControlViolation: Equatable {
    case empty
    case languageMismatch(expected: DetectedLanguage, found: DetectedLanguage)
    case informalRegister(String)
    case missingAddress
    case falseCompletionClaim(String)
    case tooLong(characters: Int, limit: Int)
    case markdownInSpeech

    var isRepairableLocally: Bool {
        switch self {
        case .missingAddress, .markdownInSpeech, .tooLong: return true
        default: return false
        }
    }
}

/// **Output controller** — the measurement end of the control objective.
///
/// Every candidate answer is checked against Jarvis' constraints *before* it is
/// spoken or shown. Violations are (a) repaired locally where possible,
/// (b) sent back to the language model as a precise correction instruction
/// otherwise, and (c) reported to the brain, whose synaptic perceptrons learn
/// to make the next first attempt satisfy them.
struct OutputController {
    /// Korean sentence endings that are not 합쇼체/해요체 (too casual for a butler).
    static let casualKoreanEndings = ["해.", "야.", "지.", "거든.", "냐?", "니?", "해?", "줘.", "어.", "아.", "래.", "다고."]
    static let casualEnglish = ["yeah", "yep", "nope", "gonna", "wanna", "gotta", "dude", "bro", "lol", "kinda", "sorta", "ya", "hey there"]
    static let englishCompletionClaims = ["i have opened", "i've opened", "i have created", "i've created", "i have sent", "i've sent",
                                          "i have played", "now playing", "i have set", "i've set", "i have turned", "i've turned", "done, sir"]
    static let koreanCompletionClaims = ["열었습니다", "만들었습니다", "생성했습니다", "보냈습니다", "재생합니다", "재생했습니다",
                                         "설정했습니다", "켰습니다", "껐습니다", "완료했습니다", "실행했습니다"]

    func verify(_ text: String,
                expected: DetectedLanguage,
                toolsSucceeded: Bool,
                characterLimit: Int,
                forSpeech: Bool) -> [ControlViolation] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [.empty] }
        var violations: [ControlViolation] = []

        let found = LanguageDetector.detect(trimmed, previous: expected)
        if found.language != expected && found.confidence >= 0.6 {
            // Allow English proper nouns inside Korean and vice versa: only flag clear mismatches.
            if expected == .korean ? found.hangulRatio < 0.15 : found.hangulRatio > 0.3 {
                violations.append(.languageMismatch(expected: expected, found: found.language))
            }
        }

        let lower = trimmed.lowercased()
        switch expected {
        case .korean:
            let sentences = Self.sentences(trimmed)
            for s in sentences {
                if let ending = Self.casualKoreanEndings.first(where: { s.hasSuffix($0) }) {
                    violations.append(.informalRegister(ending))
                    break
                }
            }
            if !toolsSucceeded, let claim = Self.koreanCompletionClaims.first(where: { trimmed.contains($0) }) {
                violations.append(.falseCompletionClaim(claim))
            }
        case .english:
            let words = Set(TextEncoder.tokens(lower))
            if let casual = Self.casualEnglish.first(where: { $0.contains(" ") ? lower.contains($0) : words.contains($0) }) {
                violations.append(.informalRegister(casual))
            }
            if !lower.contains("sir") && trimmed.count > 0 {
                violations.append(.missingAddress)
            }
            if !toolsSucceeded, let claim = Self.englishCompletionClaims.first(where: { lower.contains($0) }) {
                violations.append(.falseCompletionClaim(claim))
            }
        }

        if trimmed.count > characterLimit {
            violations.append(.tooLong(characters: trimmed.count, limit: characterLimit))
        }
        if forSpeech && (trimmed.contains("**") || trimmed.contains("##") || trimmed.contains("```")) {
            violations.append(.markdownInSpeech)
        }
        return violations
    }

    /// Deterministic local repairs (no model call needed).
    func repair(_ text: String, violations: [ControlViolation], language: DetectedLanguage) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for v in violations {
            switch v {
            case .markdownInSpeech:
                for token in ["**", "##", "```", "__"] { out = out.replacingOccurrences(of: token, with: "") }
            case .missingAddress where language == .english:
                out = Self.addressSir(out)
            case .tooLong(_, let limit):
                out = Self.truncateAtSentence(out, limit: limit)
            default:
                break
            }
        }
        return out
    }

    /// Instruction sent back to the language model when local repair is impossible.
    func correctionInstruction(for violations: [ControlViolation], language: DetectedLanguage) -> String {
        var parts: [String] = []
        for v in violations {
            switch v {
            case .empty:
                parts.append(language == .korean ? "빈 응답은 허용되지 않습니다. 반드시 답변하십시오." : "An empty reply is not acceptable; answer the request.")
            case .languageMismatch(let expected, _):
                parts.append(expected == .korean ? "반드시 한국어로만 답하십시오." : "Reply in British English only.")
            case .informalRegister(let token):
                parts.append(language == .korean
                             ? "반말(\(token))을 쓰지 말고 정중한 합쇼체(-습니다, -십시오)로 답하십시오."
                             : "Avoid casual wording (\"\(token)\"); keep a formal, courteous British register.")
            case .falseCompletionClaim(let claim):
                parts.append(language == .korean
                             ? "실제로 도구가 성공하지 않았으므로 '\(claim)'처럼 완료를 주장하지 마십시오. 사실대로 말하십시오."
                             : "No tool succeeded, so do not claim \"\(claim)\". State truthfully what happened.")
            case .tooLong(_, let limit):
                parts.append(language == .korean ? "\(limit)자 이내로 간결하게 답하십시오." : "Keep the reply under \(limit) characters.")
            case .missingAddress:
                parts.append("Address the user as \"sir\".")
            case .markdownInSpeech:
                parts.append(language == .korean ? "마크다운 기호 없이 말하듯 답하십시오." : "Do not use markdown; write as natural speech.")
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: Helpers

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?。".contains(ch) {
                let s = current.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { out.append(s) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    static func addressSir(_ text: String) -> String {
        guard let last = text.last else { return "Very good, sir." }
        if ".!?".contains(last) {
            var body = text
            let punct = body.removeLast()
            return body + ", sir" + String(punct)
        }
        return text + ", sir."
    }

    static func truncateAtSentence(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        var kept = ""
        for s in sentences(text) {
            if kept.count + s.count + 1 > limit { break }
            kept += (kept.isEmpty ? "" : " ") + s
        }
        return kept.isEmpty ? String(text.prefix(limit)) : kept
    }
}

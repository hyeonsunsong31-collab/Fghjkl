import Foundation

/// Number extraction for English and Korean commands.
enum NumberParsing {
    static let englishNumbers: [String: Double] = [
        "zero": 0, "a": 1, "an": 1, "one": 1, "single": 1, "two": 2, "couple": 2, "pair": 2, "three": 3, "few": 3,
        "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "dozen": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90, "hundred": 100,
        "once": 1, "twice": 2, "thrice": 3, "half": 0.5, "double": 2, "triple": 3
    ]

    /// Native Korean numerals (as used with counters 개/번/배/명/시).
    static let koreanNative: [(String, Double)] = [
        ("스물", 20), ("스무", 20), ("열", 10), ("아홉", 9), ("여덟", 8), ("일곱", 7), ("여섯", 6), ("다섯", 5),
        ("넷", 4), ("네", 4), ("셋", 3), ("세", 3), ("둘", 2), ("두", 2), ("하나", 1), ("한", 1)
    ]

    /// Sino-Korean digits (used with 퍼센트/초/분/도/시간/배 and in larger numbers).
    static let sinoDigits: [Character: Int] = ["일": 1, "이": 2, "삼": 3, "사": 4, "오": 5, "육": 6, "칠": 7, "팔": 8, "구": 9]

    /// First number in the text (digits first, then words), with an optional required suffix context.
    static func firstNumber(in text: String) -> Double? {
        if let d = firstDigits(in: text) { return d }
        let tokens = TextEncoder.tokens(text)
        for t in tokens {
            if let v = englishNumbers[t], t != "a" && t != "an" { return v }
        }
        if let k = koreanCount(in: text) { return k }
        return nil
    }

    static func firstDigits(in text: String) -> Double? {
        var current = ""
        var seenDot = false
        for ch in text {
            if ch.isASCII && ch.isNumber {
                current.append(ch)
            } else if ch == "." && !current.isEmpty && !seenDot {
                current.append(ch); seenDot = true
            } else if !current.isEmpty {
                break
            }
        }
        if current.hasSuffix(".") { current.removeLast() }
        return Double(current)
    }

    /// A count expressed in Korean: "세 개", "3개", "두 번", "다섯", "세번".
    static func koreanCount(in text: String) -> Double? {
        let counters = ["개", "번", "배", "명", "마리", "장", "곡", "채", "대", "시"]
        let compact = text.replacingOccurrences(of: " ", with: "")
        for (word, value) in koreanNative {
            for c in counters where compact.contains(word + c) {
                return value
            }
        }
        // Sino-Korean number before a unit: "오십퍼센트", "삼십분".
        if let sino = sinoNumber(in: compact) { return sino }
        return nil
    }

    /// Parse a Sino-Korean number like "오십", "이십오", "백" that is followed by a unit.
    static func sinoNumber(in compact: String) -> Double? {
        let units = ["퍼센트", "프로", "초", "분", "도", "시간", "배"]
        let chars = Array(compact)
        var i = 0
        while i < chars.count {
            var j = i
            var total = 0, current = 0
            var consumed = false
            while j < chars.count {
                let c = chars[j]
                if let d = sinoDigits[c] { current = d; consumed = true }
                else if c == "십" { total += (current == 0 ? 1 : current) * 10; current = 0; consumed = true }
                else if c == "백" { total += (current == 0 ? 1 : current) * 100; current = 0; consumed = true }
                else { break }
                j += 1
            }
            if consumed {
                let rest = String(chars[j...])
                if units.contains(where: { rest.hasPrefix($0) }) { return Double(total + current) }
            }
            i = max(j, i + 1)
        }
        return nil
    }

    /// Duration in seconds: "5 minutes", "90 seconds", "1 hour", "5분", "30초", "한 시간", "1시간 30분".
    static func duration(in text: String) -> Double? {
        let lower = text.lowercased()
        var seconds: Double = 0
        var found = false
        let tokens = TextEncoder.tokens(lower)
        for (i, t) in tokens.enumerated() {
            let value: Double? = Double(t) ?? englishNumbers[t]
            guard let v = value, i + 1 < tokens.count else { continue }
            let unit = tokens[i + 1]
            if unit.hasPrefix("sec") { seconds += v; found = true }
            else if unit.hasPrefix("min") { seconds += v * 60; found = true }
            else if unit.hasPrefix("hour") || unit == "hr" || unit == "hrs" { seconds += v * 3600; found = true }
        }
        if found { return seconds }

        let compact = lower.replacingOccurrences(of: " ", with: "")
        func valueBefore(_ unit: String) -> Double? {
            guard let r = compact.range(of: unit) else { return nil }
            let prefix = String(compact[..<r.lowerBound])
            var digits = ""
            for ch in prefix.reversed() { if ch.isNumber && ch.isASCII { digits = String(ch) + digits } else { break } }
            if let d = Double(digits) { return d }
            for (word, v) in koreanNative where prefix.hasSuffix(word) { return v }
            if let s = sinoNumber(in: String(prefix.suffix(4)) + unit) { return s }
            return nil
        }
        if let h = valueBefore("시간") { seconds += h * 3600; found = true }
        if let m = valueBefore("분") { seconds += m * 60; found = true }
        if let s = valueBefore("초") { seconds += s; found = true }
        return found ? seconds : nil
    }

    /// Percentage: "50%", "50 percent", "오십 퍼센트", "50프로".
    static func percentage(in text: String) -> Double? {
        let lower = text.lowercased()
        let compact = lower.replacingOccurrences(of: " ", with: "")
        if compact.contains("%") || lower.contains("percent") || compact.contains("퍼센트") || compact.contains("프로") {
            if let d = firstDigits(in: lower) { return d }
            if let s = sinoNumber(in: compact) { return s }
            for t in TextEncoder.tokens(lower) { if let v = englishNumbers[t], v >= 1 { return v } }
        }
        return nil
    }

    /// Clock time → (hour, minute) in 24h: "7am", "7:30 pm", "19:05", "오전 7시", "오후 3시 30분".
    static func clockTime(in text: String) -> (hour: Int, minute: Int)? {
        let lower = text.lowercased()
        let compact = lower.replacingOccurrences(of: " ", with: "")
        // hh:mm
        if let r = compact.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression) {
            let parts = compact[r].split(separator: ":")
            if parts.count == 2, var h = Int(parts[0]), let m = Int(parts[1]) {
                if compact.contains("pm") || compact.contains("오후"), h < 12 { h += 12 }
                if (compact.contains("am") || compact.contains("오전")) && h == 12 { h = 0 }
                return (h % 24, m % 60)
            }
        }
        // 7am / 7pm
        if let r = compact.range(of: #"(\d{1,2})(am|pm|a\.m\.|p\.m\.)"#, options: .regularExpression) {
            let s = String(compact[r])
            let digits = s.prefix { $0.isNumber }
            if var h = Int(digits) {
                if s.contains("p") && h < 12 { h += 12 }
                if s.contains("a") && h == 12 { h = 0 }
                return (h, 0)
            }
        }
        // Korean N시 (M분) — "시" not followed by "간" (시간 = hours).
        var searchStart = compact.startIndex
        while let r = compact.range(of: "시", range: searchStart..<compact.endIndex) {
            searchStart = r.upperBound
            let after = String(compact[r.upperBound...])
            if after.hasPrefix("간") { continue }
            let prefix = String(compact[..<r.lowerBound])
            var hour: Int?
            var digits = ""
            for ch in prefix.reversed() { if ch.isASCII && ch.isNumber { digits = String(ch) + digits } else { break } }
            if let d = Int(digits) { hour = d }
            else {
                let hours: [(String, Int)] = [("열두", 12), ("열한", 11), ("열", 10), ("아홉", 9), ("여덟", 8), ("일곱", 7), ("여섯", 6),
                                              ("다섯", 5), ("네", 4), ("세", 3), ("두", 2), ("한", 1)]
                for (w, v) in hours where prefix.hasSuffix(w) { hour = v; break }
            }
            guard var h = hour else { continue }
            if compact.contains("오후") || compact.contains("저녁") || compact.contains("밤"), h < 12 { h += 12 }
            if compact.contains("오전") && h == 12 { h = 0 }
            var minute = 0
            if after.hasPrefix("반") { minute = 30 }
            else if let mr = after.range(of: "분") {
                let mPrefix = String(after[..<mr.lowerBound])
                minute = Int(mPrefix.filter { $0.isASCII && $0.isNumber }) ?? Int(sinoNumber(in: mPrefix + "분") ?? 0)
            }
            return (h % 24, minute % 60)
        }
        return nil
    }
}

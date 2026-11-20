import Foundation

/// British-English text normalisation for speech synthesis:
/// numbers, ordinals, decimals, currency, percentages, times, units and
/// common abbreviations become words ("£3.50" → "three pounds fifty").
enum EnglishNormalizer {
    static let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                       "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    /// Cardinal number in British English ("one hundred and twenty-three").
    static func cardinal(_ n: Int) -> String {
        if n < 0 { return "minus " + cardinal(-n) }
        if n < 20 { return ones[n] }
        if n < 100 { return tens[n / 10] + (n % 10 == 0 ? "" : "-" + ones[n % 10]) }
        if n < 1000 {
            let rest = n % 100
            return ones[n / 100] + " hundred" + (rest == 0 ? "" : " and " + cardinal(rest))
        }
        let scales: [(Int, String)] = [(1_000_000_000_000, "trillion"), (1_000_000_000, "billion"), (1_000_000, "million"), (1000, "thousand")]
        for (value, name) in scales where n >= value {
            let head = cardinal(n / value) + " " + name
            let rest = n % value
            if rest == 0 { return head }
            return head + (rest < 100 ? " and " : " ") + cardinal(rest)
        }
        return String(n)
    }

    static func ordinal(_ n: Int) -> String {
        let irregular = ["one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth",
                         "nine": "ninth", "twelve": "twelfth"]
        let c = cardinal(n)
        var parts = c.components(separatedBy: CharacterSet(charactersIn: " -"))
        let separators = c.filter { $0 == " " || $0 == "-" }.map(String.init)
        guard let last = parts.last else { return c }
        if let ir = irregular[last] { parts[parts.count - 1] = ir }
        else if last.hasSuffix("y") { parts[parts.count - 1] = String(last.dropLast()) + "ieth" }
        else { parts[parts.count - 1] = last + "th" }
        var out = parts[0]
        for i in 1..<parts.count { out += separators[i - 1] + parts[i] }
        return out
    }

    /// Digits read one by one (for long numbers / codes).
    static func digits(_ s: String) -> String {
        s.compactMap { $0.wholeNumberValue }.map { $0 == 0 ? "oh" : ones[$0] }.joined(separator: " ")
    }

    static func number(_ token: String) -> String {
        let clean = token.replacingOccurrences(of: ",", with: "")
        if let dot = clean.firstIndex(of: ".") {
            let intPart = String(clean[..<dot]), frac = String(clean[clean.index(after: dot)...])
            let head = Int(intPart).map(cardinal) ?? intPart
            return head + " point " + frac.compactMap { $0.wholeNumberValue }.map { ones[$0] }.joined(separator: " ")
        }
        if clean.count > 12 { return digits(clean) }
        return Int(clean).map(cardinal) ?? clean
    }

    static let abbreviations: [String: String] = [
        "mr.": "mister", "mrs.": "missus", "ms.": "miz", "dr.": "doctor", "st.": "saint", "prof.": "professor",
        "e.g.": "for example", "i.e.": "that is", "etc.": "et cetera", "vs.": "versus", "approx.": "approximately",
        "no.": "number", "dept.": "department", "jan.": "january", "feb.": "february", "aug.": "august",
        "sept.": "september", "oct.": "october", "nov.": "november", "dec.": "december"
    ]

    static let units: [String: (String, String)] = [
        "km": ("kilometre", "kilometres"), "m": ("metre", "metres"), "cm": ("centimetre", "centimetres"),
        "mm": ("millimetre", "millimetres"), "kg": ("kilogram", "kilograms"), "g": ("gram", "grams"),
        "mb": ("megabyte", "megabytes"), "gb": ("gigabyte", "gigabytes"), "tb": ("terabyte", "terabytes"),
        "s": ("second", "seconds"), "ms": ("millisecond", "milliseconds"), "h": ("hour", "hours"),
        "kph": ("kilometre per hour", "kilometres per hour"), "mph": ("mile per hour", "miles per hour"),
        "°c": ("degree Celsius", "degrees Celsius"), "°f": ("degree Fahrenheit", "degrees Fahrenheit")
    ]

    static func normalize(_ text: String) -> String {
        var out: [String] = []
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var i = 0
        while i < tokens.count {
            var token = tokens[i]
            let lower = token.lowercased()
            if let a = abbreviations[lower] { out.append(a); i += 1; continue }

            // Peel leading/trailing punctuation so it survives normalisation.
            var leading = "", trailing = ""
            while let f = token.first, "\"'(“‘[".contains(f) { leading.append(f); token.removeFirst() }
            while let l = token.last, ",.;:!?\"')”’]…".contains(l) { trailing = String(l) + trailing; token.removeLast() }
            if token.isEmpty { out.append(leading + trailing); i += 1; continue }

            var spoken: String?
            let tl = token.lowercased()

            // Currency.
            if let sym = token.first, "£$€₩¥".contains(sym), token.count > 1 {
                let amount = String(token.dropFirst()).replacingOccurrences(of: ",", with: "")
                let names: [Character: (String, String, String)] = ["£": ("pound", "pounds", "pence"), "$": ("dollar", "dollars", "cents"),
                                                                    "€": ("euro", "euros", "cents"), "₩": ("won", "won", ""), "¥": ("yen", "yen", "")]
                if let (one, many, minor) = names[sym] {
                    let parts = amount.split(separator: ".")
                    if let whole = Int(parts.first ?? "") {
                        var s = cardinal(whole) + " " + (whole == 1 ? one : many)
                        if parts.count == 2, let cents = Int(parts[1].prefix(2)), cents > 0, !minor.isEmpty {
                            s += " " + cardinal(cents)
                        }
                        spoken = s
                    }
                }
            }
            // Percent.
            else if tl.hasSuffix("%"), Double(tl.dropLast()) != nil {
                spoken = number(String(tl.dropLast())) + " per cent"
            }
            // Clock time 14:30.
            else if tl.contains(":"), let colon = tl.firstIndex(of: ":"), let h = Int(tl[..<colon]), let m = Int(tl[tl.index(after: colon)...]), h < 24, m < 60 {
                spoken = cardinal(h) + (m == 0 ? " o'clock" : (m < 10 ? " oh " + cardinal(m) : " " + cardinal(m)))
            }
            // Ordinals 1st 2nd 3rd 4th.
            else if let n = Int(tl.dropLast(2)), ["st", "nd", "rd", "th"].contains(String(tl.suffix(2))) {
                spoken = ordinal(n)
            }
            // Number + unit glued ("5km", "3.5GB").
            else if let firstLetter = tl.firstIndex(where: { $0.isLetter || $0 == "°" }), firstLetter != tl.startIndex,
                    Double(tl[..<firstLetter].replacingOccurrences(of: ",", with: "")) != nil,
                    let unit = units[String(tl[firstLetter...])] {
                let value = String(tl[..<firstLetter])
                spoken = number(value) + " " + (value == "1" ? unit.0 : unit.1)
            }
            // Plain number (possibly followed by a separate unit token).
            else if Double(tl.replacingOccurrences(of: ",", with: "")) != nil {
                var s = number(tl)
                if i + 1 < tokens.count, let unit = units[tokens[i + 1].lowercased().trimmingCharacters(in: .punctuationCharacters)] {
                    s += " " + (tl == "1" ? unit.0 : unit.1)
                    trailing += tokens[i + 1].filter { ",.;:!?".contains($0) }
                    i += 1
                }
                spoken = s
            }
            // Symbols.
            else if token == "&" { spoken = "and" }
            else if token == "+" { spoken = "plus" }
            else if token == "=" { spoken = "equals" }
            else if token == "@" { spoken = "at" }
            // 3D, 2D …
            else if tl.count == 2, let d = Int(String(tl.first!)), tl.last == "d" {
                spoken = cardinal(d) + " D"
            }

            out.append(leading + (spoken ?? token) + trailing)
            i += 1
        }
        return out.joined(separator: " ")
    }
}

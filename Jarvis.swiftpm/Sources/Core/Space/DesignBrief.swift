import Foundation

/// Everything a design request asks for, read from the user's own words (English or
/// Korean): what to build, which parts, how many, which colours and materials, how
/// big, which style, and what to leave out. The design library, the language model
/// and the validator all work from this brief, and it is stored with the model so
/// later requests ("make the wheels black", "add a chimney") refine the same design.
struct DesignBrief: Codable, Equatable {
    var request: String = ""
    /// Library subject key ("car", "house", …), nil when the library has no such object.
    var subject: String?
    /// What the user called the object (used for naming and for the language model).
    var subjectPhrase: String = ""
    var variant: String?
    var styles: [String] = []
    /// Component → colour; "main" is the overall colour, "accent" a second colour.
    var colors: [String: String] = [:]
    /// Component → material; "main" for the whole object.
    var materials: [String: String] = [:]
    var counts: [String: Int] = [:]
    /// Components the request mentions (they must appear in the design).
    var features: [String] = []
    /// Components the request rules out ("without a roof", "지붕 없는").
    var excluded: [String] = []
    /// Component → relative size ("big wheels", "make the wheels bigger").
    var scales: [String: Float] = [:]
    /// Requested dimensions in metres.
    var height: Float?
    var length: Float?
    var width: Float?
    /// A size given without saying which dimension ("1 metre robot").
    var overall: Float?
    /// "big" / "tiny" and similar.
    var sizeFactor: Float = 1
    var korean: Bool = false

    // MARK: Queries

    func wants(_ component: String) -> Bool { features.contains(component) && !excluded.contains(component) }
    func excludes(_ component: String) -> Bool { excluded.contains(component) }
    func color(_ component: String) -> String? { colors[component] }
    func count(_ component: String) -> Int? { counts[component] }
    func hasStyle(_ style: String) -> Bool { styles.contains(style) }
    var isEmpty: Bool { subject == nil && features.isEmpty && colors.isEmpty && counts.isEmpty }

    /// The brief after a follow-up request ("make the roof blue", "add two more legs", "remove the spoiler").
    func refined(by edit: DesignBrief) -> DesignBrief {
        var out = self
        for (k, v) in edit.colors { out.colors[k] = v }
        for (k, v) in edit.materials { out.materials[k] = v }
        for (k, v) in edit.counts { out.counts[k] = v }
        for (k, v) in edit.scales { out.scales[k] = (out.scales[k] ?? 1) * v }
        for f in edit.features where !out.features.contains(f) { out.features.append(f) }
        out.excluded.removeAll { edit.features.contains($0) && !edit.excluded.contains($0) }
        for e in edit.excluded where !out.excluded.contains(e) { out.excluded.append(e) }
        out.features.removeAll { edit.excluded.contains($0) }
        for s in edit.styles where !out.styles.contains(s) { out.styles.append(s) }
        if let v = edit.variant, edit.subject == nil || edit.subject == subject { out.variant = v }
        if let h = edit.height { out.height = h }
        if let l = edit.length { out.length = l }
        if let w = edit.width { out.width = w }
        if let o = edit.overall { out.overall = o }
        out.sizeFactor *= edit.sizeFactor
        out.request = request + " · " + edit.request
        return out
    }

    // MARK: Parsing

    static func parse(_ text: String, description: String? = nil) -> DesignBrief {
        var brief = DesignBrief()
        brief.request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lex = Lexed(text)
        brief.korean = lex.korean

        // Subject (and the object's own variant words).
        let subjectSpans = lex.matches(DesignVocabulary.subjects)
        let chosen = Self.chooseSubject(subjectSpans, lex: lex)
        brief.subject = chosen?.key
        brief.subjectPhrase = (description?.isEmpty == false ? description! : brief.request)
        if let subject = chosen?.key {
            for v in DesignVocabulary.variants where v.subject == subject {
                if !lex.spans(of: v.words).isEmpty { brief.variant = v.variant; break }
            }
        }
        // A word naming another subject can still be a part or a material ("나무 의자" = wooden chair).
        let subjectSpan: Span? = chosen?.span

        // Components.
        var componentSpans = lex.matches(DesignVocabulary.components)
        if let s = subjectSpan { componentSpans.removeAll { $0.span.overlaps(s) } }
        let colorSpans = lex.matches(DesignVocabulary.colors)
        let materialSpans = lex.matches(DesignVocabulary.materials).filter { m in
            // "나무" is a material only when it is not the object itself.
            !(m.span.text(lex) == "나무" && brief.subject == "tree") && !(subjectSpan.map { m.span.overlaps($0) } ?? false)
        }
        let styleSpans = lex.matches(DesignVocabulary.styles)
        let context = Context(lex: lex, components: componentSpans, subject: subjectSpan,
                              colors: colorSpans.map(\.span), materials: materialSpans.map(\.span))

        // Exclusions and features.
        for c in componentSpans where context.isExcluded(c.span) {
            if !brief.excluded.contains(c.key) { brief.excluded.append(c.key) }
        }
        for c in componentSpans where !brief.excluded.contains(c.key) && c.key != "floor" {
            if !brief.features.contains(c.key) { brief.features.append(c.key) }
        }

        // Colours and materials, attached to the part they describe.
        for c in colorSpans {
            let target = context.target(of: c.span)
            assign(c.key, to: target, in: &brief.colors)
            if c.key == "gold" || c.key == "silver" {
                let key = target ?? "main"
                if brief.materials[key] == nil { brief.materials[key] = c.key == "gold" ? "metal" : "chrome" }
            }
        }
        for m in materialSpans {
            let target = context.target(of: m.span) ?? "main"
            brief.materials[target] = m.key
        }
        for s in styleSpans where !brief.styles.contains(s.key) { brief.styles.append(s.key) }

        // Counts, dimensions, sizes.
        brief.counts = context.counts()
        let dims = context.dimensions()
        brief.height = dims.height
        brief.length = dims.length
        brief.width = dims.width
        brief.overall = dims.overall
        let sizes = context.sizes()
        brief.sizeFactor = sizes.overall
        brief.scales = sizes.components
        brief.features.sort()
        brief.excluded.sort()
        brief.styles.sort()
        return brief
    }

    /// Main / accent / component colour assignment (first mention wins for components).
    private static func assign(_ value: String, to target: String?, in map: inout [String: String]) {
        if let component = target {
            if map[component] == nil { map[component] = value }
        } else if map["main"] == nil {
            map["main"] = value
        } else if map["accent"] == nil && map["main"] != value {
            map["accent"] = value
        }
    }

    private static func chooseSubject(_ spans: [Match], lex: Lexed) -> Match? {
        guard !spans.isEmpty else { return nil }
        if lex.korean { return spans.max { $0.span.start < $1.span.start } }
        // English: the object comes before "with …" ("a house with a car in front").
        let cut = lex.tokens.firstIndex { ["with", "having", "featuring", "plus", "that", "which", "and"].contains($0) } ?? lex.tokens.count
        return spans.first { $0.span.start < cut } ?? spans.first
    }
}

// MARK: - Tokens and spans

/// A run of tokens [start, end).
struct Span: Equatable {
    let start: Int
    let end: Int
    func overlaps(_ o: Span) -> Bool { start < o.end && o.start < end }
    func text(_ lex: Lexed) -> String { lex.tokens[start..<end].joined(separator: " ") }
}

struct Match {
    let key: String
    let span: Span
}

/// The request split into lowercase tokens (digits separated from letters, so
/// "6wheels", "2m", "3층" become "6 wheels", "2 m", "3 층").
struct Lexed {
    let tokens: [String]
    let korean: Bool

    init(_ text: String) {
        var out = ""
        var previous: Character = " "
        let chars = Array(text.lowercased())
        for (i, ch) in chars.enumerated() {
            let next: Character = i + 1 < chars.count ? chars[i + 1] : " "
            if ch == "." && previous.isNumber && next.isNumber { out.append(ch); previous = ch; continue }
            if ",.;:!?()[]{}\"“”‘’/\\-_~·…'".contains(ch) { out.append(" "); previous = " "; continue }
            if (ch.isNumber && previous.isLetter) || (ch.isLetter && previous.isNumber) { out.append(" ") }
            out.append(ch)
            previous = ch
        }
        tokens = out.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let hangul = text.unicodeScalars.filter { (0xAC00...0xD7A3).contains($0.value) }.count
        let latin = text.unicodeScalars.filter { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }.count
        korean = hangul > 0 && hangul * 2 >= latin
    }

    /// Number of tokens `word` matches at `index` (0 = no match).
    func match(_ word: String, at index: Int) -> Int {
        let parts = word.split(separator: " ").map(String.init)
        guard !parts.isEmpty, index + parts.count <= tokens.count else { return 0 }
        for (k, part) in parts.enumerated() {
            let token = tokens[index + k]
            let last = k == parts.count - 1
            if DesignVocabulary.containsHangul(part) {
                if !Self.koreanMatch(token: token, word: part, last: last) { return 0 }
            } else if token != part && DesignVocabulary.singular(token) != part && !(last && token == part + "es") {
                return 0
            }
        }
        return parts.count
    }

    /// Korean words carry particles and endings ("바퀴는", "자동차를", "빨간색으로"): longer words
    /// match as prefixes (or inside compounds like "앞바퀴"); one-syllable words only with a particle.
    private static func koreanMatch(token: String, word: String, last: Bool) -> Bool {
        if !last { return token == word }
        if word.count >= 2 {
            return token.hasPrefix(word) || (token.count > word.count && token.contains(word) && token.count <= word.count + 3)
        }
        guard token.hasPrefix(word) else { return false }
        let rest = String(token.dropFirst(word.count))
        if word == "검" && (rest.hasPrefix("은") || rest.hasPrefix("정") || rest.hasPrefix("게")) { return false }
        return DesignVocabulary.particles.contains(rest)
    }

    /// Non-overlapping spans of any of `words` (longest words first).
    func spans(of words: [String]) -> [Span] {
        var found: [Span] = []
        let ordered = words.sorted { $0.count > $1.count }
        for word in ordered {
            for i in tokens.indices {
                let n = match(word, at: i)
                guard n > 0 else { continue }
                let span = Span(start: i, end: i + n)
                if !found.contains(where: { $0.overlaps(span) }) { found.append(span) }
            }
        }
        return found.sorted { $0.start < $1.start }
    }

    /// Matches of a keyed vocabulary, non-overlapping across keys (longest words win).
    func matches(_ vocabulary: [(key: String, words: [String])]) -> [Match] {
        var all: [(key: String, word: String)] = []
        for entry in vocabulary { for w in entry.words { all.append((entry.key, w)) } }
        all.sort { $0.word.count > $1.word.count }
        var found: [Match] = []
        for (key, word) in all {
            for i in tokens.indices {
                let n = match(word, at: i)
                guard n > 0 else { continue }
                let span = Span(start: i, end: i + n)
                if !found.contains(where: { $0.span.overlaps(span) }) { found.append(Match(key: key, span: span)) }
            }
        }
        return found.sorted { $0.span.start < $1.span.start }
    }
}

// MARK: - Association rules

/// Attaches colours, materials, counts and sizes to the part of the sentence they describe.
private struct Context {
    let lex: Lexed
    let components: [Match]
    let subject: Span?
    let colors: [Span]
    let materials: [Span]

    private var tokens: [String] { lex.tokens }

    /// Words that may sit between an adjective and its noun.
    private static let fillers: Set<String> = [
        "a", "an", "the", "some", "very", "really", "bright", "dark", "light", "pale", "deep", "shiny", "glossy", "matte", "metallic",
        "colored", "coloured", "color", "colour", "painted", "tinted", "and", "big", "small", "large", "little", "round", "square",
        "색", "색의", "색깔의", "빛", "빛의", "아주", "진한", "연한", "밝은", "어두운", "반짝이는",
    ]
    /// Linking words between a part and a colour that follows it ("wheels are black").
    private static let linking: Set<String> = ["is", "are", "in", "painted", "colored", "coloured", "be", "all", "of", "should", "with", "to", "made"]

    private func component(startingAt j: Int) -> String? { components.first { $0.span.start == j }?.key }
    private func component(endingAt j: Int) -> String? { components.first { $0.span.end == j + 1 }?.key }
    private func isAdjective(_ j: Int) -> Bool {
        colors.contains { $0.start <= j && j < $0.end } || materials.contains { $0.start <= j && j < $0.end }
            || Self.fillers.contains(tokens[j]) || DesignVocabulary.sizes.contains { $0.words.contains(tokens[j]) }
    }

    /// The component an adjective at `span` describes (nil = the whole object).
    func target(of span: Span) -> String? {
        let backward = backwardTarget(of: span)
        if let b = backward, prefersBackward(span) { return b }
        // Forward: "black wheels", "검은 바퀴", "red car".
        var j = span.end
        while j < tokens.count && j < span.end + 4 {
            if let c = component(startingAt: j) { return c }
            if let s = subject, s.start == j { return nil }
            if !isAdjective(j) { break }
            j += 1
        }
        return backward
    }

    /// "wheels are black", "roof in blue", "바퀴는 검은색이고", "지붕을 파란색으로".
    private func backwardTarget(of span: Span) -> String? {
        var j = span.start - 1
        var steps = 0
        while j >= 0 && steps < 3 {
            if let c = component(endingAt: j) { return c }
            if !(Self.linking.contains(tokens[j]) || Self.fillers.contains(tokens[j])) { return nil }
            j -= 1
            steps += 1
        }
        return nil
    }

    private func prefersBackward(_ span: Span) -> Bool {
        let before = span.start - 1
        guard before >= 0 else { return false }
        if lex.korean {
            // A part marked as topic/subject/object right before the colour: "바퀴는 검은색".
            let token = tokens[before]
            return component(endingAt: before) != nil && ["은", "는", "이", "가", "을", "를", "도"].contains { token.hasSuffix($0) }
        }
        return Self.linking.contains(tokens[before]) && before >= 1
    }

    func isExcluded(_ span: Span) -> Bool {
        if lex.korean {
            let own = tokens[span.end - 1]
            if own.contains("없") || own.contains("빼") { return true }
            for j in span.end..<min(tokens.count, span.end + 2) {
                let t = tokens[j]
                if ["없", "빼", "제거", "삭제", "제외", "말고", "치워", "떼", "없애"].contains(where: { t.hasPrefix($0) }) { return true }
            }
            return false
        }
        if tokens[span.end - 1].hasSuffix("less") { return true }
        var j = span.start - 1
        var steps = 0
        while j >= 0 && steps < 4 {
            if ["without", "no", "remove", "delete", "minus", "lose", "drop", "except", "rid", "off", "removing", "not"].contains(tokens[j]) { return true }
            if !(Self.fillers.contains(tokens[j]) || isAdjective(j) || ["any", "its", "it", "of", "his", "her", "their", "get"].contains(tokens[j])) { return false }
            j -= 1
            steps += 1
        }
        return false
    }

    // MARK: Numbers

    /// A whole number at token `j` (digits, English words, native Korean with a counter).
    private func number(at j: Int) -> Int? {
        guard j >= 0 && j < tokens.count else { return nil }
        let t = tokens[j]
        if let d = Int(t), d >= 0, d <= 99 {
            return d
        }
        if let e = DesignVocabulary.englishNumbers[t] { return e }
        for (word, value) in DesignVocabulary.koreanNumbers where t.hasPrefix(word) {
            let rest = String(t.dropFirst(word.count))
            if rest.isEmpty {
                if j + 1 < tokens.count && DesignVocabulary.koreanCounters.contains(where: { tokens[j + 1].hasPrefix($0) }) { return value }
            } else if DesignVocabulary.koreanCounters.contains(where: { rest.hasPrefix($0) }) {
                return value
            }
        }
        return nil
    }

    private func isCounter(_ j: Int) -> Bool {
        j >= 0 && j < tokens.count && DesignVocabulary.koreanCounters.contains { tokens[j].hasPrefix($0) }
    }

    func counts() -> [String: Int] {
        var out: [String: Int] = [:]
        for c in components {
            if out[c.key] != nil { continue }
            if lex.korean {
                // "바퀴 6개", "바퀴가 여섯 개", "6개의 바퀴", "다리 세 개".
                for j in c.span.end..<min(tokens.count, c.span.end + 2) {
                    if let n = number(at: j), Int(tokens[j]) == nil || isCounter(j + 1) { out[c.key] = n; break }
                }
                if out[c.key] == nil {
                    for j in stride(from: c.span.start - 1, through: max(0, c.span.start - 3), by: -1) {
                        if let n = number(at: j), isCounter(j + 1) || Int(tokens[j]) == nil { out[c.key] = n; break }
                        if !(isCounter(j) || isAdjective(j)) { break }
                    }
                }
            } else {
                // "six black wheels", "4 legs", "two-story".
                var j = c.span.start - 1
                var steps = 0
                while j >= 0 && steps < 4 {
                    if let n = number(at: j) { out[c.key] = n; break }
                    if !isAdjective(j) && tokens[j] != "of" { break }
                    j -= 1
                    steps += 1
                }
            }
        }
        // Korean floors: "2층", "이층집", "삼층 건물", "단층".
        if out["floor"] == nil {
            let sino: [(String, Int)] = [("단층", 1), ("복층", 2), ("이층", 2), ("삼층", 3), ("사층", 4), ("오층", 5), ("육층", 6), ("십층", 10)]
            for (j, t) in tokens.enumerated() {
                if t.hasPrefix("층"), let n = number(at: j - 1) ?? Int(j > 0 ? tokens[j - 1] : "") { out["floor"] = n; break }
                if let s = sino.first(where: { t.hasPrefix($0.0) }) { out["floor"] = s.1; break }
            }
        }
        return out.filter { $0.value > 0 }
    }

    // MARK: Dimensions

    func dimensions() -> (height: Float?, length: Float?, width: Float?, overall: Float?) {
        let units: [(Float, [String])] = [
            (1, ["m", "meter", "meters", "metre", "metres", "미터", "엠"]),
            (0.01, ["cm", "centimeter", "centimeters", "centimetre", "centimetres", "센티", "센티미터", "센치"]),
            (0.001, ["mm", "millimeter", "millimeters", "millimetre", "millimetres", "밀리", "밀리미터"]),
            (0.3048, ["ft", "feet", "foot"]),
            (0.0254, ["inch", "inches", "인치"]),
        ]
        let heightWords = ["tall", "high", "height", "높이", "키", "높은", "높게"]
        let lengthWords = ["long", "length", "길이", "긴", "길게", "가로"]
        let widthWords = ["wide", "width", "broad", "deep", "depth", "폭", "너비", "넓은", "세로"]
        var height: Float?, length: Float?, width: Float?, overall: Float?
        for (i, t) in tokens.enumerated() {
            guard let value = Float(t), value > 0, i + 1 < tokens.count else { continue }
            guard let unit = units.first(where: { u in u.1.contains { tokens[i + 1].hasPrefix($0) && (tokens[i + 1] == $0 || DesignVocabulary.containsHangul($0)) } }) else { continue }
            let metres = value * unit.0
            var near: [String] = []
            for j in max(0, i - 2)..<min(tokens.count, i + 4) where j != i { near.append(tokens[j]) }
            func has(_ words: [String]) -> Bool { near.contains { n in words.contains { n.hasPrefix($0) } } }
            if has(heightWords) { height = height ?? metres }
            else if has(lengthWords) { length = length ?? metres }
            else if has(widthWords) { width = width ?? metres }
            else { overall = overall ?? metres }
        }
        return (height, length, width, overall)
    }

    // MARK: Sizes

    func sizes() -> (overall: Float, components: [String: Float]) {
        var overall: Float = 1
        var parts: [String: Float] = [:]
        // Adjectives before a part or the object: "big wheels", "a tiny house", "작은 집".
        for (factor, words) in DesignVocabulary.sizes {
            for span in lex.spans(of: words) {
                // "long"/"tall"/"높은" next to a number are dimensions, not adjectives.
                if span.start > 0 && Float(tokens[span.start - 1]) != nil { continue }
                if let target = target(of: span) {
                    parts[target] = (parts[target] ?? 1) * factor
                } else if overall == 1 {
                    overall = factor
                }
            }
        }
        // Comparatives after a part: "make the wheels bigger", "바퀴를 더 크게".
        let up = ["bigger", "larger", "taller", "longer", "wider", "thicker", "크게", "키워", "키우", "길게", "두껍게", "넓게", "높게"]
        let down = ["smaller", "shorter", "thinner", "narrower", "tinier", "작게", "줄여", "줄이", "짧게", "얇게", "좁게", "낮게"]
        let strong = ["much", "way", "lot", "far", "훨씬", "많이", "아주", "엄청"]
        for (j, t) in tokens.enumerated() {
            let isUp = up.contains { t.hasPrefix($0) }
            let isDown = down.contains { t.hasPrefix($0) }
            guard isUp || isDown else { continue }
            let intense = (max(0, j - 2)..<j).contains { strong.contains(tokens[$0]) }
            let doubled = (max(0, j - 3)..<j).contains { ["twice", "double", "두"].contains(tokens[$0]) }
            var factor: Float = isUp ? (intense ? 1.7 : 1.35) : (intense ? 0.55 : 0.75)
            if doubled && isUp { factor = 2 }
            // The part named just before ("the wheels bigger", "바퀴를 더 크게").
            var found: String?
            for k in stride(from: j - 1, through: max(0, j - 4), by: -1) {
                if let c = components.first(where: { $0.span.end == k + 1 })?.key { found = c; break }
            }
            if let c = found { parts[c] = (parts[c] ?? 1) * factor }
        }
        return (overall, parts)
    }
}

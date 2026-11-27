import Foundation

/// Pulls the requested song / artist out of a "play …" command, keeping the
/// user's own words and casing. (Song titles are full of "of", "you", "the" …,
/// which generic filler removal destroys: "Shape of You" must stay intact.)
enum MusicQuery {
    /// nil when no specific music was named ("play some music", "노래 틀어줘").
    static func extract(from text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ".?!~。"))
        guard !s.isEmpty else { return nil }
        let result = containsHangul(s) ? korean(s) : english(s)
        guard let q = result?.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.?!~\"'"))),
              !q.isEmpty, !genericRequests.contains(q.lowercased()) else { return nil }
        return q
    }

    /// Requests that name no particular music.
    static let genericRequests: Set<String> = [
        "music", "some music", "a song", "song", "songs", "something", "anything", "a tune", "tunes", "the music",
        "음악", "노래", "곡", "아무 노래", "아무 음악", "아무거나", "아무 곡", "음악 좀", "노래 좀"
    ]

    // MARK: English ("play X by Y please")

    private static let englishCues = ["start playing", "play me", "play", "put on", "listen to", "queue up", "queue"]
    private static let englishLeading = ["some ", "a bit of ", "a little ", "the song ", "the track ", "song ", "track ",
                                         "music by ", "songs by ", "something by ", "anything by ", "me ", "the music "]
    private static let englishTrailing = [" please", " for me", " right now", " now", " on youtube", " from youtube",
                                          " on spotify", " on apple music", " again", " jarvis", " sir"]

    private static func english(_ text: String) -> String? {
        let lower = text.lowercased()
        var cut: String.Index?
        for cue in englishCues {
            if let r = wordRange(of: cue, in: lower) { cut = r.upperBound; break }
        }
        guard let start = cut else { return nil }
        // Same offsets in the original string (lowercasing keeps ASCII lengths).
        let offset = lower.distance(from: lower.startIndex, to: start)
        guard let originalStart = text.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex) else { return nil }
        var q = String(text[originalStart...]).trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for lead in englishLeading where q.lowercased().hasPrefix(lead) {
                q = String(q.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces); changed = true
            }
            for tail in englishTrailing where q.lowercased().hasSuffix(tail) {
                q = String(q.dropLast(tail.count)).trimmingCharacters(in: .whitespaces); changed = true
            }
        }
        return q
    }

    /// Range of `word` in `text` at word boundaries.
    private static func wordRange(of word: String, in text: String) -> Range<String.Index>? {
        var from = text.startIndex
        while let r = text.range(of: word, range: from..<text.endIndex) {
            let beforeOK = r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetter
            let afterOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetter
            if beforeOK && afterOK { return r }
            from = r.upperBound
        }
        return nil
    }

    // MARK: Korean ("아이유 좋은날 틀어줘")

    private static let koreanVerbs = ["틀어", "재생", "들려", "플레이", "켜"]
    private static let koreanLeading = ["자비스야", "자비스", "유튜브에서", "유튜브로", "멜론에서", "지금", "한번", "한 번"]
    private static let koreanTrailing = ["노래를", "노래 좀", "음악을", "음악 좀", "곡을", "노래", "음악", "곡", "좀", "을", "를",
                                         "유튜브에서", "유튜브로", "한번", "한 번"]

    private static func korean(_ text: String) -> String? {
        // The verb ends the sentence: keep what comes before its last occurrence.
        var end: String.Index?
        for verb in koreanVerbs {
            if let r = text.range(of: verb, options: .backwards), end == nil || r.lowerBound > end! { end = r.lowerBound }
        }
        guard let stop = end else { return nil }
        var q = String(text[..<stop]).trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed && !q.isEmpty {
            changed = false
            for lead in koreanLeading where q.hasPrefix(lead) {
                q = String(q.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ","))); changed = true
            }
            for tail in koreanTrailing where q.hasSuffix(tail) && q.count > tail.count {
                q = String(q.dropLast(tail.count)).trimmingCharacters(in: .whitespaces); changed = true
            }
        }
        return q
    }

    static func containsHangul(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }
}

/// Reads YouTube's search results (the `ytInitialData` JSON embedded in the
/// results page) deterministically, in result order — no page rendering needed.
enum YouTubeResults {
    struct Video: Equatable {
        let id: String
        let title: String
    }

    static func parse(_ html: String, limit: Int = 10) -> [Video] {
        for marker in ["\"videoRenderer\":{\"videoId\":\"", "\"compactVideoRenderer\":{\"videoId\":\"",
                       "\"videoWithContextRenderer\":{\"videoId\":\""] {
            let found = scan(html, marker: marker, limit: limit)
            if !found.isEmpty { return found }
        }
        return []
    }

    private static func scan(_ html: String, marker: String, limit: Int) -> [Video] {
        var out: [Video] = []
        var seen = Set<String>()
        var cursor = html.startIndex
        while out.count < limit, let r = html.range(of: marker, range: cursor..<html.endIndex) {
            let idStart = r.upperBound
            guard let idEnd = html.index(idStart, offsetBy: 11, limitedBy: html.endIndex) else { break }
            cursor = idEnd
            let id = String(html[idStart..<idEnd])
            guard idEnd < html.endIndex, html[idEnd] == "\"",
                  id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else { continue }
            let window = html.index(idEnd, offsetBy: 6000, limitedBy: html.endIndex) ?? html.endIndex
            var title = ""
            for titleMarker in ["\"title\":{\"runs\":[{\"text\":\"", "\"title\":{\"simpleText\":\"", "\"headline\":{\"runs\":[{\"text\":\""] {
                if let t = html.range(of: titleMarker, range: idEnd..<window) {
                    title = jsonString(html, from: t.upperBound)
                    break
                }
            }
            if seen.insert(id).inserted { out.append(Video(id: id, title: title)) }
        }
        return out
    }

    /// Decodes the JSON string literal whose content starts at `start` (just after the opening quote).
    private static func jsonString(_ text: String, from start: String.Index) -> String {
        var raw = ""
        var escaped = false
        var i = start
        while i < text.endIndex {
            let ch = text[i]
            if escaped { raw.append(ch); escaped = false }
            else if ch == "\\" { raw.append(ch); escaped = true }
            else if ch == "\"" { break }
            else { raw.append(ch) }
            i = text.index(after: i)
            if raw.count > 400 { break }
        }
        let literal = "\"" + raw + "\""
        if let data = literal.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String {
            return decoded
        }
        return raw
    }

    /// The result that best matches the request (title containing most of its words),
    /// preferring earlier results; the first result when nothing matches.
    static func bestMatch(_ videos: [Video], for query: String) -> Video? {
        guard let first = videos.first else { return nil }
        let ignored: Set<String> = ["by", "the", "a", "of", "and", "노래", "음악", "곡", "official", "music", "video", "mv"]
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !ignored.contains($0) }
        guard !words.isEmpty else { return first }
        var best = first
        var bestScore = -1.0
        for video in videos.prefix(6) {
            let title = video.title.lowercased()
            let compact = title.replacingOccurrences(of: " ", with: "")
            let hits = words.filter { title.contains($0) || compact.contains($0) }.count
            let score = Double(hits) / Double(words.count)
            if score > bestScore + 0.0001 { best = video; bestScore = score }
        }
        return best
    }
}

/// Classifies answers to Jarvis' "Shall I …?" confirmation questions.
enum ConfirmationReply {
    /// true = yes, false = no, nil = neither (a new request).
    static func classify(_ text: String) -> Bool? {
        if isNegative(text) { return false }
        if isAffirmative(text) { return true }
        return nil
    }

    private static func normalized(_ text: String) -> String {
        let cleaned = text.lowercased().unicodeScalars.map { CharacterSet.punctuationCharacters.contains($0) && $0 != "'" ? " " : String($0) }.joined()
        return " " + cleaned.split(separator: " ").joined(separator: " ") + " "
    }

    static func isNegative(_ text: String) -> Bool {
        let t = normalized(text)
        let words = [" no ", " nope ", " nah ", " don't ", " dont ", " do not ", " cancel ", " stop ", " never mind ", " not now ", " negative "]
        if words.contains(where: { t.contains($0) }) { return true }
        let korean = ["아니", "아뇨", "취소", "하지 마", "하지마", "그만", "됐어", "됐습니다", "안 해", "안해", "싫어", "필요 없어", "필요없어", "멈춰", "하지 말"]
        return korean.contains { t.contains($0) }
    }

    static func isAffirmative(_ text: String) -> Bool {
        let t = normalized(text)
        let english = [" yes ", " yeah ", " yep ", " yup ", " sure ", " ok ", " okay ", " confirm ", " confirmed ", " proceed ",
                       " go ahead ", " do it ", " please do ", " affirmative ", " correct ", " send it ", " call them ", " absolutely "]
        if english.contains(where: { t.contains($0) }) { return true }
        // Short Korean answers must be whole words ("네" is also the start of "네이버").
        let shortKorean = [" 네 ", " 넵 ", " 네네 ", " 예 ", " 응 ", " 어 ", " 웅 ", " 엉 "]
        if shortKorean.contains(where: { t.contains($0) }) { return true }
        let korean = ["그래", "좋아", "보내", "해줘", "해 줘", "해주세요", "해 주세요", "진행", "확인", "걸어", "맞아", "오케이", "부탁해", "그렇게 해"]
        return korean.contains { t.contains($0) }
    }
}

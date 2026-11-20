import Foundation

/// Byte-level BPE tokenizer compatible with Hugging Face `tokenizer.json`
/// files of the Qwen2/Qwen3 family (GPT-style byte mapping + merges + special tokens).
final class BPETokenizer: @unchecked Sendable {
    private(set) var vocab: [String: Int] = [:]
    private(set) var idToToken: [Int: String] = [:]
    private var ranks: [String: Int] = [:]          // "a b" → rank
    private(set) var specialTokens: [String: Int] = [:]
    private var specialOrder: [String] = []
    private let splitter: NSRegularExpression
    private var cache: [String: [Int]] = [:]
    private let cacheLock = NSLock()

    static let qwenPattern = #"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"#

    /// GPT-2 byte ↔ unicode mapping.
    static let byteToUnicode: [UInt8: Character] = {
        var bs: [Int] = Array(33...126) + Array(161...172) + Array(174...255)
        var cs = bs
        var n = 0
        for b in 0..<256 where !bs.contains(b) {
            bs.append(b)
            cs.append(256 + n)
            n += 1
        }
        var map: [UInt8: Character] = [:]
        for (b, c) in zip(bs, cs) { map[UInt8(b)] = Character(Unicode.Scalar(UInt32(c))!) }
        return map
    }()

    static let unicodeToByte: [Character: UInt8] = {
        var m: [Character: UInt8] = [:]
        for (b, c) in byteToUnicode { m[c] = b }
        return m
    }()

    init(jsonData: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = root["model"] as? [String: Any],
              let v = model["vocab"] as? [String: Any] else { throw LMError.format("tokenizer.json") }
        for (token, id) in v {
            if let n = id as? Int { vocab[token] = n; idToToken[n] = token }
            else if let n = id as? NSNumber { vocab[token] = n.intValue; idToToken[n.intValue] = token }
        }
        if let merges = model["merges"] as? [Any] {
            for (rank, m) in merges.enumerated() {
                if let s = m as? String { ranks[s] = rank }
                else if let pair = m as? [String], pair.count == 2 { ranks[pair[0] + " " + pair[1]] = rank }
            }
        }
        for t in (root["added_tokens"] as? [[String: Any]]) ?? [] {
            guard let content = t["content"] as? String else { continue }
            let id = (t["id"] as? Int) ?? (t["id"] as? NSNumber)?.intValue ?? -1
            guard id >= 0 else { continue }
            specialTokens[content] = id
            idToToken[id] = content
        }
        specialOrder = specialTokens.keys.sorted { $0.count > $1.count }
        var pattern = Self.qwenPattern
        if let pre = root["pre_tokenizer"] as? [String: Any] {
            let candidates = (pre["pretokenizers"] as? [[String: Any]]) ?? [pre]
            for p in candidates {
                if let pat = (p["pattern"] as? [String: Any])?["Regex"] as? String { pattern = pat; break }
            }
        }
        splitter = try NSRegularExpression(pattern: pattern, options: [])
    }

    var vocabularySize: Int { max((idToToken.keys.max() ?? 0) + 1, vocab.count) }
    func id(of special: String) -> Int? { specialTokens[special] ?? vocab[special] }

    // MARK: Encoding

    func encode(_ text: String) -> [Int] {
        var ids: [Int] = []
        var segments: [(String, Bool)] = [(text.precomposedStringWithCanonicalMapping, false)]
        // Split out special tokens first.
        for special in specialOrder {
            var next: [(String, Bool)] = []
            for (seg, isSpecial) in segments {
                if isSpecial || !seg.contains(special) { next.append((seg, isSpecial)); continue }
                let parts = seg.components(separatedBy: special)
                for (i, part) in parts.enumerated() {
                    if !part.isEmpty { next.append((part, false)) }
                    if i < parts.count - 1 { next.append((special, true)) }
                }
            }
            segments = next
        }
        for (seg, isSpecial) in segments {
            if isSpecial, let id = specialTokens[seg] { ids.append(id); continue }
            let ns = seg as NSString
            for match in splitter.matches(in: seg, range: NSRange(location: 0, length: ns.length)) {
                let piece = ns.substring(with: match.range)
                ids += encodePiece(piece)
            }
        }
        return ids
    }

    private func encodePiece(_ piece: String) -> [Int] {
        cacheLock.lock()
        if let cached = cache[piece] { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        let mapped = piece.utf8.map { Self.byteToUnicode[$0]! }
        var word = mapped.map { String($0) }
        if word.count > 1 {
            while true {
                var bestRank = Int.max
                var bestIndex = -1
                for i in 0..<(word.count - 1) {
                    if let r = ranks[word[i] + " " + word[i + 1]], r < bestRank { bestRank = r; bestIndex = i }
                }
                guard bestIndex >= 0 else { break }
                let first = word[bestIndex], second = word[bestIndex + 1]
                var merged: [String] = []
                var i = 0
                while i < word.count {
                    if i < word.count - 1 && word[i] == first && word[i + 1] == second {
                        merged.append(first + second)
                        i += 2
                    } else {
                        merged.append(word[i])
                        i += 1
                    }
                }
                word = merged
                if word.count == 1 { break }
            }
        }
        var out: [Int] = []
        for w in word {
            if let id = vocab[w] { out.append(id) }
            else { for ch in w { if let id = vocab[String(ch)] { out.append(id) } } }
        }
        cacheLock.lock()
        if cache.count > 50_000 { cache.removeAll() }
        cache[piece] = out
        cacheLock.unlock()
        return out
    }

    // MARK: Decoding

    /// Bytes of a token (special tokens decode to their literal text).
    func bytes(of id: Int) -> [UInt8] {
        guard let token = idToToken[id] else { return [] }
        if specialTokens[token] != nil { return Array(token.utf8) }
        var out: [UInt8] = []
        for ch in token {
            if let b = Self.unicodeToByte[ch] { out.append(b) } else { out += Array(String(ch).utf8) }
        }
        return out
    }

    func decode(_ ids: [Int]) -> String {
        String(decoding: ids.flatMap { bytes(of: $0) }, as: UTF8.self)
    }
}

/// Incremental UTF-8 decoder for streaming tokens (multi-byte characters can
/// span several tokens — common for Korean).
struct StreamingDetokenizer {
    private var pending: [UInt8] = []

    mutating func append(_ bytes: [UInt8]) -> String {
        pending += bytes
        // Find the longest prefix that is complete UTF-8.
        var end = pending.count
        while end > 0 {
            if String(validatingUTF8CString: pending[0..<end]) != nil { break }
            end -= 1
            if pending.count - end > 4 { end = pending.count; break }
        }
        guard end > 0 else { return "" }
        let text = String(decoding: pending[0..<end], as: UTF8.self)
        pending.removeFirst(end)
        return text
    }

    mutating func flush() -> String {
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }
}

private extension String {
    /// Returns nil when the bytes are not valid UTF-8 (incomplete trailing sequence).
    init?(validatingUTF8CString bytes: ArraySlice<UInt8>) {
        var iterator = bytes.makeIterator()
        var decoder = UTF8()
        var result = ""
        loop: while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let s): result.unicodeScalars.append(s)
            case .emptyInput: break loop
            case .error: return nil
            }
        }
        self = result
    }
}

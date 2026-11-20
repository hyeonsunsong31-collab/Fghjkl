import Foundation

/// Sparse distributed representation: `indices` of active bits in a `size`-bit space.
struct SparseCode: Equatable, Codable {
    var indices: [Int]
    let size: Int

    init(indices: [Int], size: Int) {
        self.indices = Array(Set(indices.filter { $0 >= 0 && $0 < size })).sorted()
        self.size = size
    }

    static func empty(size: Int) -> SparseCode { SparseCode(indices: [], size: size) }

    func dense() -> [Float] {
        var v = [Float](repeating: 0, count: size)
        for i in indices { v[i] = 1 }
        return v
    }

    func overlap(_ other: SparseCode) -> Int {
        var i = 0, j = 0, n = 0
        while i < indices.count && j < other.indices.count {
            if indices[i] == other.indices[j] { n += 1; i += 1; j += 1 }
            else if indices[i] < other.indices[j] { i += 1 }
            else { j += 1 }
        }
        return n
    }

    /// Overlap normalised to [0,1].
    func similarity(_ other: SparseCode) -> Float {
        let denom = max(1, min(indices.count, other.indices.count))
        return Float(overlap(other)) / Float(denom)
    }

    func union(_ other: SparseCode) -> SparseCode {
        SparseCode(indices: indices + other.indices, size: size)
    }
}

/// Language-agnostic text → SDR encoder (Korean, English, mixed).
///
/// Features: lowercase word unigrams + bigrams, character trigrams over a
/// jamo-decomposed form (so 만들어/만들고 share most bits). Each feature votes
/// for `bitsPerFeature` hashed positions; the top `activeBits` positions win.
struct TextEncoder {
    var size: Int = 2048
    var activeBits: Int = 48
    var bitsPerFeature: Int = 3
    var seed: UInt64 = 0x5444_5245_4E43

    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    func encode(_ text: String) -> SparseCode {
        let words = Self.tokens(text)
        guard !words.isEmpty else { return .empty(size: size) }
        var votes: [Int: Float] = [:]

        func vote(_ feature: String, weight: Float) {
            var h = NeuroMath.hash(seed, Self.stableHash(feature))
            for _ in 0..<bitsPerFeature {
                votes[Int(h % UInt64(size)), default: 0] += weight
                h = NeuroMath.mix64(h)
            }
        }

        for (i, w) in words.enumerated() {
            vote("w:" + w, weight: 2.0)
            if i + 1 < words.count { vote("b:" + w + "_" + words[i + 1], weight: 1.0) }
            let jamo = Array(Hangul.decompose(" " + w + " "))
            if jamo.count >= 3 {
                for k in 0...(jamo.count - 3) {
                    vote("t:" + String(jamo[k..<(k + 3)]), weight: 0.6)
                }
            }
        }

        let ranked = votes.sorted { a, b in a.value == b.value ? a.key < b.key : a.value > b.value }
        return SparseCode(indices: ranked.prefix(activeBits).map(\.key), size: size)
    }

    /// FNV-1a over UTF-8 — stable across launches and platforms (unlike `hashValue`).
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }
}

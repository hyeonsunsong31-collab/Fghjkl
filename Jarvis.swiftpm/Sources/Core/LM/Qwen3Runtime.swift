import Foundation

/// A decoder backend (CPU reference or Metal GPU).
protocol LMBackend: AnyObject {
    var config: Qwen3Config { get }
    var position: Int { get }
    func reset()
    func forward(token: Int) throws -> [Float]
    var name: String { get }
}

extension Qwen3CPUModel: LMBackend {
    var name: String { "CPU" }
}

/// Token sampler: temperature, top-k, nucleus (top-p) and repetition penalty.
struct TokenSampler {
    var temperature: Float = 0.7
    var topK = 40
    var topP: Float = 0.9
    var repetitionPenalty: Float = 1.08
    var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1000))

    mutating func sample(_ logits: [Float], recent: [Int]) -> Int {
        var l = logits
        for t in Set(recent.suffix(64)) where t < l.count {
            l[t] = l[t] > 0 ? l[t] / repetitionPenalty : l[t] * repetitionPenalty
        }
        if temperature <= 0.01 { return l.indices.max { l[$0] < l[$1] } ?? 0 }
        // Top-k by partial sort.
        let k = min(topK, l.count)
        var top: [(Int, Float)] = []
        top.reserveCapacity(k + 1)
        for (i, v) in l.enumerated() {
            if top.count < k { top.append((i, v)); if top.count == k { top.sort { $0.1 > $1.1 } } ; continue }
            if v > top[k - 1].1 {
                var j = k - 1
                top[j] = (i, v)
                while j > 0 && top[j].1 > top[j - 1].1 { top.swapAt(j, j - 1); j -= 1 }
            }
        }
        if top.count < k { top.sort { $0.1 > $1.1 } }
        let maxV = top[0].1
        var probs = top.map { Float(exp(Double(($0.1 - maxV) / temperature))) }
        let total = probs.reduce(0, +)
        probs = probs.map { $0 / total }
        // Nucleus.
        var cumulative: Float = 0
        var cutoff = probs.count
        for (i, p) in probs.enumerated() {
            cumulative += p
            if cumulative >= topP { cutoff = i + 1; break }
        }
        let kept = probs.prefix(cutoff)
        let norm = kept.reduce(0, +)
        var r = rng.nextUnit() * norm
        for (i, p) in kept.enumerated() {
            r -= p
            if r <= 0 { return top[i].0 }
        }
        return top[0].0
    }
}

/// Deep-Think runtime: tokenizer + backend + generation loop.
final class Qwen3Runtime: @unchecked Sendable {
    let tokenizer: BPETokenizer
    let backend: LMBackend
    let summary: String
    private let stopTokens: Set<Int>
    private let hybridThinking: Bool
    private let lock = NSLock()

    init(directory: URL, preferGPU: Bool = true) throws {
        let tok = try BPETokenizer(jsonData: Data(contentsOf: directory.appendingPathComponent("tokenizer.json")))
        tokenizer = tok
        var chosen: LMBackend?
        #if canImport(Metal)
        if preferGPU, let gpu = try? Qwen3MetalModel(directory: directory) {
            chosen = gpu
        }
        #endif
        let model = try chosen ?? Qwen3CPUModel(directory: directory)
        backend = model
        stopTokens = Set(["<|im_end|>", "<|endoftext|>"].compactMap { tok.id(of: $0) })
        let cfg = model.config
        hybridThinking = !directory.lastPathComponent.contains("2507")
        summary = "\(cfg.layers)L·\(cfg.hiddenSize)d·\(cfg.bits)bit · \(model.name)"
    }

    /// Generate a reply for a fully formatted prompt; `onToken` returns false to stop.
    func generate(prompt: String, maxTokens: Int, temperature: Float, onToken: (String) -> Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        backend.reset()
        var text = prompt
        if hybridThinking { text += "<think>\n\n</think>\n\n" }
        let ids = tokenizer.encode(text)
        guard ids.count < 1900 else { throw LMError.unsupported("prompt too long (\(ids.count) tokens)") }
        var logits: [Float] = []
        for id in ids { logits = try backend.forward(token: id) }
        var sampler = TokenSampler(temperature: temperature)
        var produced: [Int] = []
        var detok = StreamingDetokenizer()
        for _ in 0..<maxTokens {
            let next = sampler.sample(logits, recent: ids.suffix(32) + produced)
            if stopTokens.contains(next) { break }
            produced.append(next)
            let piece = detok.append(tokenizer.bytes(of: next))
            if !piece.isEmpty, !onToken(piece) { return }
            logits = try backend.forward(token: next)
        }
        let tail = detok.flush()
        if !tail.isEmpty { _ = onToken(tail) }
    }
}

import Foundation
import Dispatch

/// Hyper-parameters from `config.json`.
struct Qwen3Config: Equatable {
    var hiddenSize: Int
    var layers: Int
    var heads: Int
    var kvHeads: Int
    var headDim: Int
    var intermediateSize: Int
    var vocabSize: Int
    var rmsEps: Float
    var ropeTheta: Float
    var tieEmbeddings: Bool
    var groupSize: Int
    var bits: Int

    init(json: Data) throws {
        guard let c = try JSONSerialization.jsonObject(with: json) as? [String: Any] else { throw LMError.format("config.json") }
        func int(_ k: String, _ d: Int? = nil) throws -> Int {
            if let v = c[k] as? Int { return v }
            if let v = c[k] as? NSNumber { return v.intValue }
            if let d { return d }
            throw LMError.format("config missing \(k)")
        }
        func float(_ k: String, _ d: Float) -> Float {
            if let v = c[k] as? Double { return Float(v) }
            if let v = c[k] as? NSNumber { return v.floatValue }
            return d
        }
        hiddenSize = try int("hidden_size")
        layers = try int("num_hidden_layers")
        heads = try int("num_attention_heads")
        kvHeads = try int("num_key_value_heads", heads)
        headDim = try int("head_dim", hiddenSize / heads)
        intermediateSize = try int("intermediate_size")
        vocabSize = try int("vocab_size")
        rmsEps = float("rms_norm_eps", 1e-6)
        ropeTheta = float("rope_theta", 1_000_000)
        tieEmbeddings = (c["tie_word_embeddings"] as? Bool) ?? false
        let q = (c["quantization"] as? [String: Any]) ?? (c["quantization_config"] as? [String: Any]) ?? [:]
        groupSize = (q["group_size"] as? Int) ?? 64
        bits = (q["bits"] as? Int) ?? 4
    }
}

/// A linear layer: MLX affine-quantized (packed uint32 + scales/biases) or dense float.
struct LinearWeights {
    let outFeatures: Int
    let inFeatures: Int
    let bits: Int
    let groupSize: Int
    /// Quantized storage (nil for dense).
    let packed: UnsafePointer<UInt32>?
    let scales: [Float]
    let biases: [Float]
    /// Dense storage (nil for quantized).
    let dense: [Float]?

    var isQuantized: Bool { packed != nil }
    var wordsPerRow: Int { inFeatures * bits / 32 }
    var groupsPerRow: Int { inFeatures / groupSize }

    static func load(_ store: SafetensorsStore, _ prefix: String, config: Qwen3Config) throws -> LinearWeights {
        let w = try store.tensor(prefix + ".weight")
        if store.has(prefix + ".scales") {
            let s = try store.tensor(prefix + ".scales")
            let b = try store.tensor(prefix + ".biases")
            let out = w.shape[0]
            let groups = s.shape[1]
            let bits = w.shape[1] * 32 / (groups * config.groupSize)
            let inFeatures = groups * config.groupSize
            return LinearWeights(outFeatures: out, inFeatures: inFeatures, bits: bits, groupSize: config.groupSize,
                                 packed: w.pointer.assumingMemoryBound(to: UInt32.self),
                                 scales: try s.floats(), biases: try b.floats(), dense: nil)
        }
        return LinearWeights(outFeatures: w.shape[0], inFeatures: w.shape[1], bits: 32, groupSize: 1,
                             packed: nil, scales: [], biases: [], dense: try w.floats())
    }

    /// y = W·x (multi-threaded).
    func apply(_ x: UnsafePointer<Float>, _ y: UnsafeMutablePointer<Float>) {
        let rows = outFeatures
        let chunk = 64
        let chunks = (rows + chunk - 1) / chunk
        if let packed {
            // Pre-sum x per group: Σ_j (s q_j + b) x_j = s Σ q_j x_j + b Σ x_j.
            var groupSums = [Float](repeating: 0, count: groupsPerRow)
            for g in 0..<groupsPerRow {
                var s: Float = 0
                for j in (g * groupSize)..<((g + 1) * groupSize) { s += x[j] }
                groupSums[g] = s
            }
            let perWord = 32 / bits
            let mask = UInt32((1 << bits) - 1)
            let wordsPerGroup = groupSize / perWord
            let wpr = wordsPerRow, gpr = groupsPerRow, bitsLocal = bits
            scales.withUnsafeBufferPointer { sc in
                biases.withUnsafeBufferPointer { bi in
                    groupSums.withUnsafeBufferPointer { gs in
                        DispatchQueue.concurrentPerform(iterations: chunks) { c in
                            let start = c * chunk, end = min(rows, start + chunk)
                            for r in start..<end {
                                let row = packed + r * wpr
                                var acc: Float = 0
                                for g in 0..<gpr {
                                    var dot: Float = 0
                                    var xi = g * groupSize
                                    for w in 0..<wordsPerGroup {
                                        var word = row[g * wordsPerGroup + w]
                                        for _ in 0..<perWord {
                                            dot += Float(word & mask) * x[xi]
                                            word >>= UInt32(bitsLocal)
                                            xi += 1
                                        }
                                    }
                                    acc += sc[r * gpr + g] * dot + bi[r * gpr + g] * gs[g]
                                }
                                y[r] = acc
                            }
                        }
                    }
                }
            }
        } else if let dense {
            let inF = inFeatures
            dense.withUnsafeBufferPointer { d in
                DispatchQueue.concurrentPerform(iterations: chunks) { c in
                    let start = c * chunk, end = min(rows, start + chunk)
                    for r in start..<end {
                        var acc: Float = 0
                        let base = r * inF
                        for j in 0..<inF { acc += d[base + j] * x[j] }
                        y[r] = acc
                    }
                }
            }
        }
    }

    /// Dequantized row (embedding lookup).
    func row(_ r: Int) -> [Float] {
        var out = [Float](repeating: 0, count: inFeatures)
        if let packed {
            let perWord = 32 / bits
            let mask = UInt32((1 << bits) - 1)
            let rowPtr = packed + r * wordsPerRow
            for j in 0..<inFeatures {
                let word = rowPtr[j / perWord]
                let q = Float((word >> UInt32((j % perWord) * bits)) & mask)
                let g = j / groupSize
                out[j] = scales[r * groupsPerRow + g] * q + biases[r * groupsPerRow + g]
            }
        } else if let dense {
            for j in 0..<inFeatures { out[j] = dense[r * inFeatures + j] }
        }
        return out
    }
}

struct Qwen3Layer {
    let inputNorm: [Float]
    let postNorm: [Float]
    let qNorm: [Float]
    let kNorm: [Float]
    let q, k, v, o: LinearWeights
    let gate, up, down: LinearWeights
}

/// CPU reference implementation of the Qwen3 decoder (also used to validate the GPU path).
final class Qwen3CPUModel: @unchecked Sendable {
    let config: Qwen3Config
    let store: SafetensorsStore
    let embed: LinearWeights
    let layers: [Qwen3Layer]
    let finalNorm: [Float]
    let lmHead: LinearWeights
    let maxContext: Int
    private var keyCache: [[Float]]
    private var valueCache: [[Float]]
    private(set) var position = 0
    private let ropeCos: [Float]
    private let ropeSin: [Float]

    init(directory: URL, maxContext: Int = 2048) throws {
        let cfg = try Qwen3Config(json: Data(contentsOf: directory.appendingPathComponent("config.json")))
        config = cfg
        store = try SafetensorsStore(directory: directory)
        self.maxContext = maxContext
        let prefix = store.has("model.embed_tokens.weight") ? "model." : ""
        embed = try LinearWeights.load(store, prefix + "embed_tokens", config: cfg)
        var ls: [Qwen3Layer] = []
        for i in 0..<cfg.layers {
            let p = "\(prefix)layers.\(i)."
            ls.append(Qwen3Layer(
                inputNorm: try store.tensor(p + "input_layernorm.weight").floats(),
                postNorm: try store.tensor(p + "post_attention_layernorm.weight").floats(),
                qNorm: try store.tensor(p + "self_attn.q_norm.weight").floats(),
                kNorm: try store.tensor(p + "self_attn.k_norm.weight").floats(),
                q: try LinearWeights.load(store, p + "self_attn.q_proj", config: cfg),
                k: try LinearWeights.load(store, p + "self_attn.k_proj", config: cfg),
                v: try LinearWeights.load(store, p + "self_attn.v_proj", config: cfg),
                o: try LinearWeights.load(store, p + "self_attn.o_proj", config: cfg),
                gate: try LinearWeights.load(store, p + "mlp.gate_proj", config: cfg),
                up: try LinearWeights.load(store, p + "mlp.up_proj", config: cfg),
                down: try LinearWeights.load(store, p + "mlp.down_proj", config: cfg)))
        }
        layers = ls
        finalNorm = try store.tensor(prefix + "norm.weight").floats()
        if !cfg.tieEmbeddings, store.has("lm_head.weight") {
            lmHead = try LinearWeights.load(store, "lm_head", config: cfg)
        } else {
            lmHead = embed
        }
        let kvDim = cfg.kvHeads * cfg.headDim
        keyCache = Array(repeating: [Float](repeating: 0, count: maxContext * kvDim), count: cfg.layers)
        valueCache = keyCache
        // RoPE tables (non-interleaved halves).
        let half = cfg.headDim / 2
        var cosT = [Float](repeating: 0, count: maxContext * half)
        var sinT = cosT
        for p in 0..<maxContext {
            for i in 0..<half {
                let freq = 1 / pow(Double(cfg.ropeTheta), Double(2 * i) / Double(cfg.headDim))
                let angle = Double(p) * freq
                cosT[p * half + i] = Float(cos(angle))
                sinT[p * half + i] = Float(sin(angle))
            }
        }
        ropeCos = cosT
        ropeSin = sinT
    }

    func reset() { position = 0 }

    static func rmsNorm(_ x: [Float], _ w: [Float], eps: Float) -> [Float] {
        var ss: Float = 0
        for v in x { ss += v * v }
        let inv = 1 / (ss / Float(x.count) + eps).squareRoot()
        var out = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count { out[i] = x[i] * inv * w[i] }
        return out
    }

    private func applyRope(_ v: inout [Float], heads: Int, pos: Int) {
        let hd = config.headDim, half = hd / 2
        for h in 0..<heads {
            let base = h * hd
            for i in 0..<half {
                let c = ropeCos[pos * half + i], s = ropeSin[pos * half + i]
                let a = v[base + i], b = v[base + half + i]
                v[base + i] = a * c - b * s
                v[base + half + i] = b * c + a * s
            }
        }
    }

    private func headNorm(_ v: inout [Float], heads: Int, weight: [Float]) {
        let hd = config.headDim
        for h in 0..<heads {
            let slice = Array(v[(h * hd)..<((h + 1) * hd)])
            let n = Self.rmsNorm(slice, weight, eps: config.rmsEps)
            for i in 0..<hd { v[h * hd + i] = n[i] }
        }
    }

    private func linear(_ w: LinearWeights, _ x: [Float]) -> [Float] {
        var y = [Float](repeating: 0, count: w.outFeatures)
        x.withUnsafeBufferPointer { xp in
            y.withUnsafeMutableBufferPointer { yp in w.apply(xp.baseAddress!, yp.baseAddress!) }
        }
        return y
    }

    /// Run one token through the network; returns logits over the vocabulary.
    func forward(token: Int) throws -> [Float] {
        guard position < maxContext else { throw LMError.unsupported("context window exceeded") }
        let cfg = config
        let pos = position
        var x = embed.row(token)
        let kvDim = cfg.kvHeads * cfg.headDim
        let groupsPerKV = cfg.heads / cfg.kvHeads
        let scale = 1 / Float(cfg.headDim).squareRoot()
        for (li, L) in layers.enumerated() {
            let h = Self.rmsNorm(x, L.inputNorm, eps: cfg.rmsEps)
            var q = linear(L.q, h)
            var k = linear(L.k, h)
            let v = linear(L.v, h)
            headNorm(&q, heads: cfg.heads, weight: L.qNorm)
            headNorm(&k, heads: cfg.kvHeads, weight: L.kNorm)
            applyRope(&q, heads: cfg.heads, pos: pos)
            applyRope(&k, heads: cfg.kvHeads, pos: pos)
            for i in 0..<kvDim {
                keyCache[li][pos * kvDim + i] = k[i]
                valueCache[li][pos * kvDim + i] = v[i]
            }
            var attn = [Float](repeating: 0, count: cfg.heads * cfg.headDim)
            for head in 0..<cfg.heads {
                let kvh = head / groupsPerKV
                var scores = [Float](repeating: 0, count: pos + 1)
                var maxScore = -Float.infinity
                for t in 0...pos {
                    var dot: Float = 0
                    for d in 0..<cfg.headDim { dot += q[head * cfg.headDim + d] * keyCache[li][t * kvDim + kvh * cfg.headDim + d] }
                    scores[t] = dot * scale
                    maxScore = max(maxScore, scores[t])
                }
                var total: Float = 0
                for t in 0...pos { scores[t] = Float(exp(Double(scores[t] - maxScore))); total += scores[t] }
                for t in 0...pos {
                    let w = scores[t] / total
                    for d in 0..<cfg.headDim { attn[head * cfg.headDim + d] += w * valueCache[li][t * kvDim + kvh * cfg.headDim + d] }
                }
            }
            let o = linear(L.o, attn)
            for i in 0..<cfg.hiddenSize { x[i] += o[i] }
            let h2 = Self.rmsNorm(x, L.postNorm, eps: cfg.rmsEps)
            let g = linear(L.gate, h2)
            let u = linear(L.up, h2)
            var act = [Float](repeating: 0, count: g.count)
            for i in 0..<g.count { act[i] = g[i] / (1 + Float(exp(Double(-g[i])))) * u[i] }
            let d = linear(L.down, act)
            for i in 0..<cfg.hiddenSize { x[i] += d[i] }
        }
        let normed = Self.rmsNorm(x, finalNorm, eps: cfg.rmsEps)
        position += 1
        return linear(lmHead, normed)
    }
}

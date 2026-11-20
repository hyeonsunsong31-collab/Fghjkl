#if canImport(Metal)
import Foundation
import Metal

/// GPU backend for the Qwen3 decoder. Kernels are compiled **at runtime from
/// source** (Swift Playgrounds cannot build `.metal` files). 4-bit weights are
/// used in place from the memory-mapped safetensors files (no copy); scales and
/// biases are converted to half precision; the KV cache is half precision.
final class Qwen3MetalModel: LMBackend, @unchecked Sendable {
    let config: Qwen3Config
    let name = "Metal GPU"
    private(set) var position = 0
    let maxContext: Int

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var pipelines: [String: MTLComputePipelineState] = [:]
    private let store: SafetensorsStore
    private var fileBuffers: [ObjectIdentifier: MTLBuffer] = [:]

    struct QLinear {
        let packed: MTLBuffer
        let packedOffset: Int
        let scales: MTLBuffer
        let biases: MTLBuffer
        let outFeatures: Int
        let inFeatures: Int
        let groupSize: Int
        let bits: Int
    }

    struct Layer {
        let inputNorm, postNorm, qNorm, kNorm: MTLBuffer
        let q, k, v, o, gate, up, down: QLinear
    }

    private var embed: QLinear!
    private var lmHead: QLinear!
    private var finalNorm: MTLBuffer!
    private var layers: [Layer] = []
    private var keyCache: [MTLBuffer] = []
    private var valueCache: [MTLBuffer] = []
    private var ropeCos: MTLBuffer!
    private var ropeSin: MTLBuffer!
    // Activations.
    private var x, h, qBuf, kBuf, vBuf, attn, oBuf, gBuf, uBuf, logits: MTLBuffer!

    init(directory: URL, maxContext: Int = 2048) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw LMError.unsupported("no Metal device")
        }
        self.device = device
        self.queue = queue
        self.maxContext = maxContext
        config = try Qwen3Config(json: Data(contentsOf: directory.appendingPathComponent("config.json")))
        store = try SafetensorsStore(directory: directory)
        try buildPipelines()
        try loadWeights()
        try allocate()
        try selfTest()
    }

    // MARK: Setup

    private func buildPipelines() throws {
        let library = try device.makeLibrary(source: Self.kernelSource, options: nil)
        for name in ["qmatvec4", "qmatvec8", "rmsnorm", "headnorm_rope", "kv_store", "attention", "silu_mul", "add_inplace", "embed_row"] {
            guard let fn = library.makeFunction(name: name) else { throw LMError.unsupported("kernel \(name)") }
            pipelines[name] = try device.makeComputePipelineState(function: fn)
        }
    }

    private func buffer(for file: MappedFile) -> MTLBuffer? {
        let key = ObjectIdentifier(file)
        if let b = fileBuffers[key] { return b }
        guard file.mappedLength <= device.maxBufferLength else { return nil }
        let b = device.makeBuffer(bytesNoCopy: UnsafeMutableRawPointer(mutating: file.base), length: file.mappedLength,
                                  options: .storageModeShared, deallocator: nil)
        fileBuffers[key] = b
        return b
    }

    private func halfBuffer(_ t: TensorInfo) throws -> MTLBuffer {
        let n = t.elementCount
        var halves = [UInt16](repeating: 0, count: n)
        switch t.dtype {
        case .f16:
            let p = t.pointer.assumingMemoryBound(to: UInt16.self)
            for i in 0..<n { halves[i] = p[i] }
        case .bf16:
            let p = t.pointer.assumingMemoryBound(to: UInt16.self)
            for i in 0..<n { halves[i] = HalfConversion.toF16(HalfConversion.bf16(p[i])) }
        case .f32:
            let p = t.pointer.assumingMemoryBound(to: Float.self)
            for i in 0..<n { halves[i] = HalfConversion.toF16(p[i]) }
        default:
            throw LMError.unsupported("scale dtype \(t.dtype.rawValue)")
        }
        guard let b = device.makeBuffer(bytes: halves, length: max(2, n * 2), options: .storageModeShared) else { throw LMError.io("alloc") }
        return b
    }

    private func floatBuffer(_ values: [Float]) throws -> MTLBuffer {
        guard let b = device.makeBuffer(bytes: values, length: max(4, values.count * 4), options: .storageModeShared) else { throw LMError.io("alloc") }
        return b
    }

    private func qlinear(_ prefix: String) throws -> QLinear {
        let w = try store.tensor(prefix + ".weight")
        guard store.has(prefix + ".scales") else { throw LMError.unsupported("dense layer \(prefix) on GPU") }
        let s = try store.tensor(prefix + ".scales")
        let b = try store.tensor(prefix + ".biases")
        let groups = s.shape[1]
        let inFeatures = groups * config.groupSize
        let bits = w.shape[1] * 32 / inFeatures
        let packedBuffer: MTLBuffer
        let offset: Int
        if w.offset % 4 == 0, let fb = buffer(for: w.file) {
            packedBuffer = fb
            offset = w.offset
        } else {
            guard let copy = device.makeBuffer(bytes: w.pointer, length: w.byteCount, options: .storageModeShared) else { throw LMError.io("alloc") }
            packedBuffer = copy
            offset = 0
        }
        return QLinear(packed: packedBuffer, packedOffset: offset, scales: try halfBuffer(s), biases: try halfBuffer(b),
                       outFeatures: w.shape[0], inFeatures: inFeatures, groupSize: config.groupSize, bits: bits)
    }

    private func loadWeights() throws {
        let prefix = store.has("model.embed_tokens.weight") ? "model." : ""
        embed = try qlinear(prefix + "embed_tokens")
        for i in 0..<config.layers {
            let p = "\(prefix)layers.\(i)."
            layers.append(Layer(
                inputNorm: try floatBuffer(store.tensor(p + "input_layernorm.weight").floats()),
                postNorm: try floatBuffer(store.tensor(p + "post_attention_layernorm.weight").floats()),
                qNorm: try floatBuffer(store.tensor(p + "self_attn.q_norm.weight").floats()),
                kNorm: try floatBuffer(store.tensor(p + "self_attn.k_norm.weight").floats()),
                q: try qlinear(p + "self_attn.q_proj"), k: try qlinear(p + "self_attn.k_proj"),
                v: try qlinear(p + "self_attn.v_proj"), o: try qlinear(p + "self_attn.o_proj"),
                gate: try qlinear(p + "mlp.gate_proj"), up: try qlinear(p + "mlp.up_proj"), down: try qlinear(p + "mlp.down_proj")))
        }
        finalNorm = try floatBuffer(store.tensor(prefix + "norm.weight").floats())
        lmHead = (!config.tieEmbeddings && store.has("lm_head.weight")) ? try qlinear("lm_head") : embed
    }

    private func allocate() throws {
        func make(_ count: Int) throws -> MTLBuffer {
            guard let b = device.makeBuffer(length: max(4, count * 4), options: .storageModeShared) else { throw LMError.io("alloc") }
            return b
        }
        let c = config
        x = try make(c.hiddenSize); h = try make(c.hiddenSize)
        qBuf = try make(c.heads * c.headDim); kBuf = try make(c.kvHeads * c.headDim); vBuf = try make(c.kvHeads * c.headDim)
        attn = try make(c.heads * c.headDim); oBuf = try make(c.hiddenSize)
        gBuf = try make(c.intermediateSize); uBuf = try make(c.intermediateSize)
        logits = try make(lmHead.outFeatures)
        let kvBytes = maxContext * c.kvHeads * c.headDim * 2
        for _ in 0..<c.layers {
            guard let kb = device.makeBuffer(length: kvBytes, options: .storageModePrivate),
                  let vb = device.makeBuffer(length: kvBytes, options: .storageModePrivate) else { throw LMError.io("KV cache alloc") }
            keyCache.append(kb)
            valueCache.append(vb)
        }
        let half = c.headDim / 2
        var cosT = [Float](repeating: 0, count: maxContext * half), sinT = cosT
        for p in 0..<maxContext {
            for i in 0..<half {
                let angle = Double(p) / pow(Double(c.ropeTheta), Double(2 * i) / Double(c.headDim))
                cosT[p * half + i] = Float(cos(angle))
                sinT[p * half + i] = Float(sin(angle))
            }
        }
        ropeCos = try floatBuffer(cosT)
        ropeSin = try floatBuffer(sinT)
    }

    func reset() { position = 0 }

    // MARK: Encoding helpers

    private func pipeline(_ name: String) -> MTLComputePipelineState { pipelines[name]! }

    private func setU32(_ e: MTLComputeCommandEncoder, _ v: Int, _ index: Int) {
        var u = UInt32(v)
        e.setBytes(&u, length: 4, index: index)
    }

    private func setF32(_ e: MTLComputeCommandEncoder, _ v: Float, _ index: Int) {
        var f = v
        e.setBytes(&f, length: 4, index: index)
    }

    private func encodeMatvec(_ e: MTLComputeCommandEncoder, _ w: QLinear, _ input: MTLBuffer, _ output: MTLBuffer) {
        let p = pipeline(w.bits == 8 ? "qmatvec8" : "qmatvec4")
        e.setComputePipelineState(p)
        e.setBuffer(w.packed, offset: w.packedOffset, index: 0)
        e.setBuffer(w.scales, offset: 0, index: 1)
        e.setBuffer(w.biases, offset: 0, index: 2)
        e.setBuffer(input, offset: 0, index: 3)
        e.setBuffer(output, offset: 0, index: 4)
        setU32(e, w.inFeatures, 5)
        setU32(e, w.outFeatures, 6)
        setU32(e, w.groupSize, 7)
        let rowsPerGroup = 2
        e.dispatchThreadgroups(MTLSize(width: (w.outFeatures + rowsPerGroup - 1) / rowsPerGroup, height: 1, depth: 1),
                               threadsPerThreadgroup: MTLSize(width: 32 * rowsPerGroup, height: 1, depth: 1))
    }

    private func encodeRMSNorm(_ e: MTLComputeCommandEncoder, _ input: MTLBuffer, _ weight: MTLBuffer, _ output: MTLBuffer, _ n: Int) {
        e.setComputePipelineState(pipeline("rmsnorm"))
        e.setBuffer(input, offset: 0, index: 0)
        e.setBuffer(weight, offset: 0, index: 1)
        e.setBuffer(output, offset: 0, index: 2)
        setU32(e, n, 3)
        setF32(e, config.rmsEps, 4)
        let threads = min(1024, pipeline("rmsnorm").maxTotalThreadsPerThreadgroup)
        e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1))
    }

    private func encodeHeadNormRope(_ e: MTLComputeCommandEncoder, _ buf: MTLBuffer, _ weight: MTLBuffer, heads: Int, pos: Int) {
        e.setComputePipelineState(pipeline("headnorm_rope"))
        e.setBuffer(buf, offset: 0, index: 0)
        e.setBuffer(weight, offset: 0, index: 1)
        e.setBuffer(ropeCos, offset: 0, index: 2)
        e.setBuffer(ropeSin, offset: 0, index: 3)
        setU32(e, config.headDim, 4)
        setU32(e, pos, 5)
        setF32(e, config.rmsEps, 6)
        e.dispatchThreadgroups(MTLSize(width: heads, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: config.headDim, height: 1, depth: 1))
    }

    private func encodeElementwise(_ e: MTLComputeCommandEncoder, _ name: String, _ a: MTLBuffer, _ b: MTLBuffer, _ n: Int) {
        e.setComputePipelineState(pipeline(name))
        e.setBuffer(a, offset: 0, index: 0)
        e.setBuffer(b, offset: 0, index: 1)
        setU32(e, n, 2)
        e.dispatchThreads(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(256, n), height: 1, depth: 1))
    }

    // MARK: Forward

    func forward(token: Int) throws -> [Float] {
        guard position < maxContext else { throw LMError.unsupported("context window exceeded") }
        let c = config
        let pos = position
        guard let cb = queue.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { throw LMError.io("command buffer") }
        let kvDim = c.kvHeads * c.headDim

        // Embedding row → x.
        e.setComputePipelineState(pipeline("embed_row"))
        e.setBuffer(embed.packed, offset: embed.packedOffset, index: 0)
        e.setBuffer(embed.scales, offset: 0, index: 1)
        e.setBuffer(embed.biases, offset: 0, index: 2)
        e.setBuffer(x, offset: 0, index: 3)
        setU32(e, c.hiddenSize, 4)
        setU32(e, token, 5)
        setU32(e, embed.groupSize, 6)
        setU32(e, embed.bits, 7)
        e.dispatchThreads(MTLSize(width: c.hiddenSize, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))

        for (li, L) in layers.enumerated() {
            encodeRMSNorm(e, x, L.inputNorm, h, c.hiddenSize)
            encodeMatvec(e, L.q, h, qBuf)
            encodeMatvec(e, L.k, h, kBuf)
            encodeMatvec(e, L.v, h, vBuf)
            encodeHeadNormRope(e, qBuf, L.qNorm, heads: c.heads, pos: pos)
            encodeHeadNormRope(e, kBuf, L.kNorm, heads: c.kvHeads, pos: pos)
            // KV store.
            e.setComputePipelineState(pipeline("kv_store"))
            e.setBuffer(kBuf, offset: 0, index: 0)
            e.setBuffer(vBuf, offset: 0, index: 1)
            e.setBuffer(keyCache[li], offset: 0, index: 2)
            e.setBuffer(valueCache[li], offset: 0, index: 3)
            setU32(e, kvDim, 4)
            setU32(e, pos, 5)
            e.dispatchThreads(MTLSize(width: kvDim, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(256, kvDim), height: 1, depth: 1))
            // Attention.
            e.setComputePipelineState(pipeline("attention"))
            e.setBuffer(qBuf, offset: 0, index: 0)
            e.setBuffer(keyCache[li], offset: 0, index: 1)
            e.setBuffer(valueCache[li], offset: 0, index: 2)
            e.setBuffer(attn, offset: 0, index: 3)
            setU32(e, c.headDim, 4)
            setU32(e, kvDim, 5)
            setU32(e, c.heads / c.kvHeads, 6)
            setU32(e, pos + 1, 7)
            setF32(e, 1 / Float(c.headDim).squareRoot(), 8)
            e.setThreadgroupMemoryLength(maxContext * 4, index: 0)
            e.dispatchThreadgroups(MTLSize(width: c.heads, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
            encodeMatvec(e, L.o, attn, oBuf)
            encodeElementwise(e, "add_inplace", x, oBuf, c.hiddenSize)
            encodeRMSNorm(e, x, L.postNorm, h, c.hiddenSize)
            encodeMatvec(e, L.gate, h, gBuf)
            encodeMatvec(e, L.up, h, uBuf)
            encodeElementwise(e, "silu_mul", gBuf, uBuf, c.intermediateSize)
            encodeMatvec(e, L.down, gBuf, oBuf)
            encodeElementwise(e, "add_inplace", x, oBuf, c.hiddenSize)
        }
        encodeRMSNorm(e, x, finalNorm, h, c.hiddenSize)
        encodeMatvec(e, lmHead, h, logits)
        e.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let error = cb.error { throw LMError.io("GPU: \(error.localizedDescription)") }
        position += 1
        let n = lmHead.outFeatures
        let p = logits.contents().bindMemory(to: Float.self, capacity: n)
        return Array(UnsafeBufferPointer(start: p, count: n))
    }

    // MARK: Self-test (GPU kernels vs CPU reference on real weights)

    private func selfTest() throws {
        let prefix = store.has("model.embed_tokens.weight") ? "model." : ""
        let cpu = try LinearWeights.load(store, prefix + "layers.0.self_attn.q_proj", config: config)
        let gpu = layers[0].q
        var rng = SplitMix64(seed: 42)
        let input = (0..<cpu.inFeatures).map { _ in rng.nextUnit() - 0.5 }
        guard let inBuf = device.makeBuffer(bytes: input, length: input.count * 4, options: .storageModeShared),
              let outBuf = device.makeBuffer(length: cpu.outFeatures * 4, options: .storageModeShared),
              let cb = queue.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { throw LMError.io("self-test alloc") }
        encodeMatvec(e, gpu, inBuf, outBuf)
        e.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var reference = [Float](repeating: 0, count: cpu.outFeatures)
        input.withUnsafeBufferPointer { ip in reference.withUnsafeMutableBufferPointer { rp in cpu.apply(ip.baseAddress!, rp.baseAddress!) } }
        let got = outBuf.contents().bindMemory(to: Float.self, capacity: cpu.outFeatures)
        var maxErr: Float = 0, maxRef: Float = 1e-6
        for i in 0..<cpu.outFeatures {
            maxErr = max(maxErr, abs(got[i] - reference[i]))
            maxRef = max(maxRef, abs(reference[i]))
        }
        guard maxErr / maxRef < 0.02 else {
            throw LMError.unsupported(String(format: "GPU self-test failed (rel. error %.4f)", maxErr / maxRef))
        }
    }

    // MARK: Kernels

    static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void qmatvec4(device const uint* W [[buffer(0)]], device const half* S [[buffer(1)]], device const half* B [[buffer(2)]],
                         device const float* x [[buffer(3)]], device float* y [[buffer(4)]],
                         constant uint& inF [[buffer(5)]], constant uint& outF [[buffer(6)]], constant uint& G [[buffer(7)]],
                         uint gid [[threadgroup_position_in_grid]], uint sid [[simdgroup_index_in_threadgroup]],
                         uint lane [[thread_index_in_simdgroup]]) {
        uint row = gid * 2 + sid;
        if (row >= outF) return;
        uint wordsPerRow = inF / 8;
        uint groups = inF / G;
        device const uint* w = W + (ulong)row * wordsPerRow;
        float acc = 0.0f;
        for (uint word = lane; word < wordsPerRow; word += 32) {
            uint p = w[word];
            uint j = word * 8;
            uint g = j / G;
            float s = float(S[row * groups + g]);
            float b = float(B[row * groups + g]);
            float4 xa = float4(x[j], x[j + 1], x[j + 2], x[j + 3]);
            float4 xb = float4(x[j + 4], x[j + 5], x[j + 6], x[j + 7]);
            float4 qa = float4(float(p & 0xF), float((p >> 4) & 0xF), float((p >> 8) & 0xF), float((p >> 12) & 0xF));
            float4 qb = float4(float((p >> 16) & 0xF), float((p >> 20) & 0xF), float((p >> 24) & 0xF), float((p >> 28) & 0xF));
            acc += s * (dot(qa, xa) + dot(qb, xb)) + b * (xa.x + xa.y + xa.z + xa.w + xb.x + xb.y + xb.z + xb.w);
        }
        acc = simd_sum(acc);
        if (lane == 0) y[row] = acc;
    }

    kernel void qmatvec8(device const uint* W [[buffer(0)]], device const half* S [[buffer(1)]], device const half* B [[buffer(2)]],
                         device const float* x [[buffer(3)]], device float* y [[buffer(4)]],
                         constant uint& inF [[buffer(5)]], constant uint& outF [[buffer(6)]], constant uint& G [[buffer(7)]],
                         uint gid [[threadgroup_position_in_grid]], uint sid [[simdgroup_index_in_threadgroup]],
                         uint lane [[thread_index_in_simdgroup]]) {
        uint row = gid * 2 + sid;
        if (row >= outF) return;
        uint wordsPerRow = inF / 4;
        uint groups = inF / G;
        device const uint* w = W + (ulong)row * wordsPerRow;
        float acc = 0.0f;
        for (uint word = lane; word < wordsPerRow; word += 32) {
            uint p = w[word];
            uint j = word * 4;
            uint g = j / G;
            float s = float(S[row * groups + g]);
            float b = float(B[row * groups + g]);
            float4 xa = float4(x[j], x[j + 1], x[j + 2], x[j + 3]);
            float4 qa = float4(float(p & 0xFF), float((p >> 8) & 0xFF), float((p >> 16) & 0xFF), float((p >> 24) & 0xFF));
            acc += s * dot(qa, xa) + b * (xa.x + xa.y + xa.z + xa.w);
        }
        acc = simd_sum(acc);
        if (lane == 0) y[row] = acc;
    }

    kernel void rmsnorm(device const float* x [[buffer(0)]], device const float* w [[buffer(1)]], device float* y [[buffer(2)]],
                        constant uint& n [[buffer(3)]], constant float& eps [[buffer(4)]],
                        uint tid [[thread_position_in_threadgroup]], uint tg [[threads_per_threadgroup]],
                        uint lane [[thread_index_in_simdgroup]], uint wid [[simdgroup_index_in_threadgroup]]) {
        threadgroup float partial[32];
        float ss = 0.0f;
        for (uint i = tid; i < n; i += tg) ss += x[i] * x[i];
        ss = simd_sum(ss);
        if (lane == 0) partial[wid] = ss;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        if (wid == 0) {
            uint groups = (tg + 31) / 32;
            float v = lane < groups ? partial[lane] : 0.0f;
            v = simd_sum(v);
            if (lane == 0) partial[0] = v;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        float inv = rsqrt(partial[0] / float(n) + eps);
        for (uint i = tid; i < n; i += tg) y[i] = x[i] * inv * w[i];
    }

    kernel void headnorm_rope(device float* v [[buffer(0)]], device const float* w [[buffer(1)]],
                              device const float* cosT [[buffer(2)]], device const float* sinT [[buffer(3)]],
                              constant uint& headDim [[buffer(4)]], constant uint& pos [[buffer(5)]], constant float& eps [[buffer(6)]],
                              uint head [[threadgroup_position_in_grid]], uint tid [[thread_position_in_threadgroup]],
                              uint lane [[thread_index_in_simdgroup]], uint wid [[simdgroup_index_in_threadgroup]]) {
        threadgroup float partial[8];
        threadgroup float shared[512];
        device float* hv = v + head * headDim;
        float val = hv[tid];
        float ss = simd_sum(val * val);
        if (lane == 0) partial[wid] = ss;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        float total = 0.0f;
        uint groups = (headDim + 31) / 32;
        for (uint i = 0; i < groups; i++) total += partial[i];
        float inv = rsqrt(total / float(headDim) + eps);
        shared[tid] = val * inv * w[tid];
        threadgroup_barrier(mem_flags::mem_threadgroup);
        uint halfDim = headDim / 2;
        uint i = tid % halfDim;
        float c = cosT[pos * halfDim + i];
        float s = sinT[pos * halfDim + i];
        float out = tid < halfDim ? shared[tid] * c - shared[tid + halfDim] * s : shared[tid] * c + shared[tid - halfDim] * s;
        hv[tid] = out;
    }

    kernel void kv_store(device const float* k [[buffer(0)]], device const float* v [[buffer(1)]],
                         device half* K [[buffer(2)]], device half* V [[buffer(3)]],
                         constant uint& kvDim [[buffer(4)]], constant uint& pos [[buffer(5)]], uint i [[thread_position_in_grid]]) {
        if (i >= kvDim) return;
        K[pos * kvDim + i] = half(k[i]);
        V[pos * kvDim + i] = half(v[i]);
    }

    kernel void attention(device const float* q [[buffer(0)]], device const half* K [[buffer(1)]], device const half* V [[buffer(2)]],
                          device float* out [[buffer(3)]], constant uint& headDim [[buffer(4)]], constant uint& kvDim [[buffer(5)]],
                          constant uint& groups [[buffer(6)]], constant uint& seqLen [[buffer(7)]], constant float& scale [[buffer(8)]],
                          threadgroup float* scores [[threadgroup(0)]],
                          uint head [[threadgroup_position_in_grid]], uint tid [[thread_position_in_threadgroup]],
                          uint tg [[threads_per_threadgroup]], uint lane [[thread_index_in_simdgroup]], uint wid [[simdgroup_index_in_threadgroup]]) {
        threadgroup float red[32];
        uint kvh = head / groups;
        device const float* qh = q + head * headDim;
        float localMax = -INFINITY;
        for (uint t = tid; t < seqLen; t += tg) {
            device const half* k = K + t * kvDim + kvh * headDim;
            float d = 0.0f;
            for (uint i = 0; i < headDim; i++) d += qh[i] * float(k[i]);
            d *= scale;
            scores[t] = d;
            localMax = max(localMax, d);
        }
        localMax = simd_max(localMax);
        if (lane == 0) red[wid] = localMax;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        float m = -INFINITY;
        for (uint i = 0; i < (tg + 31) / 32; i++) m = max(m, red[i]);
        threadgroup_barrier(mem_flags::mem_threadgroup);
        float localSum = 0.0f;
        for (uint t = tid; t < seqLen; t += tg) {
            float e = exp(scores[t] - m);
            scores[t] = e;
            localSum += e;
        }
        localSum = simd_sum(localSum);
        if (lane == 0) red[wid] = localSum;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        float total = 0.0f;
        for (uint i = 0; i < (tg + 31) / 32; i++) total += red[i];
        float invTotal = 1.0f / total;
        for (uint i = tid; i < headDim; i += tg) {
            float acc = 0.0f;
            for (uint t = 0; t < seqLen; t++) acc += scores[t] * float(V[t * kvDim + kvh * headDim + i]);
            out[head * headDim + i] = acc * invTotal;
        }
    }

    kernel void silu_mul(device float* g [[buffer(0)]], device const float* u [[buffer(1)]], constant uint& n [[buffer(2)]],
                         uint i [[thread_position_in_grid]]) {
        if (i >= n) return;
        float a = g[i];
        g[i] = a / (1.0f + exp(-a)) * u[i];
    }

    kernel void add_inplace(device float* a [[buffer(0)]], device const float* b [[buffer(1)]], constant uint& n [[buffer(2)]],
                            uint i [[thread_position_in_grid]]) {
        if (i >= n) return;
        a[i] += b[i];
    }

    kernel void embed_row(device const uint* W [[buffer(0)]], device const half* S [[buffer(1)]], device const half* B [[buffer(2)]],
                          device float* x [[buffer(3)]], constant uint& dim [[buffer(4)]], constant uint& token [[buffer(5)]],
                          constant uint& G [[buffer(6)]], constant uint& bits [[buffer(7)]], uint j [[thread_position_in_grid]]) {
        if (j >= dim) return;
        uint perWord = 32 / bits;
        uint wordsPerRow = dim / perWord;
        uint groups = dim / G;
        uint word = W[(ulong)token * wordsPerRow + j / perWord];
        uint mask = (1u << bits) - 1u;
        float q = float((word >> ((j % perWord) * bits)) & mask);
        uint g = j / G;
        x[j] = float(S[token * groups + g]) * q + float(B[token * groups + g]);
    }
    """
}
#endif

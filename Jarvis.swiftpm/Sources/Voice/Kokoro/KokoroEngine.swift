import CoreML
import Foundation

/// **Kokoro-82M neural voice** (British gentleman: `bm_george` by default).
///
/// Runs the end-to-end Core ML conversion (`kokoro_5s.mlmodelc`: BERT →
/// duration → alignment → prosody → iSTFT decoder) on the Neural Engine.
/// Inputs: `input_ids`/`attention_mask` [1,128] int32, `ref_s` [1,256] voice
/// style, `speed` [1], `random_phases` [1,9]; output: 24 kHz `audio`.
actor KokoroEngine {
    static let shared = KokoroEngine()

    static let repo = "aufklarer/Kokoro-82M-CoreML-INT8"
    static let britishVoices = ["bm_george", "bm_lewis", "bm_daniel", "bm_fable"]
    static let sampleRate = 24_000

    enum Status: Equatable {
        case notInstalled, installing(Double), installed, ready, failed(String)
    }

    private(set) var status: Status = .notInstalled
    private var model: MLModel?
    private var phonemizer: KokoroPhonemizer?
    private var voices: [String: [Float]] = [:]

    static var directory: URL { JarvisPaths.models.appendingPathComponent("Kokoro", isDirectory: true) }

    static var isInstalled: Bool {
        let fm = FileManager.default
        let d = directory
        return fm.fileExists(atPath: d.appendingPathComponent("kokoro_5s.mlmodelc/weights/weight.bin").path)
            && fm.fileExists(atPath: d.appendingPathComponent("vocab_index.json").path)
            && fm.fileExists(atPath: d.appendingPathComponent("voices/bm_george.json").path)
    }

    // MARK: Installation

    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        status = .installing(0)
        do {
            let wanted: (String) -> Bool = { path in
                path.hasPrefix("kokoro_5s.mlmodelc/") || path.hasPrefix("G2PEncoder.mlmodelc/") || path.hasPrefix("G2PDecoder.mlmodelc/")
                    || path == "vocab_index.json" || path == "g2p_vocab.json" || path == "us_gold.json" || path == "us_silver.json"
                    || Self.britishVoices.contains { path == "voices/\($0).json" } || path == "voices/bf_emma.json"
            }
            var items = try await ModelDownloader.huggingFaceFiles(repo: Self.repo, include: wanted)
            // British pronunciation dictionaries (misaki, Apache-2.0).
            for name in ["gb_gold.json", "gb_silver.json"] {
                if let url = URL(string: "https://raw.githubusercontent.com/hexgrad/misaki/main/misaki/data/\(name)") {
                    items.append(ModelDownloader.Item(url: url, relativePath: name, size: name == "gb_gold.json" ? 2_838_552 : 3_663_898))
                }
            }
            let downloader = ModelDownloader()
            try await downloader.download(items, to: Self.directory) { p in progress(p) }
            status = .installed
            try load()
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: Loading

    func load() throws {
        let dir = Self.directory
        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: dir.appendingPathComponent("kokoro_5s.mlmodelc", isDirectory: true), configuration: config)

        let g2p = NeuralG2P(directory: dir)

        let lexicon = PronunciationLexicon()
        for name in ["gb_gold.json", "gb_silver.json", "us_gold.json"] {
            if let data = try? Data(contentsOf: dir.appendingPathComponent(name)) { try? lexicon.load(jsonData: data) }
        }
        let vocab = try KokoroPhonemizer.loadVocab(jsonData: Data(contentsOf: dir.appendingPathComponent("vocab_index.json")))
        let p = KokoroPhonemizer(lexicon: lexicon, vocab: vocab)
        if g2p.isAvailable { p.neuralFallback = { word in g2p.convert(word) } }
        phonemizer = p

        voices.removeAll()
        let voiceDir = dir.appendingPathComponent("voices")
        for file in (try? FileManager.default.contentsOfDirectory(atPath: voiceDir.path)) ?? [] where file.hasSuffix(".json") {
            if let data = try? Data(contentsOf: voiceDir.appendingPathComponent(file)),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let emb = obj["embedding"] as? [NSNumber], emb.count == 256 {
                voices[String(file.dropLast(5))] = emb.map { $0.floatValue }
            }
        }
        guard !voices.isEmpty else { throw NSError(domain: "Kokoro", code: 2, userInfo: [NSLocalizedDescriptionKey: "No voices found"]) }
        status = .ready
        // Warm up the Neural Engine so the first real sentence is fast.
        _ = try? synthesize("Ready.", voice: "bm_george", speed: 1)
    }

    var availableVoices: [String] { voices.keys.sorted() }
    var isReady: Bool { status == .ready }

    // MARK: Synthesis

    /// Synthesize British English speech. Returns mono float samples at 24 kHz.
    func synthesize(_ text: String, voice: String, speed: Float) throws -> [Float] {
        guard let model, let phonemizer else { throw NSError(domain: "Kokoro", code: 1, userInfo: [NSLocalizedDescriptionKey: "Kokoro not loaded"]) }
        let style = voices[voice] ?? voices["bm_george"] ?? voices.values.first ?? []
        var output: [Float] = []
        for chunk in phonemizer.chunks(for: text) {
            var audio = try run(model: model, ids: chunk.ids, style: style, speed: speed)
            if !output.isEmpty { Self.fadeIn(&audio) }
            output += audio
            // Natural pause between sentences.
            output += [Float](repeating: 0, count: Self.sampleRate / 12)
        }
        return output
    }

    private func run(model: MLModel, ids: [Int], style: [Float], speed: Float) throws -> [Float] {
        let slots = KokoroPhonemizer.maxTokens
        let tokens = [KokoroPhonemizer.padID] + ids.prefix(slots - 2) + [KokoroPhonemizer.padID]
        let inputIDs = try MLMultiArray(shape: [1, NSNumber(value: slots)], dataType: .int32)
        let mask = try MLMultiArray(shape: [1, NSNumber(value: slots)], dataType: .int32)
        let ip = inputIDs.dataPointer.assumingMemoryBound(to: Int32.self)
        let mp = mask.dataPointer.assumingMemoryBound(to: Int32.self)
        for i in 0..<slots {
            ip[i] = i < tokens.count ? Int32(tokens[i]) : 0
            mp[i] = i < tokens.count ? 1 : 0
        }
        let refS = try MLMultiArray(shape: [1, 256], dataType: .float32)
        let rp = refS.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<256 { rp[i] = i < style.count ? style[i] : 0 }
        let speedArray = try MLMultiArray(shape: [1], dataType: .float32)
        speedArray.dataPointer.assumingMemoryBound(to: Float.self)[0] = speed
        let phases = try MLMultiArray(shape: [1, 9], dataType: .float32)
        let pp = phases.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<9 { pp[i] = Float.random(in: 0..<1) }

        let features = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
            "attention_mask": MLFeatureValue(multiArray: mask),
            "ref_s": MLFeatureValue(multiArray: refS),
            "speed": MLFeatureValue(multiArray: speedArray),
            "random_phases": MLFeatureValue(multiArray: phases),
        ])
        let result = try model.prediction(from: features)
        guard let audio = result.featureValue(for: "audio")?.multiArrayValue else { return [] }
        var length = audio.count
        if let len = result.featureValue(for: "audio_length_samples")?.multiArrayValue, len.count > 0 {
            length = min(audio.count, len[0].intValue)
        }
        var samples = [Float](repeating: 0, count: max(0, length))
        switch audio.dataType {
        case .float16:
            // NSNumber bridging avoids Float16 (unavailable on x86_64 simulators).
            for i in 0..<samples.count { samples[i] = audio[i].floatValue }
        case .double:
            let p = audio.dataPointer.assumingMemoryBound(to: Double.self)
            for i in 0..<samples.count { samples[i] = Float(p[i]) }
        default:
            let p = audio.dataPointer.assumingMemoryBound(to: Float.self)
            for i in 0..<samples.count { samples[i] = p[i] }
        }
        Self.trimTrailingArtifacts(&samples)
        return samples
    }

    /// The E2E model can emit a short burst of low-energy noise after speech; cut it.
    static func trimTrailingArtifacts(_ audio: inout [Float]) {
        let window = Int(0.05 * Double(sampleRate))
        guard audio.count > window * 2 else { return }
        var end = audio.count
        var i = audio.count - window
        while i > 0 {
            var energy: Float = 0
            for j in 0..<window { energy += audio[i + j] * audio[i + j] }
            if (energy / Float(window)).squareRoot() > 0.015 { end = i + window; break }
            i -= window / 2
        }
        audio.removeSubrange(min(end, audio.count)..<audio.count)
        let fade = min(audio.count, sampleRate / 100)
        for k in 0..<fade { audio[audio.count - fade + k] *= Float(fade - k) / Float(fade) }
        for k in 0..<audio.count { audio[k] = max(-1, min(1, audio[k])) }
    }

    static func fadeIn(_ audio: inout [Float]) {
        let n = min(audio.count, sampleRate / 200)
        for i in 0..<n { audio[i] *= Float(i) / Float(n) }
    }

}

/// Neural grapheme-to-phoneme model (BART encoder/decoder, Core ML) used for
/// words missing from the British dictionaries. Only used from inside `KokoroEngine`.
final class NeuralG2P {
    private let encoder: MLModel?
    private let decoder: MLModel?
    private var graphemeToID: [String: Int] = [:]
    private var idToPhoneme: [Int: String] = [:]

    init(directory dir: URL) {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        encoder = try? MLModel(contentsOf: dir.appendingPathComponent("G2PEncoder.mlmodelc", isDirectory: true), configuration: config)
        decoder = try? MLModel(contentsOf: dir.appendingPathComponent("G2PDecoder.mlmodelc", isDirectory: true), configuration: config)
        if let data = try? Data(contentsOf: dir.appendingPathComponent("g2p_vocab.json")),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in (obj["grapheme_to_id"] as? [String: Any]) ?? [:] {
                if let n = v as? NSNumber { graphemeToID[k] = n.intValue }
            }
            for (k, v) in (obj["id_to_phoneme"] as? [String: Any]) ?? [:] {
                if let i = Int(k), let p = v as? String { idToPhoneme[i] = p }
            }
        }
    }

    var isAvailable: Bool { encoder != nil && decoder != nil && !graphemeToID.isEmpty }

    /// Greedy decoding; returns US-style misaki phonemes (converted to GB by the caller).
    /// Written as small typed steps so older Swift compilers type-check it quickly.
    func convert(_ word: String) -> String? {
        guard let encoder, let decoder, word.count < 60 else { return nil }
        do {
            let inputIDs: MLMultiArray = try Self.int32Array(graphemeIDs(word))
            let encoderInputs: [String: MLFeatureValue] = ["input_ids": MLFeatureValue(multiArray: inputIDs)]
            let encoded: MLFeatureProvider = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: encoderInputs))
            guard let hidden: MLMultiArray = encoded.featureValue(for: "encoder_hidden_states")?.multiArrayValue else { return nil }
            var decoded: [Int32] = [1]
            for _ in 0..<63 {
                guard let next: Int = try nextToken(decoder: decoder, decoded: decoded, hidden: hidden), next != 2 else { break }
                decoded.append(Int32(next))
            }
            let phonemes: String = phonemeString(decoded)
            return phonemes.isEmpty ? nil : phonemes
        } catch {
            return nil
        }
    }

    private func graphemeIDs(_ word: String) -> [Int32] {
        var ids: [Int32] = [1]
        for ch in word {
            let s = String(ch)
            let id: Int = graphemeToID[s] ?? graphemeToID[s.lowercased()] ?? 3
            ids.append(Int32(id))
        }
        ids.append(2)
        return ids
    }

    private static func int32Array(_ values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
        let pointer: UnsafeMutablePointer<Int32> = array.dataPointer.assumingMemoryBound(to: Int32.self)
        for i in 0..<values.count { pointer[i] = values[i] }
        return array
    }

    private static func causalMask(_ n: Int) throws -> MLMultiArray {
        let mask = try MLMultiArray(shape: [1, NSNumber(value: n), NSNumber(value: n)], dataType: .float32)
        let pointer: UnsafeMutablePointer<Float> = mask.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<n {
            for j in 0..<n {
                let blocked: Bool = j > i
                pointer[i * n + j] = blocked ? -1e9 : 0
            }
        }
        return mask
    }

    /// One greedy decoder step: the most likely next token id (nil when the model gave no logits).
    private func nextToken(decoder: MLModel, decoded: [Int32], hidden: MLMultiArray) throws -> Int? {
        let n: Int = decoded.count
        var positions: [Int32] = []
        for i in 0..<n { positions.append(Int32(i)) }
        let inputs: [String: MLFeatureValue] = [
            "decoder_input_ids": MLFeatureValue(multiArray: try Self.int32Array(decoded)),
            "encoder_hidden_states": MLFeatureValue(multiArray: hidden),
            "position_ids": MLFeatureValue(multiArray: try Self.int32Array(positions)),
            "causal_mask": MLFeatureValue(multiArray: try Self.causalMask(n)),
        ]
        let output: MLFeatureProvider = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))
        guard let logits: MLMultiArray = output.featureValue(for: "logits")?.multiArrayValue,
              let vocabSize: Int = logits.shape.last?.intValue, vocabSize > 0 else { return nil }
        // Logits cover every decoder position ([1, n, V]) or only the last one ([1, 1, V]).
        let available: Int = max(1, logits.count / vocabSize)
        let offset: Int = (min(n, available) - 1) * vocabSize
        var best: Int = 0
        var bestValue: Float = -Float.infinity
        for v in 0..<vocabSize {
            let value: Float = logits[offset + v].floatValue
            if value > bestValue {
                bestValue = value
                best = v
            }
        }
        return best
    }

    private func phonemeString(_ decoded: [Int32]) -> String {
        var out = ""
        for token in decoded.dropFirst() {
            guard let phoneme: String = idToPhoneme[Int(token)], phoneme.count == 1 else { continue }
            out += phoneme
        }
        return out
    }
}

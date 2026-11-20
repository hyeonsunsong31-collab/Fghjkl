import Foundation

/// Fine-control parameters produced by the cerebellum for one response.
struct CerebellarOutput: Codable, Equatable {
    /// Predicted wall-clock duration of the task (seconds).
    var predictedSeconds: Double
    /// 0 = terse, 1 = elaborate.
    var verbosity: Float
    /// Sampling temperature for the language model.
    var temperature: Float
    /// Speech-rate multiplier (1 = natural).
    var speechRate: Float
    /// Upper bound on generated tokens.
    var maxTokens: Int
    /// Characters per TTS chunk (smaller = faster first audio).
    var ttsChunkCharacters: Int
}

/// Output microzones of the cerebellar cortex.
enum Microzone: Int, CaseIterable {
    case latency, verbosity, temperature, speechRate
}

/// **Cerebellum** — predictive fine control and error correction.
///
/// Mossy-fibre context → a large, sparse **granule-cell expansion** (Golgi
/// inhibition keeps ~5 % active) → **Purkinje** synaptic perceptrons, one per
/// microzone, whose parallel-fibre synapses learn by climbing-fibre error
/// (Marr–Albus–Ito LTD). Deep-nuclei output = baseline modulated by Purkinje
/// activity. It *predicts* how long a task will take (for "approximately N
/// seconds" announcements) and *trims* verbosity, temperature and speech rate
/// from the consequences of previous answers (interruptions, corrections,
/// requests for more detail).
final class Cerebellum {
    static let mossyCount = 40
    static let granuleCount = 4096

    let granule: PerceptronPopulation
    let purkinje: PerceptronPopulation
    let dcnIDs: [NeuronID]
    private(set) var lastMossy: [Float] = []

    /// Baselines (DCN tonic output) per microzone.
    private let latencyLogBaseline: Float = 0.7   // e^0.7 ≈ 2 s
    private let latencyLogScale: Float = 2.5

    init(seed: UInt64) {
        granule = PerceptronPopulation(name: "cerebellum.granule",
                                       ids: RegionAllocator.ids(in: .cerebellumGranule, count: Self.granuleCount, seed: seed),
                                       inputSize: Self.mossyCount, connectivity: .random(fanIn: 4),
                                       weightScale: 1.0, activation: .relu, rule: .none,
                                       kWinners: Self.granuleCount / 20, seed: seed &+ 1)
        purkinje = PerceptronPopulation(name: "cerebellum.purkinje",
                                        ids: RegionAllocator.ids(in: .cerebellumPurkinje, count: Microzone.allCases.count, seed: seed &+ 2),
                                        inputSize: Self.granuleCount, connectivity: .dense,
                                        weightScale: 0.0005, activation: .tanh,
                                        learningRate: 0.05, rule: .cerebellarLTD,
                                        receptors: .cerebellar, seed: seed &+ 3)
        dcnIDs = RegionAllocator.ids(in: .deepCerebellarNuclei, count: Microzone.allCases.count, seed: seed &+ 4)
    }

    /// Mossy-fibre encoding of the situation.
    static func mossyFibres(intents: [IntentClass: Float], action: AgentAction, textLength: Int,
                            isVoice: Bool, language: DetectedLanguage, toolCount: Int,
                            body: BodyState, salience: Float) -> [Float] {
        var m = [Float](repeating: 0, count: mossyCount)
        for i in IntentClass.allCases { m[i.index] = intents[i] ?? 0 }       // 0..11
        m[12 + action.index] = 1                                             // 12..16
        let lenBucket = min(5, Int(log2(Double(max(1, textLength)))) / 2)   // 17..22
        m[17 + lenBucket] = 1
        m[23] = isVoice ? 1 : 0
        m[24] = language == .korean ? 1 : 0
        m[25] = language == .english ? 1 : 0
        m[26 + min(3, toolCount)] = 1                                         // 26..29
        m[30] = body.lowPowerMode ? 1 : 0
        m[31] = Float(body.thermalState) / 3
        m[32] = salience
        m[33] = 1 // bias fibre
        return m
    }

    func predict(mossy: [Float], modulators: NeuromodulatorState, budget: ComputeBudget) -> CerebellarOutput {
        lastMossy = mossy
        let g = granule.step(mossy, modulators: modulators)
        let p = purkinje.step(g, modulators: modulators)
        let latency = Double(exp(latencyLogBaseline + latencyLogScale * p[Microzone.latency.rawValue]))
        let verbosity = NeuroMath.clamp(0.5 + 0.5 * p[Microzone.verbosity.rawValue], 0.05, 1)
        let temperature = NeuroMath.clamp(0.65 + 0.3 * p[Microzone.temperature.rawValue], 0.1, 1.2)
        let speechRate = NeuroMath.clamp(1 + 0.25 * p[Microzone.speechRate.rawValue], 0.7, 1.35)
        let maxTokens = min(budget.maxResponseTokens, Int(120 + 600 * verbosity))
        let chunk = Int(60 + 120 * verbosity)
        return CerebellarOutput(predictedSeconds: latency, verbosity: verbosity, temperature: temperature,
                                speechRate: speechRate, maxTokens: maxTokens, ttsChunkCharacters: chunk)
    }

    /// Climbing-fibre learning. `targets` are desired microzone outputs in (−1, 1);
    /// the error (current − target) drives LTD at active parallel fibres.
    func learn(targets: [Microzone: Float], modulators: NeuromodulatorState) {
        guard !lastMossy.isEmpty else { return }
        var teaching = [Float](repeating: 0, count: Microzone.allCases.count)
        for (zone, target) in targets {
            teaching[zone.rawValue] = purkinje.output[zone.rawValue] - NeuroMath.clamp(target, -0.99, 0.99)
        }
        // Normalised LMS: each climbing-fibre event moves the output ~35 % of the way
        // to its target regardless of how many parallel fibres were active.
        let g = granule.output
        var energy: Float = 0
        for v in g { energy += v * v }
        let scale = 0.35 / (purkinje.learningRate * modulators.learningGain * max(1e-3, energy))
        purkinje.learn(modulators: modulators, teaching: teaching, rateScale: scale)
    }

    /// Convert an observed duration into the latency microzone's target value.
    func latencyTarget(seconds: Double) -> Float {
        let y = (Float(log(max(0.05, seconds))) - latencyLogBaseline) / latencyLogScale
        return NeuroMath.clamp(y, -0.99, 0.99)
    }

    func currentOutput(_ zone: Microzone) -> Float { purkinje.output[zone.rawValue] }

    func archive(into w: inout BinaryWriter) {
        granule.archive(into: &w); purkinje.archive(into: &w)
    }

    func restore(from r: inout BinaryReader) throws {
        try granule.restore(from: &r); try purkinje.restore(from: &r)
    }
}

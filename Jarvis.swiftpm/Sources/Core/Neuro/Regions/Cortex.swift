import Foundation

struct CorticalState {
    /// Active layer-2/3 cells (the concept code).
    var concept: SparseCode
    var intentScores: [IntentClass: Float]
    var topIntent: IntentClass
    /// Layer-6 feedback to the thalamus: preference for each context kind.
    var thalamicFeedback: [ChannelKind: Float]
    /// 0 = familiar, 1 = never seen anything like it.
    var novelty: Float
    var activeNeurons: [NeuronID]
}

/// **Cerebral cortex** — layered columns.
///
/// - L4 receives the thalamic input (the text SDR) through sparse random synapses;
///   lateral inhibition keeps ~10 % of columns active (pattern separation).
/// - L2/3 learns associations with Hebbian/Oja plasticity and k-winners-take-all,
///   producing a sparse *concept code*; a decaying copy acts as working memory.
/// - L5 is the output layer: synaptic perceptrons trained by three-factor
///   learning read out the intent class.
/// - L6 projects back to the thalamus, telling the TRN which kinds of context
///   to let through for this kind of request.
final class Cortex {
    static let inputSize = 2048
    static let l4Size = 512
    static let l23Size = 1024

    let l4: PerceptronPopulation
    let l23: PerceptronPopulation
    let l5: PerceptronPopulation
    let l6: PerceptronPopulation
    private var workingMemory: [Float]
    private var recentConcepts: [SparseCode] = []

    init(seed: UInt64) {
        l4 = PerceptronPopulation(name: "cortex.L4",
                                  ids: RegionAllocator.ids(in: .cortexL4, count: Self.l4Size, seed: seed),
                                  inputSize: Self.inputSize, connectivity: .random(fanIn: 64),
                                  weightScale: 0.5, activation: .relu, rule: .none,
                                  kWinners: 48, seed: seed &+ 1)
        l23 = PerceptronPopulation(name: "cortex.L23",
                                   ids: RegionAllocator.ids(in: .cortexL23, count: Self.l23Size, seed: seed &+ 2),
                                   inputSize: Self.l4Size + Self.l23Size, connectivity: .random(fanIn: 48),
                                   weightScale: 0.4, activation: .relu,
                                   targetRate: 0.03, homeostasisRate: 0.002, learningRate: 0.01,
                                   rule: .hebbian, stpEnabled: true, branchCount: 1,
                                   kWinners: 40, seed: seed &+ 3)
        l5 = PerceptronPopulation(name: "cortex.L5",
                                  ids: RegionAllocator.ids(in: .cortexL5, count: IntentClass.allCases.count, seed: seed &+ 4),
                                  inputSize: Self.l23Size, connectivity: .dense,
                                  weightScale: 0.01, activation: .sigmoid,
                                  learningRate: 0.35, rule: .threeFactor,
                                  receptors: ModulatorReceptors(dopamine: 0, acetylcholine: 0, noradrenaline: 0, serotonin: 0),
                                  seed: seed &+ 5)
        l6 = PerceptronPopulation(name: "cortex.L6",
                                  ids: RegionAllocator.ids(in: .cortexL6, count: ChannelKind.allCases.count, seed: seed &+ 6),
                                  inputSize: Self.l23Size, connectivity: .dense,
                                  weightScale: 0.01, activation: .sigmoid,
                                  learningRate: 0.1, rule: .threeFactor,
                                  receptors: ModulatorReceptors(dopamine: 0, acetylcholine: 0, noradrenaline: 0, serotonin: 0),
                                  seed: seed &+ 7)
        for i in 0..<l5.size { l5.bias[i] = -2 }
        workingMemory = [Float](repeating: 0, count: Self.l23Size)
    }

    func perceive(_ code: SparseCode, modulators: NeuromodulatorState) -> CorticalState {
        let input = code.dense()
        let l4Out = l4.step(input, modulators: modulators)
        // L2/3 sees L4 plus its own working-memory trace (recurrence).
        let l23Out = l23.step(l4Out + workingMemory, modulators: modulators)
        for i in 0..<Self.l23Size { workingMemory[i] = workingMemory[i] * 0.6 + (l23Out[i] > 0 ? 0.4 : 0) }
        l23.learn(modulators: modulators)

        let binary = l23Out.map { $0 > 0 ? Float(1) : 0 }
        let intents = l5.step(binary, modulators: modulators)
        let feedback = l6.step(binary, modulators: modulators)

        let activeIdx = (0..<Self.l23Size).filter { l23Out[$0] > 0 }
        let concept = SparseCode(indices: activeIdx, size: Self.l23Size)
        let novelty: Float = recentConcepts.isEmpty ? 1 : 1 - (recentConcepts.map { $0.similarity(concept) }.max() ?? 0)
        recentConcepts.append(concept)
        if recentConcepts.count > 64 { recentConcepts.removeFirst() }

        var scores: [IntentClass: Float] = [:]
        for intent in IntentClass.allCases { scores[intent] = intents[intent.index] }
        let top = IntentClass.allCases.max { (scores[$0] ?? 0) < (scores[$1] ?? 0) } ?? .other
        var fb: [ChannelKind: Float] = [:]
        for kind in ChannelKind.allCases { fb[kind] = 0.25 + 0.5 * feedback[kind.index] }

        let active = activeIdx.prefix(64).map { l23.ids[$0] } + l4.activeIndices(level: 0).prefix(32).map { l4.ids[$0] }
        return CorticalState(concept: concept, intentScores: scores, topIntent: top,
                             thalamicFeedback: fb, novelty: novelty, activeNeurons: Array(active))
    }

    /// Supervised (teaching-signal) learning of the intent readout for the last percept.
    func teachIntent(_ label: IntentClass, modulators: NeuromodulatorState, strength: Float = 1) {
        let teaching = IntentClass.allCases.map { intent -> Float in
            let target: Float = intent == label ? 1 : 0
            return (target - l5.output[intent.index]) * strength
        }
        let active = l23.output.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
        l5.learn(modulators: modulators, teaching: teaching, rateScale: 4 / Float(max(1, active)))
    }

    /// Reward-driven learning of L6 → thalamus preferences.
    func teachFeedback(useful: Set<ChannelKind>, reward: Float, modulators: NeuromodulatorState) {
        let teaching = ChannelKind.allCases.map { kind -> Float in
            let target: Float = useful.contains(kind) ? 1 : 0.2
            return (target - l6.output[kind.index]) * max(0.1, reward)
        }
        let active = l23.output.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
        l6.learn(modulators: modulators, teaching: teaching, rateScale: 2 / Float(max(1, active)))
    }

    func archive(into w: inout BinaryWriter) {
        l4.archive(into: &w); l23.archive(into: &w); l5.archive(into: &w); l6.archive(into: &w)
    }

    func restore(from r: inout BinaryReader) throws {
        try l4.restore(from: &r); try l23.restore(from: &r); try l5.restore(from: &r); try l6.restore(from: &r)
    }
}

import Foundation

/// **Basal ganglia** — action selection by Go/NoGo competition.
///
/// Striatal D1 ("Go") and D2 ("NoGo") synaptic perceptrons score each action
/// from cortical and contextual features; the action with the strongest net Go
/// is released (GPi disinhibition of the thalamus). A critic estimates the
/// expected reward; the dopamine reward-prediction error δ then potentiates D1
/// and depresses D2 synapses of the chosen action (and vice-versa), so Jarvis
/// learns which way of answering works best for which situation.
final class BasalGanglia {
    /// [grammarConfidence, complexity, questionness, novelty, deepThinkAvailable,
    ///  deepThinkRequested, isVoice, ambiguity] + intent scores
    static let baseFeatures = 8
    static var featureCount: Int { baseFeatures + IntentClass.allCases.count }

    let d1: PerceptronPopulation
    let d2: PerceptronPopulation
    let critic: PerceptronPopulation
    private var lastFeatures: [Float] = []
    private var lastAction: AgentAction = .conversational
    private var lastValue: Float = 0

    init(seed: UInt64) {
        let noTonic = ModulatorReceptors(dopamine: 0, acetylcholine: 0, noradrenaline: 0, serotonin: 0)
        d1 = PerceptronPopulation(name: "bg.D1", ids: RegionAllocator.ids(in: .striatum, count: AgentAction.allCases.count, seed: seed),
                                  inputSize: Self.featureCount, connectivity: .dense, weightScale: 0.01,
                                  activation: .sigmoid, learningRate: 0.15, rule: .threeFactor, receptors: noTonic, seed: seed &+ 1)
        d2 = PerceptronPopulation(name: "bg.D2", ids: RegionAllocator.ids(in: .striatum, count: AgentAction.allCases.count, seed: seed &+ 9),
                                  inputSize: Self.featureCount, connectivity: .dense, weightScale: 0.01,
                                  activation: .sigmoid, learningRate: 0.15, rule: .threeFactor, receptors: noTonic, seed: seed &+ 2)
        critic = PerceptronPopulation(name: "bg.critic", ids: RegionAllocator.ids(in: .substantiaNigraCompacta, count: 1, seed: seed &+ 3),
                                      inputSize: Self.featureCount, connectivity: .dense, weightScale: 0.01,
                                      activation: .tanh, learningRate: 0.1, rule: .threeFactor, receptors: noTonic, seed: seed &+ 4)
        d1.weightLimit = 8
        d2.weightLimit = 8
        installPriors()
    }

    /// Innate priors so the system behaves sensibly before any learning.
    private func installPriors() {
        let intent = { (i: IntentClass) in Self.baseFeatures + i.index }
        func go(_ a: AgentAction, _ input: Int, _ w: Float) { d1.setSignedWeight(row: a.index, input: input, value: w) }
        for a in AgentAction.allCases { d1.bias[a.index] = -1.5; d2.bias[a.index] = -1.5 }

        go(.fastCommand, 0, 6.0)          // grammar confidence → instant command
        d1.bias[AgentAction.fastCommand.index] = -4.5

        d1.bias[AgentAction.conversational.index] = 0.5
        go(.conversational, intent(.smallTalk), 1.5)
        go(.conversational, intent(.question), 1.2)
        go(.conversational, 0, -2.0)

        d1.bias[AgentAction.toolUse.index] = -1.5
        for i in [IntentClass.deviceControl, .appLaunch, .web, .music, .fileTask, .command3D, .memoryRecall] {
            go(.toolUse, intent(i), 3.0)
        }
        go(.toolUse, 0, -1.0)

        d1.bias[AgentAction.clarify.index] = -3.0
        go(.clarify, 7, 3.0)               // ambiguity

        d1.bias[AgentAction.deepThink.index] = -4.0
        go(.deepThink, 1, 2.0)             // complexity
        go(.deepThink, 5, 6.0)             // explicitly requested
        go(.deepThink, 4, 0.8)             // available
    }

    static func features(grammarConfidence: Float, complexity: Float, questionness: Float, novelty: Float,
                         deepThinkAvailable: Bool, deepThinkRequested: Bool, isVoice: Bool, ambiguity: Float,
                         intents: [IntentClass: Float]) -> [Float] {
        var f: [Float] = [grammarConfidence, complexity, questionness, novelty,
                          deepThinkAvailable ? 1 : 0, deepThinkRequested ? 1 : 0, isVoice ? 1 : 0, ambiguity]
        // Intent evidence enters as a sharpened distribution (sums to 1), so an
        // untrained cortex (all scores equal) is neutral rather than additive.
        let raw = IntentClass.allCases.map { intents[$0] ?? 0 }
        let peak = raw.max() ?? 0
        let exps = raw.map { Float(exp(Double(5 * ($0 - peak)))) }
        let total = exps.reduce(0, +)
        for e in exps { f.append(e / total) }
        return f
    }

    func select(features: [Float], modulators: NeuromodulatorState, allowDeepThink: Bool, rng: inout SplitMix64) -> (AgentAction, [AgentAction: Float]) {
        lastFeatures = features
        let go = d1.step(features, modulators: modulators)
        let noGo = d2.step(features, modulators: modulators)
        lastValue = critic.step(features, modulators: modulators)[0]

        var net = [Float](repeating: 0, count: AgentAction.allCases.count)
        for a in AgentAction.allCases {
            net[a.index] = go[a.index] - 0.8 * noGo[a.index]
            if a == .deepThink && !allowDeepThink { net[a.index] = -10 }
        }
        // Softmax with inverse temperature reduced by noradrenaline (exploration)
        // and increased by serotonin (patience → commit to the best option).
        let beta = 8 * (1 - 0.5 * modulators.noradrenaline) * (0.75 + 0.5 * modulators.serotonin)
        let maxNet = net.max() ?? 0
        let exps = net.map { Float(exp(Double(beta * ($0 - maxNet)))) }
        let total = exps.reduce(0, +)
        var probs: [AgentAction: Float] = [:]
        for a in AgentAction.allCases { probs[a] = exps[a.index] / total }

        // Greedy release with small arousal-dependent exploration.
        var chosen = AgentAction.allCases[net.firstIndex(of: maxNet) ?? 1]
        if rng.nextUnit() < 0.02 * modulators.noradrenaline {
            var pick = rng.nextUnit()
            for a in AgentAction.allCases {
                pick -= probs[a] ?? 0
                if pick <= 0 { chosen = a; break }
            }
        }
        lastAction = chosen
        return (chosen, probs)
    }

    /// Learn from the reward obtained by the last selection. Returns the RPE δ.
    @discardableResult
    func learn(reward: Float, modulators: NeuromodulatorState) -> Float {
        guard !lastFeatures.isEmpty else { return 0 }
        let delta = NeuroMath.clamp(reward - lastValue, -1, 1)
        var goTeach = [Float](repeating: 0, count: AgentAction.allCases.count)
        var noGoTeach = goTeach
        goTeach[lastAction.index] = delta
        noGoTeach[lastAction.index] = -delta
        d1.learn(modulators: modulators, teaching: goTeach)
        d2.learn(modulators: modulators, teaching: noGoTeach)
        critic.learn(modulators: modulators, teaching: [delta])
        return delta
    }

    /// Imitation: when the correct action becomes known (e.g. grammar matched a
    /// command the LLM path would have handled), nudge the policy towards it.
    func imitate(_ action: AgentAction, modulators: NeuromodulatorState) {
        guard !lastFeatures.isEmpty else { return }
        let teach = AgentAction.allCases.map { $0 == action ? Float(0.5) : 0 }
        d1.learn(modulators: modulators, teaching: teach)
    }

    func archive(into w: inout BinaryWriter) {
        d1.archive(into: &w); d2.archive(into: &w); critic.archive(into: &w)
    }

    func restore(from r: inout BinaryReader) throws {
        try d1.restore(from: &r); try d2.restore(from: &r); try critic.restore(from: &r)
    }
}

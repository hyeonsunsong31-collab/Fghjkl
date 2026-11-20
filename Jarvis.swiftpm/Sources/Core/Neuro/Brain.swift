import Foundation

/// **Brain** — wires the regions into the loops that control Jarvis' output.
///
/// ```
///  text ─► encoder ─► THALAMUS (relay + TRN gate) ─► context admitted to the LLM
///                         ▲            │
///                    L6 feedback       ▼
///                     CORTEX  (L4 → L2/3 concept → L5 intent)
///                         │                         │
///                         ▼                         ▼
///                  BASAL GANGLIA (Go/NoGo)    CEREBELLUM (granule → Purkinje → DCN)
///                   action selection          latency / verbosity / temperature /
///                         │                   speech-rate fine control
///                         ▼                         │
///                     decision ◄────────────────────┘
///     outcome ─► VTA dopamine (RPE) ─► BG, thalamus, cortex plasticity
///             ─► inferior olive (CF error) ─► cerebellar LTD
///             ─► hippocampus (episode) ─► replay ─► cortex (consolidation)
/// ```
///
/// The objective of every synaptic perceptron is the *control score*: the
/// fraction of turns in which the AI's output satisfied every control
/// constraint (language, register, length, truthful tool claims, timing) on
/// the first attempt. All plasticity is driven, directly or through
/// neuromodulators, by deviations from that objective.
final class Brain {
    static let formatVersion: UInt32 = 3

    let seed: UInt64
    let encoder = TextEncoder()
    let connectome: ProceduralConnectome
    let thalamus: Thalamus
    let cortex: Cortex
    let basalGanglia: BasalGanglia
    let cerebellum: Cerebellum
    let hippocampus: Hippocampus
    let amygdala = Amygdala()
    let hypothalamus = Hypothalamus()
    let brainstem = Brainstem()

    /// Exponential moving average of first-attempt control success (0…1).
    private(set) var controlScore: Float = 0.5
    private(set) var decisionsMade = 0
    private var rng: SplitMix64
    private var lastDecision: BrainDecision?
    private var lastCode: SparseCode?
    private var lastMossy: [Float] = []

    init(seed: UInt64 = 0x4A41_5256_4953) {
        self.seed = seed
        self.rng = SplitMix64(seed: seed ^ 0xD1CE)
        connectome = ProceduralConnectome(seed: seed)
        thalamus = Thalamus(seed: seed &+ 10)
        cortex = Cortex(seed: seed &+ 20)
        basalGanglia = BasalGanglia(seed: seed &+ 30)
        cerebellum = Cerebellum(seed: seed &+ 40)
        hippocampus = Hippocampus(seed: seed &+ 50)
        brainstem.transition(to: .listening)
    }

    var modulators: NeuromodulatorState { brainstem.modulators }

    /// Number of materialised (densely simulated) core perceptrons.
    var coreNeuronCount: Int {
        Cortex.l4Size + Cortex.l23Size + cortex.l5.size + cortex.l6.size
            + basalGanglia.d1.size + basalGanglia.d2.size + 1
            + Cerebellum.granuleCount + cerebellum.purkinje.size
            + Hippocampus.dgSize + ChannelKind.allCases.count * 2
    }

    var coreSynapseCount: Int {
        cortex.l4.synapseCount + cortex.l23.synapseCount + cortex.l5.synapseCount + cortex.l6.synapseCount
            + basalGanglia.d1.synapseCount + basalGanglia.d2.synapseCount + basalGanglia.critic.synapseCount
            + cerebellum.granule.synapseCount + cerebellum.purkinje.synapseCount
            + hippocampus.dentateGyrus.synapseCount + thalamus.relay.synapseCount
    }

    // MARK: Arousal

    func wake() { brainstem.transition(to: .attentive) }
    func sleep() { brainstem.transition(to: .asleep) }
    func setSpeaking(_ speaking: Bool) { brainstem.transition(to: speaking ? .speaking : .attentive) }

    // MARK: Decision

    func process(_ input: BrainInput) -> BrainDecision {
        decisionsMade += 1
        let code = encoder.encode(input.text)
        lastCode = code

        // Limbic appraisal → phasic neuromodulation.
        let appraisal = amygdala.appraise(input.text)
        let cortical = cortex.perceive(code, modulators: brainstem.modulators)
        brainstem.respond(to: appraisal, novelty: cortical.novelty)
        let mods = brainstem.modulators

        // Hypothalamic budget.
        let budget = hypothalamus.budget(for: input.body)

        // Hippocampal recall becomes extra memory channels for the thalamus.
        var channels = input.channels
        for (episode, score) in hippocampus.recall(code, k: 4) where score > 0.15 {
            channels.append(ContextChannel(id: "mem-" + episode.id, kind: .memory, text: episode.text,
                                           salience: episode.importance, recency: 0.3, encoder: encoder))
        }

        // Thalamic gating under the token budget, biased by cortical L6.
        let gated = thalamus.gate(channels: channels, cue: code, corticalFeedback: cortical.thalamicFeedback,
                                  tokenBudget: input.tokenBudget, modulators: mods)

        // Basal ganglia action selection.
        let words = TextEncoder.tokens(input.text)
        let complexity = NeuroMath.clamp(Float(words.count) / 40 + (input.text.contains("?") ? 0.1 : 0)
                                         + (words.count > 25 ? 0.3 : 0), 0, 1)
        let questionness: Float = Self.looksLikeQuestion(input.text, language: input.language) ? 1 : 0
        let sortedIntents = cortical.intentScores.values.sorted(by: >)
        let ambiguity: Float = input.grammarConfidence > 0.3 && input.grammarConfidence < 0.6
            ? 0.6 : (sortedIntents.count > 1 && sortedIntents[0] - sortedIntents[1] < 0.02 && sortedIntents[0] > 0.6 ? 0.3 : 0)
        let features = BasalGanglia.features(grammarConfidence: input.grammarConfidence, complexity: complexity,
                                             questionness: questionness, novelty: cortical.novelty,
                                             deepThinkAvailable: input.deepThinkAvailable && budget.allowDeepThink,
                                             deepThinkRequested: input.deepThinkRequested, isVoice: input.isVoice,
                                             ambiguity: ambiguity, intents: cortical.intentScores)
        let (action, probs) = basalGanglia.select(features: features, modulators: mods,
                                                  allowDeepThink: input.deepThinkAvailable && budget.allowDeepThink,
                                                  rng: &rng)

        // Cerebellar fine control.
        let mossy = Cerebellum.mossyFibres(intents: cortical.intentScores, action: action, textLength: input.text.count,
                                           isVoice: input.isVoice, language: input.language,
                                           toolCount: action == .toolUse ? 2 : (action == .fastCommand ? 1 : 0),
                                           body: input.body, salience: appraisal.salience)
        lastMossy = mossy
        var control = cerebellum.predict(mossy: mossy, modulators: mods, budget: budget)
        if appraisal.urgency > 0.5 { control.verbosity = min(control.verbosity, 0.35) }

        // Supervised cortical learning from the grammar label (self-supervision):
        // the cortex learns to recognise paraphrases the grammar will miss.
        if let label = input.grammarIntent, input.grammarConfidence >= 0.75 {
            cortex.teachIntent(label, modulators: mods, strength: 0.6)
        }

        var active = cortical.activeNeurons
        active.append(thalamus.relayIDs[0])
        active.append(basalGanglia.d1.ids[action.index])
        active.append(contentsOf: cerebellum.granule.activeIndices(level: 0).prefix(48).map { cerebellum.granule.ids[$0] })
        active.append(contentsOf: cerebellum.dcnIDs)

        let decision = BrainDecision(action: action, actionProbabilities: probs, gatedChannels: gated,
                                     intentScores: cortical.intentScores, topIntent: cortical.topIntent,
                                     cerebellar: control, salience: appraisal.salience, urgency: appraisal.urgency,
                                     arousal: brainstem.arousal, budget: budget, novelty: cortical.novelty,
                                     activeNeurons: active)
        lastDecision = decision
        return decision
    }

    static func looksLikeQuestion(_ text: String, language: DetectedLanguage) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasSuffix("?") { return true }
        if language == .korean {
            return ["까", "니", "나요", "가요", "죠", "뭐", "왜", "어떻게", "언제", "어디", "누구", "무엇", "알려"].contains { t.contains($0) }
        }
        let starters = ["what", "why", "how", "when", "where", "who", "which", "is ", "are ", "can ", "could ", "would ", "do ", "does ", "did ", "should "]
        return starters.contains { t.hasPrefix($0) }
    }

    // MARK: Learning from outcomes

    /// Reward signal derived from the control objective.
    static func reward(for outcome: BrainOutcome) -> Float {
        var r: Float = outcome.success ? 0.6 : -0.6
        switch outcome.feedback {
        case .positive: r += 0.4
        case .negative: r -= 0.5
        case .interrupted: r -= 0.25
        case .correction: r -= 0.35
        case .requestedMoreDetail, .requestedBrevity: r -= 0.1
        case .neutral: break
        }
        r -= 0.15 * Float(min(outcome.controlViolations, 4))
        return NeuroMath.clamp(r, -1, 1)
    }

    @discardableResult
    func feedback(_ outcome: BrainOutcome) -> Float {
        guard let decision = lastDecision else { return 0 }
        let reward = Self.reward(for: outcome)

        // Control objective: first-attempt success without violations.
        let controlled: Float = (outcome.success && outcome.controlViolations == 0) ? 1 : 0
        controlScore = controlScore * 0.95 + controlled * 0.05

        // Dopamine: basal ganglia RPE.
        let rpe = basalGanglia.learn(reward: reward, modulators: brainstem.modulators)
        brainstem.releaseDopamine(rpe)
        let mods = brainstem.modulators

        // Thalamus + cortical feedback learn which context was worth admitting.
        thalamus.reinforce(admitted: decision.gatedChannels.map { $0.channel.id }, reward: reward, modulators: mods)
        cortex.teachFeedback(useful: Set(decision.gatedChannels.map { $0.channel.kind }), reward: reward, modulators: mods)
        if let intent = outcome.resolvedIntent {
            cortex.teachIntent(intent, modulators: mods, strength: 1)
        }

        // Cerebellum: climbing-fibre errors per microzone.
        var targets: [Microzone: Float] = [.latency: cerebellum.latencyTarget(seconds: outcome.actualSeconds)]
        let v = cerebellum.currentOutput(.verbosity)
        switch outcome.feedback {
        case .interrupted, .requestedBrevity: targets[.verbosity] = v - 0.3
        case .requestedMoreDetail: targets[.verbosity] = v + 0.3
        default: break
        }
        if outcome.controlViolations > 0 {
            targets[.temperature] = cerebellum.currentOutput(.temperature) - 0.2
        }
        cerebellum.learn(targets: targets, modulators: mods)

        brainstem.relax()
        return reward
    }

    /// Explicit speech-rate adjustment requested by the user ("speak faster").
    func adjustSpeechRate(faster: Bool) {
        guard !lastMossy.isEmpty else { return }
        let current = cerebellum.currentOutput(.speechRate)
        cerebellum.learn(targets: [.speechRate: current + (faster ? 0.4 : -0.4)], modulators: brainstem.modulators)
    }

    // MARK: Memory

    @discardableResult
    func remember(_ text: String, kind: String, importance: Float) -> Episode {
        hippocampus.encode(text: text, kind: kind, importance: importance, code: encoder.encode(text))
    }

    func recall(_ cue: String, k: Int = 5) -> [(Episode, Float)] {
        hippocampus.recall(encoder.encode(cue), k: k)
    }

    /// Offline replay (idle / charging): reactivate important episodes so the
    /// cortex consolidates them and procedural lattice synapses along the
    /// replayed pathways are potentiated.
    func consolidate(replays: Int = 16) -> Int {
        let mods = brainstem.modulators
        var potentiated = 0
        for episode in hippocampus.replayCandidates(replays) {
            let state = cortex.perceive(encoder.encode(episode.text), modulators: mods)
            for id in state.activeNeurons.prefix(8) {
                for s in connectome.synapses(of: id, limit: 16) {
                    connectome.potentiate(s, by: 0.001 * episode.importance)
                    potentiated += 1
                }
            }
        }
        return potentiated
    }

    // MARK: Persistence

    func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var w = BinaryWriter()
        w.write(UInt32(0x4A42_524E)) // "JBRN"
        w.write(Self.formatVersion)
        w.write(controlScore)
        w.write(UInt64(decisionsMade))
        cortex.archive(into: &w)
        basalGanglia.archive(into: &w)
        cerebellum.archive(into: &w)
        hippocampus.archive(into: &w)
        let relayWeights = thalamus.relay.branches[0].synapses.map { Float($0.transmitter.rawValue) * $0.weight }
        w.write(relayWeights)
        w.write(thalamus.relay.bias)
        try w.data.write(to: directory.appendingPathComponent("brain.bin"), options: .atomic)
        try connectome.plasticity.serialized().write(to: directory.appendingPathComponent("plasticity.bin"), options: .atomic)
        try hippocampus.exportEpisodes().write(to: directory.appendingPathComponent("episodes.json"), options: .atomic)
    }

    func load(from directory: URL) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("brain.bin"))
        var r = BinaryReader(data)
        guard try r.read(UInt32.self) == 0x4A42_524E else { throw BinaryArchiveError.badMagic }
        guard try r.read(UInt32.self) == Self.formatVersion else { throw BinaryArchiveError.versionMismatch }
        controlScore = try r.readFloat()
        decisionsMade = Int(try r.read(UInt64.self))
        try cortex.restore(from: &r)
        try basalGanglia.restore(from: &r)
        try cerebellum.restore(from: &r)
        try hippocampus.restore(from: &r)
        let relayWeights = try r.readFloats()
        let relayBias = try r.readFloat()
        if relayWeights.count == thalamus.relay.branches[0].synapses.count {
            for (i, w) in relayWeights.enumerated() {
                thalamus.relay.branches[0].synapses[i].weight = abs(w)
                thalamus.relay.branches[0].synapses[i].transmitter = w >= 0 ? .glutamate : .gaba
            }
            thalamus.relay.bias = relayBias
        }
        let plasticityURL = directory.appendingPathComponent("plasticity.bin")
        if let p = try? Data(contentsOf: plasticityURL), let store = try? PlasticityStore.deserialize(p) {
            connectome.plasticity.replace(with: store)
        }
        if let e = try? Data(contentsOf: directory.appendingPathComponent("episodes.json")) {
            try hippocampus.importEpisodes(e)
        }
    }
}

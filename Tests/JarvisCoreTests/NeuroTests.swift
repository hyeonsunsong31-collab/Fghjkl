import XCTest
@testable import JarvisCore

final class SynapticPerceptronTests: XCTestCase {
    func testClassicModeEqualsPerceptron() {
        let w: [Float] = [0.7, -1.2, 0.4]
        let b: Float = 0.1
        let p = SynapticPerceptron.classic(id: 1, weights: w, bias: b)
        let x: [Float] = [1, 0.5, 0.25]
        let z: Double = 0.7 * 1.0 - 1.2 * 0.5 + 0.4 * 0.25 + 0.1
        let expected: Double = 1.0 / (1.0 + exp(-z))
        // Repeated calls stay identical: no STP, no leak in classic mode.
        for _ in 0..<5 {
            XCTAssertEqual(p.forward(x), Float(expected), accuracy: 1e-5)
        }
    }

    func testShortTermDepressionWeakensRepeatedTransmission() {
        var syn = Synapse(inputIndex: 0, weight: 1, baselineRelease: 0.6, tauFacilitation: 2, tauDepression: 50)
        let first = syn.transmit(1)
        var last = first
        for _ in 0..<10 { last = syn.transmit(1) }
        XCTAssertGreaterThan(first, 0)
        XCTAssertLessThan(last, first * 0.6, "resources should deplete under sustained firing")
        // Rest recovers.
        for _ in 0..<300 { _ = syn.transmit(0) }
        XCTAssertEqual(syn.transmit(1), first, accuracy: 0.05)
    }

    func testFacilitationStrengthensLowReleaseSynapse() {
        var syn = Synapse(inputIndex: 0, weight: 1, baselineRelease: 0.1, tauFacilitation: 40, tauDepression: 2)
        let first = syn.transmit(1)
        let second = syn.transmit(1)
        let third = syn.transmit(1)
        XCTAssertGreaterThan(second, first)
        XCTAssertGreaterThan(third, second)
    }

    func testDendriticBranchesComputeXOR() {
        func syn(_ i: Int, _ w: Float, _ t: Transmitter) -> Synapse {
            Synapse(inputIndex: i, weight: w, transmitter: t, baselineRelease: 1, tauFacilitation: 1, tauDepression: 1)
        }
        // Branch A fires for x1 ∧ ¬x2, branch B for x2 ∧ ¬x1.
        let a = DendriticBranch(synapses: [syn(0, 1, .glutamate), syn(1, 2, .gaba)], gain: 1, threshold: 0.5, slope: 20)
        let b = DendriticBranch(synapses: [syn(1, 1, .glutamate), syn(0, 2, .gaba)], gain: 1, threshold: 0.5, slope: 20)
        let neuron = SynapticPerceptron(id: 7, branches: [a, b], bias: 0, threshold: 0.5, activation: .spiking)
        func run(_ x1: Float, _ x2: Float) -> Float {
            neuron.resetState()
            return neuron.forward([x1, x2])
        }
        XCTAssertEqual(run(0, 0), 0)
        XCTAssertEqual(run(1, 0), 1)
        XCTAssertEqual(run(0, 1), 1)
        XCTAssertEqual(run(1, 1), 0)
    }

    func testSynapticDelayShiftsResponse() {
        let s = Synapse(inputIndex: 0, weight: 5, baselineRelease: 1, tauFacilitation: 1, tauDepression: 1, delay: 2)
        let n = SynapticPerceptron(id: 3, branches: [DendriticBranch(synapses: [s])], bias: 0, threshold: 1, activation: .spiking)
        XCTAssertEqual(n.forward([1]), 0)
        XCTAssertEqual(n.forward([0]), 0)
        XCTAssertEqual(n.forward([0]), 1, "input arrives after a two-tick delay")
    }

    func testThreeFactorLearningLearnsOR() {
        let n = SynapticPerceptron.classic(id: 9, weights: [0.05, 0.05], bias: -1)
        n.learningRate = 0.8
        let data: [([Float], Float)] = [([0, 0], 0), ([1, 0], 1), ([0, 1], 1), ([1, 1], 1)]
        for _ in 0..<400 {
            for (x, t) in data {
                n.resetState()
                _ = n.train(x, target: t)
            }
        }
        for (x, t) in data {
            n.resetState()
            let y = n.forward(x)
            XCTAssertEqual(y > 0.5 ? 1 : 0, t, "OR(\(x)) = \(y)")
        }
    }
}

final class LatticeTests: XCTestCase {
    func testTotalNeuronCountExceeds200Billion() {
        XCTAssertEqual(Lattice3D.totalNeurons, 206_158_430_208)
        XCTAssertGreaterThan(Lattice3D.totalNeurons, 200_000_000_000)
    }

    func testIndexRoundTrip() {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<10_000 {
            let id = rng.next() % Lattice3D.totalNeurons
            let c = Lattice3D.coordinate(id)
            XCTAssertTrue(Lattice3D.isValid(c))
            XCTAssertEqual(Lattice3D.id(c), id)
        }
        XCTAssertEqual(Lattice3D.id(LatticeCoordinate(8191, 6143, 4095)), Lattice3D.totalNeurons - 1)
    }

    func testCensusIsExactAndProportional() {
        let census = Lattice3D.census()
        XCTAssertEqual(census.values.reduce(0, +), Lattice3D.totalNeurons)
        for region in BrainRegion.allCases {
            XCTAssertGreaterThan(census[region] ?? 0, 0, "\(region) has no neurons")
        }
        let systems = Lattice3D.systemCensus()
        XCTAssertEqual(systems[.cerebellum], 161_061_273_600)
        XCTAssertEqual(systems[.cortex], 38_654_705_664)
        let coreSystems: [BrainSystem] = [.thalamus, .basalGanglia, .hippocampus, .amygdala, .hypothalamus, .brainstem]
        var core: UInt64 = 0
        for s in coreSystems { core += systems[s] ?? 0 }
        XCTAssertEqual(core, 6_442_450_944)
    }

    func testCensusMatchesMonteCarlo() {
        let census = Lattice3D.census()
        var rng = SplitMix64(seed: 7)
        var counts: [BrainRegion: Int] = [:]
        let n = 200_000
        for _ in 0..<n {
            counts[Lattice3D.region(of: rng.next() % Lattice3D.totalNeurons), default: 0] += 1
        }
        for region in [BrainRegion.cerebellumGranule, .cortexL23, .cortexL5] {
            let expected = Double(census[region]!) / Double(Lattice3D.totalNeurons)
            let observed = Double(counts[region] ?? 0) / Double(n)
            XCTAssertEqual(observed, expected, accuracy: 0.01, "\(region)")
        }
    }

    func testSamplingLandsInsideEveryRegion() {
        var rng = SplitMix64(seed: 99)
        for region in BrainRegion.allCases {
            for _ in 0..<500 {
                let c = Lattice3D.sample(in: region, u: rng.nextUnit(), v: rng.nextUnit(), w: rng.nextUnit(), hash: rng.next())
                XCTAssertTrue(Lattice3D.isValid(c))
                XCTAssertEqual(Lattice3D.region(at: c), region, "sample in \(region) landed at \(c)")
            }
        }
    }
}

final class ConnectomeTests: XCTestCase {
    let connectome = ProceduralConnectome(seed: 1234)

    func testDeterministic() {
        let id: NeuronID = 123_456_789_012
        XCTAssertEqual(connectome.synapse(of: id, index: 17), connectome.synapse(of: id, index: 17))
        XCTAssertEqual(connectome.fanOut(of: id), connectome.fanOut(of: id))
    }

    func testTargetsAreValidAndRegionsFollowAnatomy() {
        func firstNeuron(in region: BrainRegion) -> NeuronID {
            Lattice3D.id(Lattice3D.sample(in: region, u: 0.4, v: 0.5, w: 0.6, hash: 5))
        }
        // Pons → cerebellar granule cells (mossy fibres).
        let pons = firstNeuron(in: .pons)
        for s in connectome.synapses(of: pons, limit: 200) {
            XCTAssertLessThan(s.target, Lattice3D.totalNeurons)
            XCTAssertEqual(Lattice3D.region(of: s.target), .cerebellumGranule)
            XCTAssertGreaterThan(s.weight, 0)
        }
        // Inferior olive → Purkinje (climbing fibres).
        for s in connectome.synapses(of: firstNeuron(in: .inferiorOlive), limit: 32) {
            XCTAssertEqual(Lattice3D.region(of: s.target), .cerebellumPurkinje)
        }
        // Purkinje cells are inhibitory and mostly target the deep nuclei.
        let purkinje = connectome.synapses(of: firstNeuron(in: .cerebellumPurkinje), limit: 64)
        XCTAssertTrue(purkinje.allSatisfy { $0.weight < 0 })
        let toDCN = purkinje.filter { Lattice3D.region(of: $0.target) == .deepCerebellarNuclei }.count
        XCTAssertGreaterThan(toDCN, 40)
        // Granule parallel fibres reach the Purkinje row of the same folium.
        let granule = firstNeuron(in: .cerebellumGranule)
        let gy = Lattice3D.coordinate(granule).y / Lattice3D.foliumPeriod
        let pf = connectome.synapses(of: granule, limit: 256).filter { Lattice3D.region(of: $0.target) == .cerebellumPurkinje }
        XCTAssertGreaterThan(pf.count, 100)
        XCTAssertTrue(pf.allSatisfy { Lattice3D.coordinate($0.target).y / Lattice3D.foliumPeriod == gy })
        // TRN inhibits thalamic relay nuclei only.
        for s in connectome.synapses(of: firstNeuron(in: .thalamicReticular), limit: 100) {
            XCTAssertEqual(Lattice3D.region(of: s.target).system, .thalamus)
            XCTAssertNotEqual(Lattice3D.region(of: s.target), .thalamicReticular)
            XCTAssertLessThan(s.weight, 0)
        }
        // Thalamic relays project mostly into cortical layer 4.
        let relay = connectome.synapses(of: firstNeuron(in: .thalamusSensoryRelay), limit: 300)
        let toL4 = relay.filter { Lattice3D.region(of: $0.target) == .cortexL4 }.count
        XCTAssertGreaterThan(toL4, 150)
    }

    func testEveryRegionHasOutgoingConnections() {
        for region in BrainRegion.allCases {
            let id = Lattice3D.id(Lattice3D.sample(in: region, u: 0.5, v: 0.5, w: 0.5, hash: 11))
            let syn = connectome.synapses(of: id, limit: 50)
            XCTAssertFalse(syn.isEmpty)
            XCTAssertTrue(syn.allSatisfy { $0.target != id && $0.target < Lattice3D.totalNeurons }, "\(region)")
        }
    }

    func testLogicalSynapseCountIsAstronomical() {
        let n = ProceduralConnectome.logicalSynapseCount()
        XCTAssertGreaterThan(n, 50_000_000_000_000)
    }

    func testLearnedDeltaIsApplied() {
        let c = ProceduralConnectome(seed: 5)
        let s = c.synapse(of: 1_000_000, index: 3)
        c.potentiate(s, by: 0.25)
        XCTAssertEqual(c.synapse(of: 1_000_000, index: 3).weight, s.weight + 0.25, accuracy: 1e-6)
    }
}

final class PlasticityStoreTests: XCTestCase {
    func testAddGrowSerializeDecay() throws {
        let store = PlasticityStore(capacity: 16)
        for k in 0..<5000 { store.add(Float(k % 7) * 0.01 + 0.001, for: UInt64(k) &* 0x9E3779B97F4A7C15) }
        XCTAssertEqual(store.count, 5000)
        XCTAssertEqual(store.delta(for: UInt64(10) &* 0x9E3779B97F4A7C15), 0.031, accuracy: 1e-6)
        let restored = try PlasticityStore.deserialize(store.serialized())
        XCTAssertEqual(restored.count, 5000)
        XCTAssertEqual(restored.delta(for: UInt64(10) &* 0x9E3779B97F4A7C15), 0.031, accuracy: 1e-6)
        store.decay(factor: 0.5, prune: 0.01)
        XCTAssertLessThan(store.count, 5000)
        XCTAssertEqual(store.delta(for: 0), 0) // key 0 normalised, never inserted
    }
}

final class RegionTests: XCTestCase {
    func testThalamusRespectsBudgetAndPrefersRelevantContext() {
        let thalamus = Thalamus(seed: 1)
        let enc = TextEncoder()
        let cue = enc.encode("make the red cube bigger")
        let channels = [
            ContextChannel(id: "scene", kind: .scene, text: "Scene: red cube at origin, blue sphere left", salience: 0.6, recency: 0.9),
            ContextChannel(id: "weather", kind: .memory, text: "Yesterday the user asked about the weather in Seoul", salience: 0.3, recency: 0.2),
            ContextChannel(id: "long", kind: .memory, text: String(repeating: "irrelevant filler text ", count: 200), salience: 0.2, recency: 0.1),
        ]
        let gated = thalamus.gate(channels: channels, cue: cue, corticalFeedback: [:], tokenBudget: 120, modulators: NeuromodulatorState())
        let sceneGate = gated.first { $0.channel.id == "scene" }?.gate ?? 0
        let weatherGate = gated.first { $0.channel.id == "weather" }?.gate ?? 0
        XCTAssertGreaterThan(sceneGate, weatherGate)
        XCTAssertLessThanOrEqual(gated.reduce(0) { $0 + $1.channel.tokenCost }, 120)
        XCTAssertFalse(gated.contains { $0.channel.id == "long" })
    }

    func testBasalGangliaPriorsAndLearning() {
        let bg = BasalGanglia(seed: 3)
        var rng = SplitMix64(seed: 1)
        let mods = NeuromodulatorState(dopamine: 0, acetylcholine: 0.5, noradrenaline: 0, serotonin: 0.5)
        func features(_ g: Float, music: Float = 0) -> [Float] {
            BasalGanglia.features(grammarConfidence: g, complexity: 0.2, questionness: 0, novelty: 0.5,
                                  deepThinkAvailable: true, deepThinkRequested: false, isVoice: true, ambiguity: 0,
                                  intents: [.music: music])
        }
        XCTAssertEqual(bg.select(features: features(0.95), modulators: mods, allowDeepThink: true, rng: &rng).0, .fastCommand)
        XCTAssertEqual(bg.select(features: features(0), modulators: mods, allowDeepThink: true, rng: &rng).0, .conversational)

        // Reward toolUse whenever the music intent is strong; punish conversational.
        let musicFeatures = features(0, music: 0.9)
        let before = bg.select(features: musicFeatures, modulators: mods, allowDeepThink: true, rng: &rng).1[.toolUse] ?? 0
        for _ in 0..<60 {
            let (a, _) = bg.select(features: musicFeatures, modulators: mods, allowDeepThink: true, rng: &rng)
            bg.learn(reward: a == .toolUse ? 1 : -1, modulators: mods)
        }
        let (after, probs) = bg.select(features: musicFeatures, modulators: mods, allowDeepThink: true, rng: &rng)
        XCTAssertEqual(after, .toolUse)
        XCTAssertGreaterThan(probs[.toolUse] ?? 0, before)
    }

    func testCerebellumLearnsTaskDurations() {
        let cb = Cerebellum(seed: 8)
        let budget = Hypothalamus().budget(for: BodyState())
        let mods = NeuromodulatorState()
        func mossy(_ intent: IntentClass) -> [Float] {
            Cerebellum.mossyFibres(intents: [intent: 1], action: .toolUse, textLength: 30, isVoice: true,
                                   language: .english, toolCount: 2, body: BodyState(), salience: 0.3)
        }
        let slow = mossy(.web), fast = mossy(.systemControl)
        for _ in 0..<40 {
            _ = cb.predict(mossy: slow, modulators: mods, budget: budget)
            cb.learn(targets: [.latency: cb.latencyTarget(seconds: 12)], modulators: mods)
            _ = cb.predict(mossy: fast, modulators: mods, budget: budget)
            cb.learn(targets: [.latency: cb.latencyTarget(seconds: 0.5)], modulators: mods)
        }
        let pSlow = cb.predict(mossy: slow, modulators: mods, budget: budget).predictedSeconds
        let pFast = cb.predict(mossy: fast, modulators: mods, budget: budget).predictedSeconds
        XCTAssertEqual(pSlow, 12, accuracy: 4)
        XCTAssertEqual(pFast, 0.5, accuracy: 0.3)
    }

    func testCortexLearnsIntentsAndGeneralises() {
        let cortex = Cortex(seed: 2)
        let enc = TextEncoder()
        let mods = NeuromodulatorState()
        let examples: [(String, IntentClass)] = [
            ("make a red cube", .command3D), ("create a sphere", .command3D), ("큐브 만들어줘", .command3D),
            ("add a blue cylinder", .command3D), ("clone the cube", .command3D),
            ("play some music", .music), ("play bohemian rhapsody", .music), ("노래 틀어줘", .music), ("음악 재생해줘", .music),
            ("open kakaotalk", .appLaunch), ("open safari", .appLaunch), ("카카오톡 열어줘", .appLaunch),
            ("what is the capital of france", .question), ("why is the sky blue", .question), ("하늘은 왜 파래", .question),
        ]
        for _ in 0..<25 {
            for (text, label) in examples {
                _ = cortex.perceive(enc.encode(text), modulators: mods)
                cortex.teachIntent(label, modulators: mods)
            }
        }
        XCTAssertEqual(cortex.perceive(enc.encode("make a green cube"), modulators: mods).topIntent, .command3D)
        XCTAssertEqual(cortex.perceive(enc.encode("play some jazz music"), modulators: mods).topIntent, .music)
        XCTAssertEqual(cortex.perceive(enc.encode("빨간 큐브 만들어줘"), modulators: mods).topIntent, .command3D)
    }

    func testHippocampusPatternCompletion() {
        let hc = Hippocampus(seed: 4)
        let enc = TextEncoder()
        let facts = ["The user's favourite colour is midnight blue",
                     "The user's dog is called Bori and loves walks",
                     "The quarterly report is due on Friday afternoon",
                     "사용자는 매일 아침 7시에 일어납니다"]
        for f in facts { hc.encode(text: f, kind: "fact", importance: 0.7, code: enc.encode(f)) }
        XCTAssertEqual(hc.recall(enc.encode("what is my dog called"), k: 1).first?.0.text, facts[1])
        XCTAssertEqual(hc.recall(enc.encode("favourite colour"), k: 1).first?.0.text, facts[0])
        XCTAssertEqual(hc.recall(enc.encode("몇 시에 일어나"), k: 1).first?.0.text, facts[3])
    }

    func testHypothalamusBudget() {
        let h = Hypothalamus()
        XCTAssertTrue(h.budget(for: BodyState()).allowDeepThink)
        XCTAssertFalse(h.budget(for: BodyState(batteryLevel: 0.05)).allowDeepThink)
        XCTAssertEqual(h.budget(for: BodyState(thermalState: 3)).latticeEventsPerTick, 0)
    }

    func testAmygdalaAppraisal() {
        let a = Amygdala()
        XCTAssertGreaterThan(a.appraise("긴급! 지금 당장 도와줘").urgency, 0.5)
        XCTAssertGreaterThan(a.appraise("Thank you, that was brilliant").valence, 0)
        XCTAssertEqual(a.appraise("I know it is now ok").valence, 0, "'no' must not match inside 'know'/'now'")
    }
}

final class BrainTests: XCTestCase {
    func input(_ text: String, g: Float = 0, intent: IntentClass? = nil) -> BrainInput {
        BrainInput(text: text, language: LanguageDetector.detect(text).language, isVoice: false,
                   grammarConfidence: g, grammarIntent: intent,
                   channels: [ContextChannel(id: "c1", kind: .conversation, text: "User: hello Jarvis", recency: 0.9)],
                   body: BodyState(), deepThinkAvailable: false)
    }

    func testEndToEndDecisionAndLearning() throws {
        let brain = Brain(seed: 77)
        XCTAssertGreaterThan(brain.coreNeuronCount, 10_000)
        let d = brain.process(input("open the 3D project space", g: 0.95, intent: .command3D))
        XCTAssertEqual(d.action, .fastCommand)
        XCTAssertGreaterThan(d.cerebellar.predictedSeconds, 0)
        XCTAssertFalse(d.activeNeurons.isEmpty)
        XCTAssertTrue(d.activeNeurons.allSatisfy { $0 < Lattice3D.totalNeurons })
        let r = brain.feedback(BrainOutcome(success: true, actualSeconds: 0.2, feedback: .positive, controlViolations: 0,
                                            resolvedIntent: .command3D, outputCharacters: 30))
        XCTAssertGreaterThan(r, 0)

        let d2 = brain.process(input("Tell me a little about the history of tea in Britain"))
        XCTAssertEqual(d2.action, .conversational)
    }

    func testSaveAndLoadRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("brain-\(UUID().uuidString)")
        let a = Brain(seed: 5)
        for _ in 0..<5 {
            _ = a.process(input("play some music please", g: 0.9, intent: .music))
            a.feedback(BrainOutcome(success: true, actualSeconds: 1, feedback: .neutral, controlViolations: 0, resolvedIntent: .music, outputCharacters: 20))
        }
        a.remember("The user prefers jazz in the evening", kind: "preference", importance: 0.8)
        try a.save(to: dir)

        let b = Brain(seed: 5)
        try b.load(from: dir)
        XCTAssertEqual(b.controlScore, a.controlScore, accuracy: 1e-6)
        XCTAssertEqual(b.recall("jazz", k: 1).first?.0.text, "The user prefers jazz in the evening")
        XCTAssertEqual(a.cortex.l5.signedRow(IntentClass.music.index), b.cortex.l5.signedRow(IntentClass.music.index))
    }

    func testConsolidationPotentiatesLatticeSynapses() {
        let brain = Brain(seed: 6)
        brain.remember("Remember the meeting with the design team on Monday", kind: "fact", importance: 0.9)
        let n = brain.consolidate(replays: 1)
        XCTAssertGreaterThan(n, 0)
        XCTAssertGreaterThan(brain.connectome.plasticity.count, 0)
    }
}

final class LatticeSimulatorTests: XCTestCase {
    func testEventDrivenActivityRespectsBudget() {
        let sim = LatticeSimulator(connectome: ProceduralConnectome(seed: 9))
        let seeds = RegionAllocator.ids(in: .thalamusSensoryRelay, count: 64, seed: 1)
            + RegionAllocator.ids(in: .pons, count: 64, seed: 2)
        sim.threshold = 0.01
        sim.inject(seeds)
        let t1 = sim.step(eventBudget: 10_000)
        XCTAssertLessThanOrEqual(t1.synapticEvents, 10_000)
        XCTAssertGreaterThan(t1.synapticEvents, 0)
        XCTAssertGreaterThan(t1.spikes, 0)
        XCTAssertNotNil(t1.activity[.cortex] ?? t1.activity[.cerebellum])
    }
}

final class OutputControllerTests: XCTestCase {
    let oc = OutputController()

    func testKoreanCasualRegisterIsFlagged() {
        let v = oc.verify("알았어. 지금 큐브 만들어줘.", expected: .korean, toolsSucceeded: true, characterLimit: 500, forSpeech: true)
        XCTAssertTrue(v.contains { if case .informalRegister = $0 { return true } else { return false } })
        let ok = oc.verify("알겠습니다. 빨간 큐브를 생성했습니다.", expected: .korean, toolsSucceeded: true, characterLimit: 500, forSpeech: true)
        XCTAssertTrue(ok.isEmpty, "\(ok)")
    }

    func testEnglishAddressRepair() {
        let v = oc.verify("Certainly. The cube is ready.", expected: .english, toolsSucceeded: true, characterLimit: 500, forSpeech: true)
        XCTAssertEqual(v, [.missingAddress])
        XCTAssertEqual(oc.repair("Certainly. The cube is ready.", violations: v, language: .english), "Certainly. The cube is ready, sir.")
    }

    func testFalseCompletionClaimAndLanguageMismatch() {
        let v = oc.verify("I have opened KakaoTalk for you, sir.", expected: .english, toolsSucceeded: false, characterLimit: 500, forSpeech: false)
        XCTAssertTrue(v.contains(.falseCompletionClaim("i have opened")))
        let m = oc.verify("Of course, sir.", expected: .korean, toolsSucceeded: true, characterLimit: 500, forSpeech: false)
        XCTAssertTrue(m.contains(.languageMismatch(expected: .korean, found: .english)))
    }
}

import Foundation

/// **Thalamus** — the relay and gatekeeper.
///
/// Every candidate context item (conversation turns, episodic memories, 3D scene
/// state, device state, tool results…) is a *channel*. A relay synaptic
/// perceptron scores each channel from its features; the thalamic reticular
/// nucleus (TRN) then imposes competitive inhibition under the language model's
/// token budget, sharpened by acetylcholine and biased by cortical layer-6
/// feedback. Only the winners reach the "cortex" of the language model — this is
/// how the neural core controls *what the AI sees* before it answers.
final class Thalamus {
    static let featureCount = 6 + ChannelKind.allCases.count

    let relay: SynapticPerceptron
    let relayIDs: [NeuronID]
    let trnIDs: [NeuronID]
    private var lastFeatures: [String: [Float]] = [:]

    init(seed: UInt64) {
        relayIDs = RegionAllocator.ids(in: .thalamusPulvinar, count: ChannelKind.allCases.count, seed: seed)
        trnIDs = RegionAllocator.ids(in: .thalamicReticular, count: ChannelKind.allCases.count, seed: seed ^ 0x77)
        // Prior weights: similarity to the cue, salience, recency, cortical feedback,
        // pinned, (negative) cost, then a per-kind bias.
        var weights: [Float] = [2.4, 1.2, 1.0, 1.0, 3.0, -1.2]
        for kind in ChannelKind.allCases {
            switch kind {
            case .conversation: weights.append(0.6)
            case .task, .toolResult: weights.append(0.5)
            case .scene, .device: weights.append(0.1)
            case .memory: weights.append(0.0)
            case .profile: weights.append(0.2)
            case .screen: weights.append(-0.1)
            }
        }
        relay = SynapticPerceptron.classic(id: relayIDs[0], weights: weights, bias: -2.0, activation: .sigmoid)
        relay.learningRate = 0.08
    }

    func features(for channel: ContextChannel, cue: SparseCode, feedback: [ChannelKind: Float], budget: Int) -> [Float] {
        var f: [Float] = [
            channel.code.similarity(cue),
            channel.salience,
            channel.recency,
            feedback[channel.kind] ?? 0.5,
            channel.pinned ? 1 : 0,
            min(1, Float(channel.tokenCost) / Float(max(1, budget)))
        ]
        for kind in ChannelKind.allCases { f.append(kind == channel.kind ? 1 : 0) }
        return f
    }

    /// Relay + TRN competition. Returns the channels admitted to the language model.
    func gate(channels: [ContextChannel],
              cue: SparseCode,
              corticalFeedback: [ChannelKind: Float],
              tokenBudget: Int,
              modulators: NeuromodulatorState) -> [GatedChannel] {
        guard !channels.isEmpty else { return [] }
        var scored: [(ContextChannel, Float)] = []
        lastFeatures.removeAll(keepingCapacity: true)
        for ch in channels {
            let f = features(for: ch, cue: cue, feedback: corticalFeedback, budget: tokenBudget)
            lastFeatures[ch.id] = f
            let r = relay.forward(f, modulators: modulators)
            // Acetylcholine sharpens the contrast between strong and weak channels.
            let sharpened = Float(pow(Double(max(r, 1e-4)), Double(1 + 2 * modulators.acetylcholine)))
            scored.append((ch, sharpened))
        }

        var remaining = scored
        var selected: [GatedChannel] = []
        var used = 0
        while !remaining.isEmpty {
            remaining.sort { $0.1 > $1.1 }
            let (best, score) = remaining.removeFirst()
            if score < 0.02 && !best.pinned { break }
            if used + best.tokenCost > tokenBudget { continue }
            selected.append(GatedChannel(channel: best, gate: score))
            used += best.tokenCost
            // TRN lateral inhibition: suppress redundant channels of the same kind
            // and near-duplicates of what was just admitted.
            remaining = remaining.map { item in
                var s = item.1
                if item.0.kind == best.kind { s *= 0.85 }
                if item.0.code.similarity(best.code) > 0.8 { s *= 0.3 }
                return (item.0, s)
            }
        }
        // Present in natural order: pinned/profile first, then by kind priority, then recency.
        return selected.sorted { a, b in
            if a.channel.pinned != b.channel.pinned { return a.channel.pinned }
            if a.channel.kind != b.channel.kind { return a.channel.kind.index < b.channel.kind.index }
            return a.channel.recency < b.channel.recency
        }
    }

    /// Dopamine-gated learning: channels that were admitted on a successful turn
    /// become more likely to be admitted in similar situations.
    func reinforce(admitted: [String], reward: Float, modulators: NeuromodulatorState) {
        for id in admitted {
            guard let f = lastFeatures[id] else { continue }
            let target: Float = reward >= 0 ? 1 : 0
            _ = relay.train(f, target: target, modulators: modulators)
        }
    }
}

import Foundation

/// Activity statistics of one lattice tick.
struct LatticeTickStats: Equatable {
    var spikes: Int
    var synapticEvents: Int
    var activity: [BrainSystem: Int]
    var sample: [NeuronID]
}

/// Event-driven simulator of the **full 206-billion-neuron lattice**.
///
/// Only spiking neurons do work: each spike walks its procedural fan-out
/// (generated on the fly), depositing current into target neurons whose
/// membrane potentials live in a sparse map. Activity is bounded by the
/// hypothalamic event budget, so the whole brain can "idle", replay and
/// visualise on a phone while honouring battery and thermal limits.
final class LatticeSimulator {
    let connectome: ProceduralConnectome
    var threshold: Float = 0.06
    var leak: Float = 0.6
    private(set) var potentials: [NeuronID: Float] = [:]
    private(set) var active: [NeuronID] = []
    private(set) var ticks = 0

    init(connectome: ProceduralConnectome) {
        self.connectome = connectome
    }

    /// Stimulate neurons (e.g. the core neurons that fired for a decision).
    func inject(_ ids: [NeuronID]) {
        active.append(contentsOf: ids)
        if active.count > 100_000 { active.removeFirst(active.count - 100_000) }
    }

    @discardableResult
    func step(eventBudget: Int, synapsesPerSpike: Int = 64) -> LatticeTickStats {
        ticks += 1
        var events = 0
        var next: [NeuronID: Float] = [:]
        next.reserveCapacity(min(eventBudget, 1 << 16))

        // Decay existing potentials.
        for (id, v) in potentials {
            let decayed = v * leak
            if abs(decayed) > threshold * 0.05 { next[id] = decayed }
        }

        let perSpike = max(1, min(synapsesPerSpike, eventBudget / max(1, active.count)))
        outer: for src in active {
            let fan = min(connectome.fanOut(of: src), perSpike)
            for k in 0..<fan {
                if events >= eventBudget { break outer }
                let s = connectome.synapse(of: src, index: k)
                next[s.target, default: 0] += s.weight
                events += 1
            }
        }

        var spikes: [NeuronID] = []
        var activity: [BrainSystem: Int] = [:]
        for (id, v) in next where v >= threshold {
            spikes.append(id)
            next[id] = 0 // reset
            activity[Lattice3D.region(of: id).system, default: 0] += 1
        }
        potentials = next
        // Cap runaway activity (global inhibition).
        if spikes.count > 50_000 {
            spikes.sort()
            spikes = Array(spikes.prefix(50_000))
        }
        active = spikes
        return LatticeTickStats(spikes: spikes.count, synapticEvents: events, activity: activity,
                                sample: Array(spikes.prefix(512)))
    }

    func reset() {
        potentials.removeAll()
        active.removeAll()
    }
}

import Foundation

/// Places the members of a materialised core population at real coordinates
/// inside their region of the 206-billion-neuron lattice. Core neurons therefore
/// share identity (and procedural connectivity) with the full lattice.
enum RegionAllocator {
    static func ids(in region: BrainRegion, count: Int, seed: UInt64) -> [NeuronID] {
        var out: [NeuronID] = []
        out.reserveCapacity(count)
        var used = Set<NeuronID>()
        var i: UInt64 = 0
        while out.count < count {
            let h = NeuroMath.hash(seed, UInt64(region.rawValue), i)
            // Low-discrepancy spread over the region (golden-ratio sequence + jitter).
            let n = Float(out.count) + 0.5
            let u = (n * 0.618034).truncatingRemainder(dividingBy: 1)
            let v = (n * 0.754878).truncatingRemainder(dividingBy: 1)
            let w = (n * 0.569840).truncatingRemainder(dividingBy: 1)
            let c = Lattice3D.sample(in: region, u: u, v: v, w: w, hash: h)
            let id = Lattice3D.id(c)
            if used.insert(id).inserted { out.append(id) }
            i += 1
        }
        return out
    }
}

extension PerceptronPopulation {
    /// Set the signed weight of an existing synapse (row → input column).
    func setSignedWeight(row: Int, input col: Int, value: Float) {
        guard let k = synapseIndex(row: row, input: col) else { return }
        assignSigned(k, value)
    }
}

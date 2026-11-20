import Foundation

/// One synapse of the procedural connectome.
struct ProceduralSynapse: Equatable {
    var source: NeuronID
    var target: NeuronID
    /// Signed effective weight (base + learned Δw).
    var weight: Float
    /// Axonal + synaptic delay in ticks (from 3D distance).
    var delay: UInt8
    /// Stable key used to look up/learn Δw in the `PlasticityStore`.
    var key: UInt64
}

/// How a region projects.
enum ProjectionKind: Equatable {
    /// Gaussian neighbourhood around the source (σ in lattice sites).
    case local(sigma: Int64)
    /// Topographic long-range tract into another region.
    case tract(BrainRegion)
    /// Cerebellar parallel fibre: runs along z inside the same folium to the Purkinje row.
    case parallelFibre
}

struct ProjectionRule: Equatable {
    var kind: ProjectionKind
    /// Fraction of the source's fan-out that uses this rule.
    var fraction: Float
    /// +1 excitatory / −1 inhibitory.
    var sign: Float
}

/// **Procedural connectome** of the 206-billion-neuron 3D mesh.
///
/// Storing ~10¹⁴ synapses is impossible on any phone or tablet, so connectivity
/// is *computed*: the k-th synapse of neuron n is a pure function
/// `f(seed, n, k)` of counter-based hashes (the technique used by GeNN to
/// simulate cortical models far larger than GPU memory). Every neuron therefore
/// has a definite, reproducible set of partners — the whole lattice is one
/// connected 3D network — while memory holds only the learned deltas.
final class ProceduralConnectome {
    let seed: UInt64
    let plasticity: PlasticityStore

    init(seed: UInt64 = 0x4A41_5256_4953_0001, plasticity: PlasticityStore = PlasticityStore()) {
        self.seed = seed
        self.plasticity = plasticity
    }

    // MARK: Anatomy tables

    static func meanFanOut(_ region: BrainRegion) -> Int {
        switch region {
        case .cerebellumGranule: return 256
        case .cerebellumPurkinje: return 64
        case .cerebellumMolecular: return 128
        case .deepCerebellarNuclei: return 512
        case .cortexL1: return 300
        case .cortexL23: return 1200
        case .cortexL4: return 800
        case .cortexL5: return 1000
        case .cortexL6: return 800
        case .thalamusSensoryRelay, .thalamusMotorRelay, .thalamusPulvinar, .thalamusMediodorsal: return 600
        case .thalamicReticular: return 400
        case .striatum: return 500
        case .globusPallidusExternal, .globusPallidusInternal, .subthalamicNucleus: return 400
        case .substantiaNigraCompacta, .ventralTegmentalArea, .locusCoeruleus, .raphe: return 2000
        case .dentateGyrus: return 300
        case .ca3: return 1000
        case .ca1: return 800
        case .amygdala, .hypothalamus, .basalForebrain: return 800
        case .pons: return 600
        case .inferiorOlive: return 32
        case .reticularFormation: return 1500
        }
    }

    static func baseWeight(_ region: BrainRegion) -> Float {
        switch region.system {
        case .cerebellum: return 0.02
        case .cortex: return 0.015
        case .thalamus: return 0.05
        case .basalGanglia: return 0.04
        case .hippocampus: return 0.03
        case .amygdala, .hypothalamus: return 0.04
        case .brainstem: return 0.06
        }
    }

    static func rules(_ region: BrainRegion) -> [ProjectionRule] {
        func r(_ k: ProjectionKind, _ f: Float, _ s: Float = 1) -> ProjectionRule { ProjectionRule(kind: k, fraction: f, sign: s) }
        switch region {
        case .cerebellumGranule: return [r(.parallelFibre, 0.65), r(.tract(.cerebellumMolecular), 0.35)]
        case .cerebellumPurkinje: return [r(.tract(.deepCerebellarNuclei), 0.9, -1), r(.local(sigma: 24), 0.1, -1)]
        case .cerebellumMolecular: return [r(.tract(.cerebellumPurkinje), 1.0, -1)]
        case .deepCerebellarNuclei: return [r(.tract(.thalamusMotorRelay), 0.7), r(.tract(.inferiorOlive), 0.2, -1), r(.local(sigma: 16), 0.1)]
        case .cortexL1: return [r(.tract(.cortexL23), 0.7), r(.tract(.cortexL5), 0.3)]
        case .cortexL23: return [r(.local(sigma: 40), 0.4), r(.local(sigma: 12), 0.1, -1), r(.tract(.cortexL5), 0.3),
                                 r(.tract(.striatum), 0.1), r(.tract(.cortexL23), 0.1)]
        case .cortexL4: return [r(.tract(.cortexL23), 0.8), r(.local(sigma: 20), 0.2)]
        case .cortexL5: return [r(.tract(.pons), 0.25), r(.tract(.striatum), 0.25), r(.tract(.thalamusPulvinar), 0.1),
                                r(.local(sigma: 30), 0.3), r(.tract(.reticularFormation), 0.1)]
        case .cortexL6: return [r(.tract(.thalamusSensoryRelay), 0.1), r(.tract(.thalamusMotorRelay), 0.1),
                                r(.tract(.thalamusMediodorsal), 0.1), r(.tract(.thalamusPulvinar), 0.1),
                                r(.tract(.thalamicReticular), 0.3), r(.tract(.cortexL4), 0.3)]
        case .thalamusSensoryRelay, .thalamusMotorRelay, .thalamusPulvinar, .thalamusMediodorsal:
            return [r(.tract(.cortexL4), 0.7), r(.tract(.thalamicReticular), 0.2), r(.tract(.striatum), 0.1)]
        case .thalamicReticular:
            return [r(.tract(.thalamusSensoryRelay), 0.25, -1), r(.tract(.thalamusMotorRelay), 0.25, -1),
                    r(.tract(.thalamusPulvinar), 0.25, -1), r(.tract(.thalamusMediodorsal), 0.25, -1)]
        case .striatum: return [r(.tract(.globusPallidusInternal), 0.5, -1), r(.tract(.globusPallidusExternal), 0.4, -1), r(.local(sigma: 16), 0.1, -1)]
        case .globusPallidusExternal: return [r(.tract(.subthalamicNucleus), 0.6, -1), r(.tract(.globusPallidusInternal), 0.4, -1)]
        case .globusPallidusInternal: return [r(.tract(.thalamusMotorRelay), 0.8, -1), r(.tract(.thalamusMediodorsal), 0.2, -1)]
        case .subthalamicNucleus: return [r(.tract(.globusPallidusInternal), 0.6), r(.tract(.globusPallidusExternal), 0.4)]
        case .substantiaNigraCompacta: return [r(.tract(.striatum), 1.0)]
        case .dentateGyrus: return [r(.tract(.ca3), 1.0)]
        case .ca3: return [r(.local(sigma: 48), 0.5), r(.tract(.ca1), 0.5)]
        case .ca1: return [r(.tract(.cortexL5), 0.4), r(.tract(.amygdala), 0.2), r(.tract(.cortexL23), 0.4)]
        case .amygdala: return [r(.tract(.hypothalamus), 0.4), r(.tract(.locusCoeruleus), 0.2), r(.tract(.cortexL23), 0.2), r(.tract(.ventralTegmentalArea), 0.2)]
        case .hypothalamus: return [r(.tract(.reticularFormation), 0.5), r(.tract(.amygdala), 0.2), r(.local(sigma: 24), 0.3)]
        case .basalForebrain: return [r(.tract(.cortexL1), 0.6), r(.tract(.ca1), 0.2), r(.tract(.thalamicReticular), 0.2)]
        case .pons: return [r(.tract(.cerebellumGranule), 1.0)]
        case .inferiorOlive: return [r(.tract(.cerebellumPurkinje), 1.0)]
        case .ventralTegmentalArea: return [r(.tract(.striatum), 0.5), r(.tract(.cortexL5), 0.3), r(.tract(.amygdala), 0.2)]
        case .locusCoeruleus: return [r(.tract(.cortexL1), 0.5), r(.tract(.ca3), 0.2), r(.tract(.thalamusSensoryRelay), 0.3)]
        case .raphe: return [r(.tract(.cortexL1), 0.5), r(.tract(.striatum), 0.3), r(.tract(.dentateGyrus), 0.2)]
        case .reticularFormation: return [r(.tract(.thalamusSensoryRelay), 0.25), r(.tract(.thalamusMotorRelay), 0.25),
                                          r(.local(sigma: 32), 0.3), r(.tract(.basalForebrain), 0.2)]
        }
    }

    // MARK: Generation

    /// Fan-out of a specific neuron (mean ± 25 % deterministic variation).
    func fanOut(of id: NeuronID) -> Int {
        let mean = Self.meanFanOut(Lattice3D.region(of: id))
        let h = NeuroMath.hash(seed, id, 0xFA0)
        let variation = Int(Float(mean) * 0.5 * (NeuroMath.unit(h) - 0.5))
        return max(1, mean + variation)
    }

    /// The k-th outgoing synapse of neuron `id` — a pure function of (seed, id, k).
    func synapse(of id: NeuronID, index k: Int) -> ProceduralSynapse {
        let src = Lattice3D.coordinate(id)
        let region = Lattice3D.region(at: src)
        let rules = Self.rules(region)
        let h = NeuroMath.hash(seed, id, UInt64(k) &+ 1)

        // Pick the projection rule by its fan-out fraction.
        var pick = NeuroMath.unit(h)
        var rule = rules[rules.count - 1]
        for candidate in rules {
            if pick < candidate.fraction { rule = candidate; break }
            pick -= candidate.fraction
        }

        let h2 = NeuroMath.mix64(h ^ 0x51ED_270B)
        let h3 = NeuroMath.mix64(h2)
        let h4 = NeuroMath.mix64(h3)
        var dst: LatticeCoordinate
        switch rule.kind {
        case .local(let sigma):
            dst = LatticeCoordinate(src.x + Int32(NeuroMath.gaussianOffset(h2, sigma: sigma)),
                                    src.y + Int32(NeuroMath.gaussianOffset(h3, sigma: sigma)),
                                    src.z + Int32(NeuroMath.gaussianOffset(h4, sigma: sigma)))
            dst = Lattice3D.clamped(dst)
            if dst == src { dst.z = src.z == 0 ? 1 : src.z - 1 }
        case .parallelFibre:
            let folium = src.y / Lattice3D.foliumPeriod
            let span = Int64(1500)
            let dz = Int32(Int64(h3 % UInt64(2 * span + 1)) - span)
            dst = LatticeCoordinate(src.x + Int32(NeuroMath.gaussianOffset(h2, sigma: 32)),
                                    folium * Lattice3D.foliumPeriod + Lattice3D.purkinjeRow + Int32(h4 & 1),
                                    src.z + dz)
            dst = Lattice3D.clamped(dst)
            if dst.x >= Lattice3D.cerebrumStartX { dst.x = Lattice3D.cerebrumStartX - 1 }
            if Lattice3D.dcn.contains(dst) { dst.x = Lattice3D.dcn.x0 - 1 }
        case .tract(let target):
            let (u, v, w) = Lattice3D.normalisedPosition(src, in: region)
            // Topographic mapping with ±4 % jitter.
            let ju = (NeuroMath.unit(h2) - 0.5) * 0.08
            let jv = (NeuroMath.unit(h3) - 0.5) * 0.08
            let jw = (NeuroMath.unit(h4) - 0.5) * 0.08
            dst = Lattice3D.sample(in: target,
                                   u: NeuroMath.clamp(u + ju, 0, 0.9999),
                                   v: NeuroMath.clamp(v + jv, 0, 0.9999),
                                   w: NeuroMath.clamp(w + jw, 0, 0.9999),
                                   hash: NeuroMath.mix64(h4))
        }

        let targetID = Lattice3D.id(dst)
        let key = NeuroMath.hash(id, UInt64(k), seed)
        let base = Self.baseWeight(region) * (0.25 + 1.5 * NeuroMath.unit(NeuroMath.mix64(h ^ 0xBA5E)))
        let learned = plasticity.delta(for: key)
        let distance = src.distance(to: dst)
        let delay = UInt8(min(255, Int(distance / 64) + 1))
        return ProceduralSynapse(source: id, target: targetID, weight: rule.sign * base + learned, delay: delay, key: key)
    }

    /// All outgoing synapses of a neuron (optionally truncated).
    func synapses(of id: NeuronID, limit: Int? = nil) -> [ProceduralSynapse] {
        let n = min(fanOut(of: id), limit ?? Int.max)
        return (0..<n).map { synapse(of: id, index: $0) }
    }

    /// Hebbian/three-factor update of a procedural synapse (stored sparsely).
    func potentiate(_ synapse: ProceduralSynapse, by delta: Float) {
        plasticity.add(delta, for: synapse.key)
    }

    /// Total number of logical synapses in the lattice (Σ region size × mean fan-out).
    static func logicalSynapseCount() -> UInt64 {
        Lattice3D.census().reduce(0) { $0 + $1.value * UInt64(meanFanOut($1.key)) }
    }
}

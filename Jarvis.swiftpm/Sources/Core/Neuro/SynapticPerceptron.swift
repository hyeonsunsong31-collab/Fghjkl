import Foundation

/// Activation function of the soma.
enum ActivationKind: UInt8, Codable {
    case sigmoid
    case tanh
    case relu
    /// Graded firing rate (softplus, saturating at 1).
    case rate
    /// Spiking: emits 1 when the potential crosses threshold, then becomes refractory.
    case spiking

    func apply(_ x: Float) -> Float {
        switch self {
        case .sigmoid: return NeuroMath.sigmoid(x)
        case .tanh: return Float(Foundation.tanh(Double(x)))
        case .relu: return max(0, x)
        case .rate: return min(1, NeuroMath.softplus(x))
        case .spiking: return x >= 0 ? 1 : 0
        }
    }

    /// Surrogate derivative used for eligibility (well defined for spiking too).
    func derivative(_ x: Float, output y: Float) -> Float {
        switch self {
        case .sigmoid: return y * (1 - y)
        case .tanh: return 1 - y * y
        case .relu: return x > 0 ? 1 : 0.01
        case .rate: return y < 1 ? NeuroMath.sigmoid(x) : 0.01
        case .spiking: return 1 / (1 + abs(x) * 4) // fast-sigmoid surrogate
        }
    }
}

/// A dendritic branch: a group of synapses integrated **non-linearly** before
/// reaching the soma (NMDA-spike-like). Two branches let a single neuron
/// compute XOR, which a classic perceptron cannot.
struct DendriticBranch: Codable, Equatable {
    var synapses: [Synapse]
    /// Gain with which this branch drives the soma.
    var gain: Float = 1
    /// Local threshold of the branch non-linearity.
    var threshold: Float = 0.5
    /// Steepness of the branch non-linearity. 0 → linear branch (classic perceptron).
    var slope: Float = 0

    /// Integrate (already delayed) inputs through the branch.
    mutating func integrate(_ delayedInput: (Int, Int) -> Float) -> (drive: Float, raw: Float) {
        var raw: Float = 0
        for i in synapses.indices {
            let pre = delayedInput(synapses[i].inputIndex, synapses[i].delay)
            raw += synapses[i].transmit(pre)
        }
        if slope <= 0 { return (gain * raw, raw) }
        return (gain * NeuroMath.sigmoid(slope * (raw - threshold)), raw)
    }
}

/// **Synaptic Perceptron** — the new neuron unit of Jarvis' neural core.
///
/// Classic perceptron: `y = φ(Σ wᵢxᵢ + b)`.
///
/// Synaptic perceptron adds the synapse component and its consequences:
/// 1. every input passes through a `Synapse` (weight × dynamic efficacy u·R, sign by
///    transmitter, distance-dependent delay);
/// 2. synapses are grouped into **dendritic branches** with their own non-linearity;
/// 3. the soma is a **leaky integrator** `v ← αv + Σ D_b + b` with an **adaptive
///    (homeostatic) threshold** θ, so the bias becomes a living quantity;
/// 4. the output is gain-modulated by acetylcholine and can be graded or spiking;
/// 5. learning is **three-factor** — local eligibility × a broadcast neuromodulatory
///    or teaching signal — so that the *population* learns to control what the AI
///    finally outputs (the "control objective", see `OutputController`).
final class SynapticPerceptron: Codable {
    /// Neuron identifier — its linear index inside the 3D lattice.
    let id: NeuronID
    var branches: [DendriticBranch]
    var bias: Float
    var threshold: Float
    /// Membrane leak α (0 = memoryless classic perceptron, →1 = long integration).
    var leak: Float
    var activation: ActivationKind
    var targetRate: Float
    var homeostasisRate: Float
    var refractoryPeriod: Int
    var learningRate: Float

    private(set) var potential: Float = 0
    private(set) var output: Float = 0
    private(set) var lastInput: Float = 0  // pre-activation (v − θ)
    private var refractoryLeft = 0
    private var averageRate: Float
    /// Ring buffer of past input vectors for delayed transmission.
    private var history: [[Float]] = []
    private var historyHead = 0

    init(id: NeuronID,
         branches: [DendriticBranch],
         bias: Float = 0,
         threshold: Float = 0,
         leak: Float = 0,
         activation: ActivationKind = .sigmoid,
         targetRate: Float = 0.2,
         homeostasisRate: Float = 0,
         refractoryPeriod: Int = 0,
         learningRate: Float = 0.05) {
        self.id = id
        self.branches = branches
        self.bias = bias
        self.threshold = threshold
        self.leak = leak
        self.activation = activation
        self.targetRate = targetRate
        self.homeostasisRate = homeostasisRate
        self.refractoryPeriod = refractoryPeriod
        self.learningRate = learningRate
        self.averageRate = targetRate
    }

    /// Convenience: single linear branch — behaves exactly like a classic perceptron
    /// when leak = 0, delays = 0, STP disabled (U = 1, τ = 1).
    static func classic(id: NeuronID, weights: [Float], bias: Float, activation: ActivationKind = .sigmoid) -> SynapticPerceptron {
        let synapses = weights.enumerated().map { index, w in
            Synapse(inputIndex: index,
                    weight: abs(w),
                    transmitter: w >= 0 ? .glutamate : .gaba,
                    baselineRelease: 1, tauFacilitation: 1, tauDepression: 1)
        }
        return SynapticPerceptron(id: id, branches: [DendriticBranch(synapses: synapses)], bias: bias, activation: activation)
    }

    var maxDelay: Int { branches.flatMap { $0.synapses }.map(\.delay).max() ?? 0 }
    var synapseCount: Int { branches.reduce(0) { $0 + $1.synapses.count } }

    /// One forward tick.
    @discardableResult
    func forward(_ inputs: [Float], modulators: NeuromodulatorState = NeuromodulatorState()) -> Float {
        let depth = maxDelay + 1
        if history.count != depth {
            history = Array(repeating: Array(repeating: 0, count: inputs.count), count: depth)
            historyHead = 0
        }
        historyHead = (historyHead + 1) % depth
        history[historyHead] = inputs

        let readDelayed: (Int, Int) -> Float = { [history, historyHead] index, delay in
            let slot = (historyHead - delay + depth) % depth
            let row = history[slot]
            return index < row.count ? row[index] : 0
        }

        var drive: Float = 0
        for b in branches.indices {
            drive += branches[b].integrate(readDelayed).drive
        }

        potential = leak * potential + drive + bias
        let pre = potential - threshold
        lastInput = pre

        if refractoryLeft > 0 {
            refractoryLeft -= 1
            output = 0
        } else {
            output = activation.apply(pre) * modulators.outputGain / NeuromodulatorState().outputGain
            if activation == .spiking && output > 0 {
                potential = 0 // reset after a spike
                refractoryLeft = refractoryPeriod
            }
        }

        // Homeostatic threshold adaptation (intrinsic plasticity).
        averageRate = averageRate * 0.95 + output * 0.05
        if homeostasisRate > 0 {
            threshold += homeostasisRate * (averageRate - targetRate)
        }

        // Eligibility traces.
        let postTerm = activation.derivative(pre, output: output)
        for b in branches.indices {
            for s in branches[b].synapses.indices {
                let syn = branches[b].synapses[s]
                let p = readDelayed(syn.inputIndex, syn.delay)
                branches[b].synapses[s].updateEligibility(pre: p, postTerm: postTerm)
            }
        }
        return output
    }

    /// Apply long-term plasticity with an optional teaching signal (e.g. `target − output`).
    func learn(modulators: NeuromodulatorState, teaching: Float = 0) {
        guard !history.isEmpty else { return }
        let depth = history.count
        for b in branches.indices {
            for s in branches[b].synapses.indices {
                let syn = branches[b].synapses[s]
                let slot = (historyHead - syn.delay + depth) % depth
                let row = history[slot]
                let pre = syn.inputIndex < row.count ? row[syn.inputIndex] : 0
                branches[b].synapses[s].learn(modulators: modulators, teaching: teaching,
                                              rate: learningRate, pre: pre, post: output)
            }
        }
        // Bias follows the same three-factor signal.
        bias += learningRate * modulators.learningGain * teaching * activation.derivative(lastInput, output: output)
    }

    /// Supervised convenience: drive the output towards `target` using the
    /// teaching signal as the third factor.
    func train(_ inputs: [Float], target: Float, modulators: NeuromodulatorState = NeuromodulatorState()) -> Float {
        let y = forward(inputs, modulators: modulators)
        learn(modulators: modulators, teaching: target - y)
        return y
    }

    func resetState() {
        potential = 0
        output = 0
        refractoryLeft = 0
        history = []
        for b in branches.indices {
            for s in branches[b].synapses.indices {
                branches[b].synapses[s].release = branches[b].synapses[s].baselineRelease
                branches[b].synapses[s].resources = 1
                branches[b].synapses[s].eligibility = 0
                branches[b].synapses[s].preTrace = 0
            }
        }
    }
}

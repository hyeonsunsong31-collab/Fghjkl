import Foundation

/// Neurotransmitter of a synapse; its raw value is the sign of transmission.
enum Transmitter: Int8, Codable {
    case glutamate = 1   // excitatory
    case gaba = -1       // inhibitory
}

/// Learning rule attached to a synapse.
enum PlasticityRule: UInt8, Codable {
    case none
    /// Unsupervised Hebbian with Oja normalisation (cortex association).
    case hebbian
    /// Spike-timing dependent: pre-before-post potentiates, post-before-pre depresses.
    case stdp
    /// Three-factor: Δw = η · M · e, where M is a neuromodulatory/teaching signal.
    case threeFactor
    /// Marr–Albus–Ito: climbing-fibre error depresses recently active parallel fibres.
    case cerebellarLTD
}

/// The **synapse component** added to the classic perceptron.
///
/// Beyond a scalar weight it carries the machinery that lets perceptrons
/// *control each other* over time:
/// - short-term plasticity (Tsodyks–Markram facilitation `u` and depression `R`)
/// - transmission delay (ticks, proportional to 3D distance in the lattice)
/// - an eligibility trace that remembers recent pre/post co-activity
/// - receptor sensitivities so neuromodulators can gate learning per synapse
struct Synapse: Codable, Equatable {
    /// Index of the presynaptic signal in the owning perceptron's input vector.
    var inputIndex: Int
    /// Long-term efficacy (magnitude ≥ 0; sign comes from the transmitter).
    var weight: Float
    var transmitter: Transmitter
    /// Baseline release probability U.
    var baselineRelease: Float
    /// Current release probability u (facilitation state).
    var release: Float
    /// Available vesicle resources R (depression state).
    var resources: Float
    /// Facilitation recovery time constant (ticks).
    var tauFacilitation: Float
    /// Depression recovery time constant (ticks).
    var tauDepression: Float
    /// Transmission delay in ticks.
    var delay: Int
    /// Eligibility trace e.
    var eligibility: Float = 0
    /// Per-tick decay of the eligibility trace.
    var traceDecay: Float = 0.9
    var rule: PlasticityRule
    var receptors: ModulatorReceptors
    /// Running presynaptic trace (for STDP).
    var preTrace: Float = 0

    init(inputIndex: Int,
         weight: Float,
         transmitter: Transmitter = .glutamate,
         baselineRelease: Float = 0.5,
         tauFacilitation: Float = 8,
         tauDepression: Float = 20,
         delay: Int = 0,
         rule: PlasticityRule = .threeFactor,
         receptors: ModulatorReceptors = .standard) {
        self.inputIndex = inputIndex
        self.weight = max(0, weight)
        self.transmitter = transmitter
        self.baselineRelease = baselineRelease
        self.release = baselineRelease
        self.resources = 1
        self.tauFacilitation = max(1, tauFacilitation)
        self.tauDepression = max(1, tauDepression)
        self.delay = max(0, delay)
        self.rule = rule
        self.receptors = receptors
    }

    /// Current dynamic efficacy u·R normalised by its resting value U·1, so a
    /// rested synapse transmits exactly `weight`.
    var dynamicEfficacy: Float { (release * resources) / max(baselineRelease, 1e-4) }

    /// Transmit a presynaptic activity (0…1) through the synapse for one tick and
    /// update the short-term plasticity state.
    mutating func transmit(_ presynaptic: Float) -> Float {
        // Recovery towards rest.
        release += (baselineRelease - release) / tauFacilitation
        resources += (1 - resources) / tauDepression
        let efficacy = dynamicEfficacy
        let signal = Float(transmitter.rawValue) * weight * efficacy * presynaptic
        // Use-dependent changes: facilitation increases u, release consumes R.
        let used = release * resources * presynaptic
        release += baselineRelease * (1 - release) * presynaptic
        resources = max(0, resources - used)
        preTrace = preTrace * 0.8 + presynaptic
        return signal
    }

    /// Update the eligibility trace from pre/post co-activity.
    mutating func updateEligibility(pre: Float, postTerm: Float) {
        switch rule {
        case .stdp:
            // Potentiate when post follows pre (preTrace high), depress otherwise.
            eligibility = eligibility * traceDecay + preTrace * postTerm - 0.5 * pre * (1 - postTerm) * 0.1
        default:
            eligibility = eligibility * traceDecay + pre * postTerm
        }
    }

    /// Apply long-term plasticity.
    /// - Parameters:
    ///   - modulators: global neuromodulator state.
    ///   - teaching: region-specific teaching signal (climbing-fibre error, supervised error…).
    ///   - rate: base learning rate η.
    ///   - post: current postsynaptic output (for Hebbian/Oja).
    ///   - pre: current (delayed) presynaptic activity.
    mutating func learn(modulators: NeuromodulatorState, teaching: Float, rate: Float, pre: Float, post: Float) {
        let eta = rate * modulators.learningGain
        var delta: Float = 0
        switch rule {
        case .none:
            return
        case .hebbian:
            // Oja's rule keeps the weight vector bounded.
            delta = eta * post * (pre - post * weight)
        case .stdp, .threeFactor:
            delta = eta * receptors.thirdFactor(modulators, teaching: teaching) * eligibility
        case .cerebellarLTD:
            // Error > 0 (climbing fibre fired) → LTD of active fibres; small LTP otherwise.
            delta = teaching > 0 ? -eta * teaching * pre : eta * 0.05 * pre
        }
        // Signed learning: for inhibitory synapses the magnitude moves the opposite way.
        weight = NeuroMath.clamp(weight + Float(transmitter.rawValue) * delta, 0, 8)
    }
}

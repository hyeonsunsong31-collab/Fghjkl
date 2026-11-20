import Foundation

/// Global neuromodulator concentrations broadcast to every synaptic perceptron.
///
/// - dopamine:        phasic reward-prediction error (−1…1). Gates three-factor learning.
/// - acetylcholine:   attention / input gain (0…1). Sharpens thalamic gating.
/// - noradrenaline:   arousal & exploration (0…1). Raises learning rate and action noise.
/// - serotonin:       patience / temporal discounting (0…1). Damps impulsive actions.
struct NeuromodulatorState: Codable, Equatable {
    var dopamine: Float = 0
    var acetylcholine: Float = 0.5
    var noradrenaline: Float = 0.3
    var serotonin: Float = 0.5

    /// Relax phasic signals back towards their tonic baselines.
    mutating func relax(rate: Float = 0.15) {
        dopamine += (0 - dopamine) * rate
        acetylcholine += (0.5 - acetylcholine) * rate * 0.5
        noradrenaline += (0.3 - noradrenaline) * rate * 0.5
        serotonin += (0.5 - serotonin) * rate * 0.25
        clampAll()
    }

    mutating func clampAll() {
        dopamine = NeuroMath.clamp(dopamine, -1, 1)
        acetylcholine = NeuroMath.clamp(acetylcholine, 0, 1)
        noradrenaline = NeuroMath.clamp(noradrenaline, 0, 1)
        serotonin = NeuroMath.clamp(serotonin, 0, 1)
    }

    /// Multiplicative factor applied to plasticity everywhere (arousal boosts learning).
    var learningGain: Float { 0.75 + 0.75 * noradrenaline }

    /// Multiplicative gain applied to neuron output (attention).
    var outputGain: Float { 0.8 + 0.4 * acetylcholine }
}

/// Per-synapse receptor sensitivities to each neuromodulator.
struct ModulatorReceptors: Codable, Equatable {
    var dopamine: Float = 1
    var acetylcholine: Float = 0.5
    var noradrenaline: Float = 0.5
    var serotonin: Float = 0.2

    static let standard = ModulatorReceptors()
    static let striatalD1 = ModulatorReceptors(dopamine: 1.0, acetylcholine: 0.3, noradrenaline: 0.3, serotonin: 0.2)
    static let striatalD2 = ModulatorReceptors(dopamine: -1.0, acetylcholine: 0.3, noradrenaline: 0.3, serotonin: 0.2)
    static let cerebellar = ModulatorReceptors(dopamine: 0.1, acetylcholine: 0.2, noradrenaline: 0.6, serotonin: 0.1)

    /// Effective third-factor signal M seen by a synapse given the global state and an
    /// optional region-specific teaching signal (e.g. climbing-fibre error).
    func thirdFactor(_ state: NeuromodulatorState, teaching: Float = 0) -> Float {
        dopamine * state.dopamine
            + noradrenaline * (state.noradrenaline - 0.3) * 0.25
            + serotonin * (state.serotonin - 0.5) * 0.1
            + teaching
    }
}

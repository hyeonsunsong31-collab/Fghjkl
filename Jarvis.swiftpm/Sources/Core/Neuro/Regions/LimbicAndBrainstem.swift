import Foundation

/// **Amygdala** — salience, urgency and valence of an input.
struct Amygdala {
    struct Appraisal: Equatable {
        var salience: Float
        var urgency: Float
        /// −1 negative … +1 positive.
        var valence: Float
    }

    static let urgentWords = ["urgent", "emergency", "asap", "immediately", "now", "quick", "hurry", "help",
                              "긴급", "급해", "빨리", "당장", "지금", "어서", "도와", "응급", "위험"]
    static let negativeWords = ["wrong", "no", "bad", "stop", "terrible", "annoying", "useless", "hate",
                                "틀렸", "아니", "별로", "싫", "그만", "짜증", "답답", "실망"]
    static let positiveWords = ["thanks", "thank you", "great", "perfect", "good", "excellent", "brilliant", "love",
                                "고마", "감사", "좋아", "완벽", "훌륭", "최고", "잘했"]

    /// English cues match whole words/phrases; Korean cues match stems inside words.
    static func hits(_ cues: [String], in lower: String, tokens: Set<String>) -> Int {
        cues.filter { cue in
            if cue.unicodeScalars.allSatisfy({ $0.isASCII }) {
                return cue.contains(" ") ? (" " + lower + " ").contains(" " + cue + " ") : tokens.contains(cue)
            }
            return lower.contains(cue)
        }.count
    }

    func appraise(_ text: String) -> Appraisal {
        let lower = text.lowercased()
        let tokens = Set(TextEncoder.tokens(lower))
        let urgentHits = Self.hits(Self.urgentWords, in: lower, tokens: tokens)
        let neg = Self.hits(Self.negativeWords, in: lower, tokens: tokens)
        let pos = Self.hits(Self.positiveWords, in: lower, tokens: tokens)
        let exclaim = Float(text.filter { $0 == "!" }.count)
        let letters = text.filter { $0.isLetter }
        let caps = letters.isEmpty ? 0 : Float(letters.filter { $0.isUppercase }.count) / Float(letters.count)
        let urgency = NeuroMath.clamp(Float(urgentHits) * 0.35 + exclaim * 0.1 + (caps > 0.6 && letters.count > 3 ? 0.3 : 0), 0, 1)
        let valence = NeuroMath.clamp(Float(pos - neg) * 0.4, -1, 1)
        let salience = NeuroMath.clamp(0.3 + urgency * 0.5 + abs(valence) * 0.3, 0, 1)
        return Appraisal(salience: salience, urgency: urgency, valence: valence)
    }
}

/// **Hypothalamus** — homeostasis: keeps the AI's appetite for compute within
/// what the battery and temperature of the device can afford.
struct Hypothalamus {
    func budget(for body: BodyState) -> ComputeBudget {
        let hot = body.thermalState >= 2
        let critical = body.thermalState >= 3
        let lowBattery = body.batteryLevel < 0.15 && !body.isCharging
        let allowDeep = !critical && !lowBattery && !(body.lowPowerMode && !body.isCharging)
        var events = 2_000_000
        if body.lowPowerMode || hot { events = 250_000 }
        if critical || lowBattery { events = 0 }
        if body.isCharging && !hot { events = 4_000_000 }
        return ComputeBudget(allowDeepThink: allowDeep,
                             latticeEventsPerTick: events,
                             allowConsolidation: body.isCharging || body.batteryLevel > 0.5,
                             maxResponseTokens: (body.lowPowerMode || hot) ? 400 : 900)
    }
}

/// **Brainstem** — arousal (reticular activating system), neuromodulator nuclei
/// (VTA dopamine, locus-coeruleus noradrenaline, raphe serotonin, basal-forebrain
/// acetylcholine) and the inferior olive that turns prediction errors into
/// climbing-fibre teaching signals.
final class Brainstem {
    private(set) var arousal: ArousalState = .asleep
    var modulators = NeuromodulatorState()

    func transition(to state: ArousalState) {
        arousal = state
        switch state {
        case .asleep:
            modulators.acetylcholine = 0.2
            modulators.noradrenaline = 0.1
        case .listening:
            modulators.acetylcholine = 0.5
            modulators.noradrenaline = 0.3
        case .attentive:
            modulators.acetylcholine = 0.8
            modulators.noradrenaline = 0.45
        case .speaking:
            modulators.acetylcholine = 0.6
        }
    }

    /// Phasic responses to an appraised input.
    func respond(to appraisal: Amygdala.Appraisal, novelty: Float) {
        modulators.noradrenaline += 0.3 * appraisal.urgency + 0.15 * novelty
        modulators.acetylcholine += 0.2 * appraisal.salience
        modulators.serotonin += 0.1 * appraisal.valence
        modulators.clampAll()
    }

    /// VTA: broadcast the reward-prediction error.
    func releaseDopamine(_ rpe: Float) {
        modulators.dopamine = NeuroMath.clamp(rpe, -1, 1)
        if rpe > 0 { modulators.serotonin += 0.05 * rpe }
        modulators.clampAll()
    }

    /// Inferior olive: prediction error → climbing-fibre error (clipped).
    func climbingFibre(predicted: Float, actual: Float) -> Float {
        NeuroMath.clamp(predicted - actual, -1, 1)
    }

    func relax() { modulators.relax() }
}

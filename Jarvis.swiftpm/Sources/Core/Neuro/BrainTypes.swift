import Foundation

/// Coarse intent classes learned by the cortex (L5 readout).
enum IntentClass: String, CaseIterable, Codable {
    case smallTalk, question, command3D, deviceControl, appLaunch, music, web, fileTask, memoryRecall, systemControl, creative, other

    var index: Int { Self.allCases.firstIndex(of: self)! }
}

/// High-level action chosen by the basal ganglia.
enum AgentAction: String, CaseIterable, Codable {
    /// Deterministic grammar command — instant, no language model.
    case fastCommand
    /// Conversational answer from the language model.
    case conversational
    /// Language model with tool calling (agentic).
    case toolUse
    /// Ask the user a clarifying question.
    case clarify
    /// Escalate to the larger local "deep think" model.
    case deepThink

    var index: Int { Self.allCases.firstIndex(of: self)! }
}

/// Kinds of context the thalamus can relay to the language model.
enum ChannelKind: String, CaseIterable, Codable {
    case conversation, memory, scene, device, toolResult, screen, profile, task

    var index: Int { Self.allCases.firstIndex(of: self)! }
}

/// A candidate piece of context competing for the language model's limited window.
struct ContextChannel: Codable, Equatable {
    var id: String
    var kind: ChannelKind
    var text: String
    var tokenCost: Int
    /// 0…1, externally estimated importance.
    var salience: Float
    /// 0…1, 1 = just now.
    var recency: Float
    /// Always include if it fits.
    var pinned: Bool = false
    var code: SparseCode

    init(id: String, kind: ChannelKind, text: String, salience: Float = 0.5, recency: Float = 0.5, pinned: Bool = false, encoder: TextEncoder = TextEncoder()) {
        self.id = id
        self.kind = kind
        self.text = text
        // Rough token estimate: Hangul packs far fewer characters per token than Latin text.
        self.tokenCost = max(1, Hangul.hangulRatio(text) > 0.3 ? text.count * 2 / 3 : text.count / 3)
        self.salience = salience
        self.recency = recency
        self.pinned = pinned
        self.code = encoder.encode(text)
    }
}

struct GatedChannel: Equatable {
    var channel: ContextChannel
    var gate: Float
}

/// Homeostatic inputs from the device "body".
struct BodyState: Codable, Equatable {
    var batteryLevel: Float = 1
    var isCharging: Bool = false
    /// 0 nominal, 1 fair, 2 serious, 3 critical.
    var thermalState: Int = 0
    var lowPowerMode: Bool = false
}

/// Compute budget decided by the hypothalamus.
struct ComputeBudget: Codable, Equatable {
    var allowDeepThink: Bool
    var latticeEventsPerTick: Int
    var allowConsolidation: Bool
    var maxResponseTokens: Int
}

enum ArousalState: String, Codable {
    case asleep, listening, attentive, speaking
}

enum FeedbackKind: String, Codable {
    case positive, negative, interrupted, correction, neutral, requestedMoreDetail, requestedBrevity
}

/// What the brain receives for each user turn.
struct BrainInput {
    var text: String
    var language: DetectedLanguage
    var isVoice: Bool
    /// Confidence of the deterministic command grammar (0 if no match).
    var grammarConfidence: Float
    /// Intent class implied by the grammar match, used as a teaching label for the cortex.
    var grammarIntent: IntentClass?
    var channels: [ContextChannel]
    var body: BodyState
    var deepThinkAvailable: Bool
    var deepThinkRequested: Bool = false
    var tokenBudget: Int = 900
}

/// The brain's control decision for one turn.
struct BrainDecision {
    var id: UUID = UUID()
    var action: AgentAction
    var actionProbabilities: [AgentAction: Float]
    var gatedChannels: [GatedChannel]
    var intentScores: [IntentClass: Float]
    var topIntent: IntentClass
    var cerebellar: CerebellarOutput
    var salience: Float
    var urgency: Float
    var arousal: ArousalState
    var budget: ComputeBudget
    var novelty: Float
    /// Lattice IDs of core neurons active during this decision (for the brain hologram).
    var activeNeurons: [NeuronID]
}

/// What happened after a decision, for learning.
struct BrainOutcome {
    var success: Bool
    var actualSeconds: Double
    var feedback: FeedbackKind
    /// Number of output-control violations detected before repair.
    var controlViolations: Int
    /// Ground-truth intent if it became known (e.g. grammar or tool executed).
    var resolvedIntent: IntentClass?
    var outputCharacters: Int
}

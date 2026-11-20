import Foundation

/// Purpose of an explanation text (requirement 2-(2)).
enum ExplanationKind: String, Codable, CaseIterable {
    /// (2-1) Explanation of an error.
    case error
    /// (2-2) Explanation answering the user's question.
    case answer
    /// (2-3) How a task succeeded or failed, step by step.
    case process
    /// (2-4) How long a task is expected to take.
    case timeEstimate
}

struct Explanation: Codable, Equatable {
    var kind: ExplanationKind
    var text: String
}

/// An option for continuous adjustment (requirement 2-(3)); tapping or saying it runs `utterance`.
struct SuggestedOption: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var label: String
    var utterance: String
}

/// A recommendation / proposal supporting the options (requirement 2-(4)).
struct Recommendation: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var text: String
    var utterance: String?
}

/// The complete, loggable result of one agent turn.
struct AgentTurnResult: Codable, Equatable {
    var reply: String
    var language: DetectedLanguage
    var explanations: [Explanation] = []
    var options: [SuggestedOption] = []
    var recommendations: [Recommendation] = []
    var estimatedSeconds: Double?
    var artifactPaths: [String] = []
    var success: Bool = true
}

/// Where a command came from.
enum InputModality: String, Codable {
    case voice, text, button, shortcut, system
}

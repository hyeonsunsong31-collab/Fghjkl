import Foundation

/// A request to a language model, already shaped by the neural core
/// (thalamic context gating, cerebellar generation parameters).
struct LLMRequest {
    var userText: String
    var language: DetectedLanguage
    var context: [GatedChannel]
    var withTools: Bool
    var temperature: Float
    var maxTokens: Int
    var verbosity: Float
    /// Extra correction instruction from the output controller (on retries).
    var correction: String?
}

struct ToolCallRecord: Codable, Equatable {
    var name: String
    var arguments: String
    var result: String
    var success: Bool
    var duration: Double
}

struct LLMResult {
    var reply: String
    var errorExplanation: String = ""
    var processExplanation: String = ""
    var options: [String] = []
    var recommendation: String = ""
    var toolCalls: [ToolCallRecord] = []
    var engineName: String

    var toolsSucceeded: Bool { toolCalls.contains { $0.success } }
}

/// Common interface of Jarvis' language engines.
@MainActor
protocol LanguageEngine: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    func prewarm()
    /// Generate a reply; `onText` receives incremental reply text for streaming speech.
    func respond(_ request: LLMRequest, onText: @escaping (String) -> Void) async throws -> LLMResult
}

/// Builds the prompt text shared by all engines.
enum PromptBuilder {
    static func prompt(for request: LLMRequest) -> String {
        var parts: [String] = []
        if !request.context.isEmpty {
            let header = request.language == .korean ? "참고 맥락:" : "Context:"
            parts.append(header + "\n" + request.context.map { "- [\($0.channel.kind.rawValue)] \($0.channel.text)" }.joined(separator: "\n"))
        }
        let lengthHint: String
        switch request.verbosity {
        case ..<0.3: lengthHint = request.language == .korean ? "한두 문장으로 아주 간결하게 답하십시오." : "Answer in one or two short sentences."
        case ..<0.7: lengthHint = request.language == .korean ? "간결하게 답하십시오." : "Be concise."
        default: lengthHint = request.language == .korean ? "충분히 자세히 답하십시오." : "You may answer in some detail."
        }
        parts.append(lengthHint)
        if let c = request.correction, !c.isEmpty { parts.append(c) }
        let label = request.language == .korean ? "사용자:" : "User:"
        parts.append("\(label) \(request.userText)")
        return parts.joined(separator: "\n\n")
    }
}

import Foundation

/// Used when neither Apple Intelligence nor the Deep-Think model is available.
/// It still executes every built-in command (via the grammar) and answers from
/// memory, and explains clearly how to enable a full language model.
@MainActor
final class FallbackEngine: LanguageEngine {
    let name = "Built-in responses"
    var isAvailable: Bool { true }
    var unavailableReason: String? { nil }
    weak var brain: Brain?

    func prewarm() {}

    func respond(_ request: LLMRequest, onText: @escaping (String) -> Void) async throws -> LLMResult {
        let ko = request.language == .korean
        let text = request.userText.lowercased()
        var reply: String
        if ["hello", "hi", "good morning", "good evening", "안녕", "반가워"].contains(where: { text.contains($0) }) {
            reply = ko ? "안녕하십니까. 무엇을 도와드릴까요?" : "Good day, sir. How may I help?"
        } else if ["thank", "고마", "감사"].contains(where: { text.contains($0) }) {
            reply = ko ? "천만의 말씀입니다." : "You're most welcome, sir."
        } else if let memory = brain?.recall(request.userText, k: 1).first, memory.1 > 0.35 {
            reply = ko ? "기억하기로는 이렇습니다. \(memory.0.text)" : "From memory, sir: \(memory.0.text)"
        } else {
            reply = ko
                ? "그 질문에 답하려면 언어 모델이 필요합니다. 설정에서 Apple Intelligence를 켜시거나 심층 사고 모델을 내려받아 주십시오. 기본 명령은 지금도 모두 실행할 수 있습니다."
                : "To answer that properly I need a language model, sir. Please enable Apple Intelligence in Settings or download the Deep-Think model. All built-in commands work in the meantime."
        }
        onText(reply)
        return LLMResult(reply: reply,
                         errorExplanation: "",
                         processExplanation: "",
                         options: ko ? ["도움말", "설정 열어"] : ["help", "open settings"],
                         recommendation: "",
                         toolCalls: [],
                         engineName: name)
    }
}

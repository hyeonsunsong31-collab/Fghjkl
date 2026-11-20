import Foundation

/// Runs one conversational turn end to end:
///
/// input → language detection → command grammar → **brain decision**
/// (thalamic context gating, basal-ganglia action selection, cerebellar
/// control parameters, time prediction) → fast command execution or language
/// model with tools (streamed to speech) → **output control** (verify / repair /
/// regenerate) → logging of every artefact → learning feedback to the brain.
@MainActor
final class Orchestrator {
    unowned let c: JarvisController
    private let grammar = CommandGrammar()
    private let outputControl = OutputController()
    private let optionGenerator = OptionGenerator()
    private var turnCounter = 0

    /// Bookkeeping of the previous turn, judged when the next input arrives.
    private struct PendingFeedback {
        var success: Bool
        var seconds: Double
        var violations: Int
        var intent: IntentClass?
        var characters: Int
        var interrupted: Bool
    }
    private var pending: PendingFeedback?

    init(controller: JarvisController) { c = controller }

    func noteInterruption() { pending?.interrupted = true }

    // MARK: Turn

    func handle(_ raw: String, modality: InputModality, languageHint: DetectedLanguage?, confidence: Double?) async {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        turnCounter += 1
        let started = Date()

        // Typed or spoken wake phrase with a trailing command.
        if let wake = WakeWordMatcher().match(text) {
            if wake.trailingCommand.isEmpty {
                // An explicit wake phrase is always answered with the wake response.
                c.respondToWake()
                return
            }
            if !c.isAwake { c.wake(source: modality) }
            text = wake.trailingCommand
        }

        // Language: follow the user's language automatically (or the fixed mode).
        let detected = languageHint ?? c.detectLanguage(text)
        let language: DetectedLanguage
        switch c.languageMode {
        case .auto: language = detected
        case .korean: language = .korean
        case .english: language = .english
        }
        c.currentLanguage = language

        // Judge the previous turn from this reaction, then teach the brain.
        deliverPendingFeedback(reaction: text)

        // Pending confirmation (calls, messages, clearing the scene).
        if let pendingCommand = c.pendingConfirmation {
            c.pendingConfirmation = nil
            if Self.isAffirmative(text) {
                await executeConfirmed(pendingCommand, language: language)
                return
            } else if Self.isNegative(text) {
                let reply = language == .korean ? "알겠습니다. 취소했습니다." : "Very well, sir. Cancelled."
                finish(reply: reply, language: language, runID: nil)
                return
            }
        }

        let commandID = c.records.logCommand(text: text, modality: modality, language: language, transcript: modality == .voice ? raw : nil,
                                             confidence: confidence, intent: nil)
        c.appendMessage(.user, text, language: language)
        c.records.logMessage(role: "user", text: text, language: language, runID: nil)
        c.phase = .thinking

        // Deterministic grammar + neural decision.
        let parsed = grammar.parse(text)
        let channels = ContextBuilder.channels(for: c, language: language)
        let input = BrainInput(text: text, language: language, isVoice: modality == .voice,
                               grammarConfidence: parsed.confidence,
                               grammarIntent: parsed.commands.first?.intent.intentClass,
                               channels: channels, body: DeviceState.body(),
                               deepThinkAvailable: c.deepThink.isAvailable,
                               deepThinkRequested: c.deepThinkEnabled,
                               tokenBudget: 900)
        let decision = c.brain.process(input)
        c.stimulateLattice(decision.activeNeurons)

        let useFast = !parsed.isEmpty && parsed.confidence >= 0.75 && (decision.action == .fastCommand || parsed.confidence >= 0.88)
        let routeKey = useFast ? (parsed.commands.first.map { $0.intent.rawValue } ?? "fastCommand") : decision.action.rawValue
        let estimate = c.timeEstimator.estimate(key: routeKey, cerebellar: decision.cerebellar.predictedSeconds)
        let runID = c.records.beginRun(commandID: commandID, title: String(text.prefix(80)), action: useFast ? "fastCommand" : decision.action.rawValue, estimated: estimate)
        c.currentRunID = runID

        var explanations: [Explanation] = []
        if !useFast && c.timeEstimator.shouldAnnounce(estimate) {
            let phrase = TimeEstimator.phrase(estimate, language: language)
            explanations.append(Explanation(kind: .timeEstimate, text: phrase))
            c.speech.speak(phrase, language: language)
        }
        c.speech.rate = max(0.7, min(1.35, decision.cerebellar.speechRate * (Float(c.records.setting("speechRate") ?? "1") ?? 1)))

        var result: AgentTurnResult
        var violations = 0
        if useFast {
            result = await runCommands(parsed.commands, language: language, runID: runID, original: text)
        } else if decision.action == .clarify, let guess = parsed.commands.first {
            c.pendingConfirmation = guess
            let q = language == .korean ? "혹시 '\(guess.text)'(을)를 실행하라는 말씀이십니까?" : "Did you mean for me to \(guess.text.lowercased()), sir?"
            result = AgentTurnResult(reply: q, language: language)
            c.speech.speak(q, language: language)
        } else {
            let useDeep = (decision.action == .deepThink || c.deepThinkEnabled) && c.deepThink.isAvailable && decision.budget.allowDeepThink
            (result, violations) = await runLanguageModel(text: text, language: language, decision: decision, deep: useDeep, runID: runID)
        }
        guard !Task.isCancelled else {
            c.records.endRun(runID, success: false, actual: Date().timeIntervalSince(started), error: "interrupted")
            pending = PendingFeedback(success: false, seconds: Date().timeIntervalSince(started), violations: 0,
                                      intent: parsed.commands.first?.intent.intentClass, characters: 0, interrupted: true)
            return
        }

        result.explanations = explanations + result.explanations
        if result.estimatedSeconds == nil { result.estimatedSeconds = estimate }
        let seconds = Date().timeIntervalSince(started)
        c.timeEstimator.record(key: routeKey, seconds: seconds)
        c.records.endRun(runID, success: result.success, actual: seconds,
                         error: result.success ? nil : result.explanations.first { $0.kind == .error }?.text)
        c.records.logTurn(result, runID: runID)
        c.lastTurn = result
        c.currentRunID = nil
        if c.phase == .thinking { c.phase = c.speech.isSpeaking ? .speaking : .listening }

        pending = PendingFeedback(success: result.success, seconds: seconds, violations: violations,
                                  intent: parsed.commands.first?.intent.intentClass ?? (useFast ? nil : decision.topIntent),
                                  characters: result.reply.count, interrupted: false)
        if turnCounter % 5 == 0 { c.saveBrain() }
        c.lastInteraction = Date()
    }

    // MARK: Fast path

    private func runCommands(_ commands: [Command], language: DetectedLanguage, runID: String, original: String) async -> AgentTurnResult {
        var workflow = Workflow(title: String(original.prefix(60)), originalRequest: original, language: language,
                                steps: commands.map { WorkflowStep(title: $0.text, command: $0) })
        if commands.count > 1 { c.currentWorkflow = workflow }
        return await runWorkflow(&workflow, runID: runID)
    }

    private func runWorkflow(_ workflow: inout Workflow, runID: String) async -> AgentTurnResult {
        let language = workflow.language
        var replies: [String] = []
        var errors: [String] = []
        var artifacts: [String] = []
        var lastCommand: Command?
        var lastSuccess = true
        while let i = workflow.nextPendingIndex {
            if Task.isCancelled { break }
            guard let command = workflow.steps[i].command else { workflow.succeed(step: i, summary: nil); continue }
            if command.intent.requiresConfirmation {
                c.pendingConfirmation = command
                let q = Persona.confirmationQuestion(for: command, language: language)
                workflow.cancel()
                saveCheckpoint(workflow)
                c.speech.speak(q, language: language)
                c.appendMessage(.assistant, q, language: language)
                c.records.logMessage(role: "assistant", text: q, language: language, runID: runID)
                return AgentTurnResult(reply: q, language: language)
            }
            workflow.start(step: i)
            saveCheckpoint(workflow)
            let stepStart = Date()
            let outcome = await c.executor.execute(command, language: language, runID: runID)
            if outcome.success {
                workflow.succeed(step: i, summary: outcome.detail.isEmpty ? nil : outcome.detail)
                let reply = outcome.spokenOverride ?? Persona.confirmation(for: command, language: language, detail: outcome.detail, variant: turnCounter)
                if !reply.isEmpty { replies.append(reply) }
            } else {
                workflow.fail(step: i, error: outcome.detail)
                errors.append(outcome.detail)
            }
            artifacts += outcome.artifacts.map { $0.path.replacingOccurrences(of: JarvisPaths.documents.path + "/", with: "") }
            c.records.logStep(runID: runID, index: i, title: command.text, tool: command.intent.rawValue,
                              arguments: command.parameters.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "),
                              result: outcome.detail, status: outcome.success ? .succeeded : .failed,
                              start: stepStart, end: Date(), error: outcome.success ? nil : outcome.detail)
            saveCheckpoint(workflow)
            if workflow.steps.count > 1 { c.currentWorkflow = workflow }
            lastCommand = command
            lastSuccess = outcome.success
            if !outcome.success { break }
        }

        var reply: String
        if errors.isEmpty {
            reply = replies.count <= 2 ? replies.joined(separator: " ") : (replies.last ?? "")
            if replies.count > 2 {
                reply = (language == .korean ? "요청하신 \(replies.count)단계를 모두 마쳤습니다. " : "All \(replies.count) steps are complete, sir. ") + reply
            }
        } else {
            reply = Persona.failurePreamble(language, variant: turnCounter) + " " + (errors.first ?? "")
        }
        if reply.isEmpty { reply = "" }

        var explanations: [Explanation] = []
        if !errors.isEmpty {
            explanations.append(Explanation(kind: .error, text: errors.joined(separator: "\n")))
        }
        if workflow.steps.count > 1 || !errors.isEmpty {
            explanations.append(Explanation(kind: .process, text: workflow.narration(language)))
        }
        let (options, recommendations) = lastCommand.map { optionGenerator.options(after: $0, language: language, success: lastSuccess) } ?? ([], [])

        if !reply.isEmpty {
            c.appendMessage(.assistant, reply, language: language)
            c.records.logMessage(role: "assistant", text: reply, language: language, runID: runID)
            c.speech.speak(reply, language: language)
        }
        if workflow.steps.count > 1 {
            Task { [weak controller = self.c] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                controller?.currentWorkflow = nil
            }
        }
        return AgentTurnResult(reply: reply, language: language, explanations: explanations, options: options,
                               recommendations: recommendations, artifactPaths: artifacts, success: errors.isEmpty)
    }

    private func saveCheckpoint(_ workflow: Workflow) {
        c.records.saveCheckpoint(WorkflowCheckpoint(workflow: workflow, savedAt: Date(), context: ["scene": c.scene.documentJSON]))
    }

    /// Resume a workflow interrupted by an app restart (latest checkpoint).
    func resume(_ interrupted: Workflow) async {
        var workflow = interrupted
        let language = workflow.language
        let runID = c.records.beginRun(commandID: nil, title: "Resume: \(workflow.title)", action: "resume", estimated: nil)
        c.currentRunID = runID
        c.currentWorkflow = workflow
        let result = await runWorkflow(&workflow, runID: runID)
        c.records.logTurn(result, runID: runID)
        c.records.endRun(runID, success: result.success, actual: 0, error: nil)
        c.lastTurn = result
        c.currentRunID = nil
        _ = language
    }

    private func executeConfirmed(_ command: Command, language: DetectedLanguage) async {
        let runID = c.records.beginRun(commandID: nil, title: command.text, action: "confirmed", estimated: nil)
        let outcome = await c.executor.execute(command, language: language, runID: runID)
        let reply = outcome.success
            ? (outcome.spokenOverride ?? Persona.confirmation(for: command, language: language, detail: outcome.detail))
            : Persona.failurePreamble(language) + " " + outcome.detail
        c.records.endRun(runID, success: outcome.success, actual: 0, error: outcome.success ? nil : outcome.detail)
        finish(reply: reply, language: language, runID: runID)
    }

    private func finish(reply: String, language: DetectedLanguage, runID: String?) {
        c.appendMessage(.assistant, reply, language: language)
        c.records.logMessage(role: "assistant", text: reply, language: language, runID: runID)
        c.speech.speak(reply, language: language)
        c.phase = .listening
    }

    // MARK: Language-model path

    private func runLanguageModel(text: String, language: DetectedLanguage, decision: BrainDecision, deep: Bool, runID: String) async -> (AgentTurnResult, Int) {
        let engine: LanguageEngine
        if deep { engine = c.deepThink } else if c.appleFM.isAvailable { engine = c.appleFM } else { engine = c.fallback }
        let charLimit = Int(200 + 900 * decision.cerebellar.verbosity)
        var request = LLMRequest(userText: text, language: language, context: decision.gatedChannels,
                                 withTools: decision.action == .toolUse || decision.topIntent != .smallTalk,
                                 temperature: decision.cerebellar.temperature, maxTokens: decision.cerebellar.maxTokens,
                                 verbosity: decision.cerebellar.verbosity, correction: nil)
        let messageID = c.appendMessage(.assistant, "", language: language, streaming: true)
        var streamed = ""
        let onText: (String) -> Void = { [weak controller = self.c] delta in
            guard let controller else { return }
            streamed += delta
            controller.updateMessage(messageID, text: streamed, streaming: true)
            controller.speech.appendStream(delta, language: language)
        }

        var llm: LLMResult
        do {
            llm = try await engine.respond(request, onText: onText)
        } catch {
            if Task.isCancelled { return (AgentTurnResult(reply: streamed, language: language, success: false), 0) }
            // Fall back to the built-in engine and explain what went wrong.
            let cause = String(describing: error)
            llm = (try? await c.fallback.respond(request, onText: onText)) ?? LLMResult(reply: "", engineName: "none")
            llm.errorExplanation = language == .korean ? "언어 모델 오류: \(cause)" : "Language model error: \(cause)"
        }
        c.speech.finishStream(language: language)

        // Output control: verify → local repair → (if needed) one corrective regeneration.
        var reply = llm.reply.isEmpty ? streamed : llm.reply
        let violations = outputControl.verify(reply, expected: language, toolsSucceeded: llm.toolsSucceeded || llm.toolCalls.isEmpty && !Self.claimsAction(reply),
                                              characterLimit: charLimit, forSpeech: !c.voiceMuted)
        let firstAttemptViolations = violations.count
        if !violations.isEmpty {
            let local = violations.filter { $0.isRepairableLocally }
            let remote = violations.filter { !$0.isRepairableLocally }
            reply = outputControl.repair(reply, violations: local, language: language)
            if !remote.isEmpty, !Task.isCancelled, engine !== c.fallback {
                request.correction = outputControl.correctionInstruction(for: remote, language: language)
                request.context = []
                c.speech.stop()
                if let corrected = try? await engine.respond(request, onText: { _ in }) {
                    let fixed = outputControl.repair(corrected.reply, violations: outputControl.verify(corrected.reply, expected: language,
                                                                                                    toolsSucceeded: corrected.toolsSucceeded,
                                                                                                    characterLimit: charLimit, forSpeech: true).filter { $0.isRepairableLocally },
                                                     language: language)
                    if !fixed.isEmpty {
                        reply = fixed
                        llm.options = corrected.options.isEmpty ? llm.options : corrected.options
                    }
                }
                c.speech.speak(reply, language: language)
            }
        }
        c.updateMessage(messageID, text: reply, streaming: false)
        c.records.logMessage(role: "assistant", text: reply, language: language, runID: runID)

        var explanations: [Explanation] = []
        if !llm.errorExplanation.isEmpty { explanations.append(Explanation(kind: .error, text: llm.errorExplanation)) }
        if !llm.processExplanation.isEmpty || !llm.toolCalls.isEmpty {
            let toolLines = llm.toolCalls.map { "\($0.success ? "✓" : "✗") \($0.name)(\($0.arguments)) — \(String(format: "%.1f", $0.duration))s" }
            let process = ([llm.processExplanation] + toolLines).filter { !$0.isEmpty }.joined(separator: "\n")
            explanations.append(Explanation(kind: .process, text: process))
        }
        if Brain.looksLikeQuestion(text, language: language) {
            explanations.append(Explanation(kind: .answer, text: reply))
        }
        let options = llm.options.prefix(3).map { SuggestedOption(label: $0, utterance: $0) }
        let recommendations = llm.recommendation.isEmpty ? [] : [Recommendation(text: llm.recommendation, utterance: nil)]
        let failed = !llm.errorExplanation.isEmpty || llm.toolCalls.contains { !$0.success } && !llm.toolsSucceeded
        return (AgentTurnResult(reply: reply, language: language, explanations: explanations, options: Array(options),
                                recommendations: recommendations, success: !failed), firstAttemptViolations)
    }

    // MARK: Feedback

    private func deliverPendingFeedback(reaction: String) {
        guard let p = pending else { return }
        pending = nil
        let lower = reaction.lowercased()
        var kind: FeedbackKind = .neutral
        if p.interrupted { kind = .interrupted }
        else if ["no,", "no ", "wrong", "that's not", "not what", "아니", "틀렸", "그게 아니"].contains(where: { lower.hasPrefix($0) || lower.contains($0) }) { kind = .correction }
        else if ["more detail", "explain more", "elaborate", "자세히", "더 설명"].contains(where: { lower.contains($0) }) { kind = .requestedMoreDetail }
        else if ["shorter", "too long", "briefly", "짧게", "간단히", "요약"].contains(where: { lower.contains($0) }) { kind = .requestedBrevity }
        else if ["thank", "great", "perfect", "excellent", "good job", "고마", "감사", "좋아", "완벽", "잘했"].contains(where: { lower.contains($0) }) { kind = .positive }
        c.brain.feedback(BrainOutcome(success: p.success, actualSeconds: p.seconds, feedback: kind,
                                      controlViolations: p.violations, resolvedIntent: p.intent, outputCharacters: p.characters))
    }

    // MARK: Helpers

    static func isAffirmative(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["yes", "yeah", "sure", "do it", "go ahead", "please do", "confirm", "send", "call", "okay", "ok",
                "네", "예", "응", "그래", "좋아", "보내", "해줘", "진행", "확인", "걸어"].contains { t.contains($0) }
    }

    static func isNegative(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["no", "don't", "cancel", "stop", "never mind", "아니", "취소", "하지 마", "그만", "됐어"].contains { t.contains($0) }
    }

    static func claimsAction(_ reply: String) -> Bool {
        let l = reply.lowercased()
        return OutputController.englishCompletionClaims.contains { l.contains($0) } || OutputController.koreanCompletionClaims.contains { reply.contains($0) }
    }
}

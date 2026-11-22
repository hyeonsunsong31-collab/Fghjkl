import Foundation
import FoundationModels

/// Records tool calls made by the language model during one turn.
@MainActor
final class ToolCallLog {
    static let shared = ToolCallLog()
    private(set) var calls: [ToolCallRecord] = []
    func reset() { calls.removeAll() }
    func append(_ call: ToolCallRecord) { calls.append(call) }
}

// MARK: - Tools exposed to the model (kept few and compact: the context window is 4K tokens)
// Their `Arguments` types live in GenerableTypes.swift (written without macros).

struct RunCommandTool: Tool {
    let name = "run_command"
    let description = "Run any built-in Jarvis function from a short command phrase in the user's language, e.g. 'make three red cubes', 'open the 3D space', 'play jazz', 'turn on the flashlight', 'open KakaoTalk', 'set a timer for 5 minutes', '배경화면으로 저장해'."
    func call(arguments: Arguments) async throws -> String {
        await ToolRegistry.shared.invoke("run_command", ["command": arguments.command])
    }
}

struct WebSearchTool: Tool {
    let name = "web_search"
    let description = "Search the web and return the top results (title, link, snippet)."
    func call(arguments: Arguments) async throws -> String {
        await ToolRegistry.shared.invoke("web_search", ["query": arguments.query])
    }
}

struct ReadPageTool: Tool {
    let name = "read_page"
    let description = "Open a web page (or the page currently shown in Jarvis' browser when url is 'current') and return its readable text."
    func call(arguments: Arguments) async throws -> String {
        await ToolRegistry.shared.invoke("read_page", ["url": arguments.url])
    }
}

struct CalendarTool: Tool {
    let name = "calendar"
    let description = "List upcoming calendar events or create an event. Dates use ISO 8601 like 2026-11-21T15:00."
    func call(arguments: Arguments) async throws -> String {
        await ToolRegistry.shared.invoke("calendar", ["action": arguments.action, "title": arguments.title,
                                                       "start": arguments.start, "minutes": String(arguments.minutes)])
    }
}

struct RemindersTool: Tool {
    let name = "reminders"
    let description = "List open reminders or add a reminder with an optional due date (ISO 8601)."
    func call(arguments: Arguments) async throws -> String {
        await ToolRegistry.shared.invoke("reminders", ["action": arguments.action, "title": arguments.title, "due": arguments.due])
    }
}

struct ContactsTool: Tool {
    let name = "contacts"
    let description = "Look up a person in the user's contacts and return their phone numbers and e-mail addresses."
    func call(arguments: Arguments) async throws -> String {
        await ToolRegistry.shared.invoke("contacts", ["name": arguments.name])
    }
}

struct MemoryTool: Tool {
    let name = "memory"
    let description = "Remember a fact about the user for later, or recall stored memories relevant to a query."
    func call(arguments: Arguments) async throws -> String {
        await ToolRegistry.shared.invoke("memory", ["action": arguments.action, "text": arguments.text])
    }
}

struct FilesTool: Tool {
    let name = "files"
    let description = "List, read or write text files in the Jarvis folder of the Files app."
    func call(arguments: Arguments) async throws -> String {
        await ToolRegistry.shared.invoke("files", ["action": arguments.action, "filename": arguments.filename, "content": arguments.content])
    }
}

// MARK: - Engine

/// Apple's on-device foundation model (Apple Intelligence) — fast, private, free.
@MainActor
final class AppleFMEngine: LanguageEngine {
    let name = "Apple Intelligence (on-device)"
    private var warm: LanguageModelSession?
    private var warmLanguage: DetectedLanguage?

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This device does not support Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is turned off in Settings."
            case .modelNotReady: return "The on-device model is still downloading."
            @unknown default: return "The on-device model is unavailable."
            }
        }
    }

    private func tools(_ withTools: Bool) -> [any Tool] {
        guard withTools else { return [RunCommandTool()] }
        return [RunCommandTool(), WebSearchTool(), ReadPageTool(), CalendarTool(), RemindersTool(),
                ContactsTool(), MemoryTool(), FilesTool()]
    }

    private func makeSession(language: DetectedLanguage, withTools: Bool) -> LanguageModelSession {
        LanguageModelSession(model: SystemLanguageModel.default,
                             tools: tools(withTools),
                             instructions: Persona.instructions(language, deviceName: DeviceState.deviceName))
    }

    func prewarm() {
        guard isAvailable else { return }
        let session = makeSession(language: .english, withTools: true)
        session.prewarm()
        warm = session
        warmLanguage = .english
    }

    func respond(_ request: LLMRequest, onText: @escaping (String) -> Void) async throws -> LLMResult {
        ToolCallLog.shared.reset()
        var context = request.context
        var attempt = 0
        while true {
            attempt += 1
            let session: LanguageModelSession
            if let w = warm, warmLanguage == request.language, request.withTools {
                session = w
                warm = nil
            } else {
                session = makeSession(language: request.language, withTools: request.withTools)
            }
            var req = request
            req.context = context
            let options = GenerationOptions(temperature: Double(request.temperature), maximumResponseTokens: request.maxTokens)
            do {
                let stream = session.streamResponse(to: PromptBuilder.prompt(for: req), generating: GeneratedReply.self, options: options)
                var spoken = ""
                var last: GeneratedReply.PartiallyGenerated?
                for try await snapshot in stream {
                    let partial = snapshot.content
                    last = partial
                    if let text = partial.reply, text.count > spoken.count, text.hasPrefix(spoken) {
                        onText(String(text.dropFirst(spoken.count)))
                        spoken = text
                    }
                }
                // Prepare a fresh warm session for the next turn.
                Task { @MainActor [weak self] in self?.prewarmFor(request.language) }
                return LLMResult(reply: last?.reply ?? spoken,
                                 errorExplanation: last?.errorExplanation ?? "",
                                 processExplanation: last?.processExplanation ?? "",
                                 options: (last?.options ?? []).filter { !$0.isEmpty },
                                 recommendation: last?.recommendation ?? "",
                                 toolCalls: ToolCallLog.shared.calls,
                                 engineName: name)
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error, attempt == 1, !context.isEmpty {
                    // Thalamic fallback: halve the admitted context and retry.
                    context = Array(context.prefix(context.count / 2))
                    continue
                }
                throw error
            }
        }
    }

    private func prewarmFor(_ language: DetectedLanguage) {
        guard isAvailable else { return }
        let session = makeSession(language: language, withTools: true)
        session.prewarm()
        warm = session
        warmLanguage = language
    }
}

// MARK: - 3D model design with guided generation

@MainActor
enum AppleFMDesigner {
    static func design(_ description: String, language: DetectedLanguage) async throws -> ModelSpec {
        let session = LanguageModelSession(instructions: """
        You are a 3D modelling assistant. Compose recognisable objects from simple primitives \
        (cube, sphere, cylinder, cone, torus, capsule, pyramid, plane). Use metres; the object should be about 0.5 to 1 metre tall, \
        resting on the floor (y = 0 is the floor). Use between 4 and 20 parts.
        """)
        let response = try await session.respond(to: "Design: \(description)", generating: GeneratedModelSpec.self)
        let spec = response.content
        return ModelSpec(name: spec.name, parts: spec.parts.map {
            ModelSpec.Part(shape: $0.shape, position: SIMD3(Float($0.x), Float($0.y), Float($0.z)),
                           size: SIMD3(Float(max(0.01, $0.width)), Float(max(0.01, $0.height)), Float(max(0.01, $0.depth))),
                           rotationY: Float($0.rotation), color: $0.color)
        })
    }
}

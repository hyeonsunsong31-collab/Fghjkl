import Foundation

/// Entry point for tool calls coming from the language model. Every call is
/// timed and recorded (tool call log → explanations, history, brain feedback).
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()
    weak var controller: JarvisController?

    /// Invoke a tool by name with string arguments; returns text for the model.
    func invoke(_ name: String, _ args: [String: String]) async -> String {
        let start = Date()
        let (success, text) = await execute(name, args)
        let argsText = args.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
        ToolCallLog.shared.append(ToolCallRecord(name: name, arguments: argsText, result: String(text.prefix(500)),
                                                 success: success, duration: Date().timeIntervalSince(start)))
        if let runID = controller?.currentRunID {
            RecordKeeper.shared.logStep(runID: runID, index: ToolCallLog.shared.calls.count, title: name, tool: name,
                                        arguments: argsText, result: String(text.prefix(2000)),
                                        status: success ? .succeeded : .failed, start: start, end: Date(),
                                        error: success ? nil : text)
        }
        return success ? text : "FAILED: \(text)"
    }

    private func execute(_ name: String, _ args: [String: String]) async -> (Bool, String) {
        guard let c = controller else { return (false, "Jarvis is not ready.") }
        switch name {
        case "run_command":
            let phrase = args["command"] ?? ""
            let parsed = CommandGrammar().parse(phrase)
            guard !parsed.isEmpty else { return (false, "No built-in function matches “\(phrase)”.") }
            var lines: [String] = []
            var ok = true
            for command in parsed.commands {
                let outcome = await c.executor.execute(command, language: parsed.language, runID: c.currentRunID)
                ok = ok && outcome.success
                lines.append("\(command.intent.rawValue): \(outcome.success ? "done" : "failed") \(outcome.detail)")
            }
            return (ok, lines.joined(separator: "\n"))
        case "web_search":
            let results = await c.web.search(args["query"] ?? "")
            if results.isEmpty { return (false, "No results (the web may be unreachable).") }
            c.showPanel(.browser)
            return (true, results.enumerated().map { "\($0.offset + 1). \($0.element.title) — \($0.element.url)\n\($0.element.snippet)" }.joined(separator: "\n"))
        case "read_page":
            let text = await c.web.readPage(args["url"])
            return text.isEmpty ? (false, "The page had no readable text.") : (true, text)
        case "calendar":
            return await c.personal.calendar(action: args["action"] ?? "list", title: args["title"] ?? "",
                                             start: args["start"] ?? "", minutes: Int(args["minutes"] ?? "60") ?? 60)
        case "reminders":
            return await c.personal.reminders(action: args["action"] ?? "list", title: args["title"] ?? "", due: args["due"] ?? "")
        case "contacts":
            let matches = await c.personal.lookupContact(args["name"] ?? "")
            if matches.isEmpty { return (false, "No matching contact (or contacts access denied).") }
            return (true, matches.map { "\($0.name): \($0.phones.joined(separator: ", ")) \($0.emails.joined(separator: ", "))" }.joined(separator: "\n"))
        case "memory":
            let text = args["text"] ?? ""
            if args["action"] == "remember" {
                c.brain.remember(text, kind: "fact", importance: 0.8)
                return (true, "Remembered.")
            }
            let recalled = c.brain.recall(text, k: 4).filter { $0.1 > 0.1 }
            return recalled.isEmpty ? (true, "Nothing relevant is stored.") : (true, recalled.map { $0.0.text }.joined(separator: "\n"))
        case "files":
            return c.personal.files(action: args["action"] ?? "list", filename: args["filename"] ?? "",
                                    content: args["content"] ?? "", runID: c.currentRunID)
        default:
            return (false, "Unknown tool \(name).")
        }
    }
}

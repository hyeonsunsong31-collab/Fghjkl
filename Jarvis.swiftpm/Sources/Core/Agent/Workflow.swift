import Foundation

enum StepStatus: String, Codable {
    case pending, running, succeeded, failed, skipped
}

enum WorkflowStatus: String, Codable {
    case planned, running, succeeded, failed, cancelled, interrupted
}

/// One step of an agent workflow.
struct WorkflowStep: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    /// Deterministic command to run (fast path), if any.
    var command: Command?
    /// Natural-language instruction for the language model (agentic path), if any.
    var instruction: String?
    var status: StepStatus = .pending
    var resultSummary: String?
    var error: String?
    var startedAt: Date?
    var finishedAt: Date?

    var duration: TimeInterval? {
        guard let s = startedAt, let f = finishedAt else { return nil }
        return f.timeIntervalSince(s)
    }
}

/// A multi-step task with resumable state. Every state change is checkpointed.
struct Workflow: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var originalRequest: String
    var language: DetectedLanguage
    var createdAt: Date = Date()
    var steps: [WorkflowStep]
    var status: WorkflowStatus = .planned
    var estimatedSeconds: Double?

    var nextPendingIndex: Int? { steps.firstIndex { $0.status == .pending || $0.status == .running } }
    var isFinished: Bool { [.succeeded, .failed, .cancelled].contains(status) }
    var progress: Double {
        guard !steps.isEmpty else { return 1 }
        return Double(steps.filter { $0.status == .succeeded || $0.status == .skipped }.count) / Double(steps.count)
    }

    mutating func start(step i: Int, at date: Date = Date()) {
        guard steps.indices.contains(i) else { return }
        status = .running
        steps[i].status = .running
        steps[i].startedAt = date
    }

    mutating func succeed(step i: Int, summary: String?, at date: Date = Date()) {
        guard steps.indices.contains(i) else { return }
        steps[i].status = .succeeded
        steps[i].resultSummary = summary
        steps[i].finishedAt = date
        if nextPendingIndex == nil { status = steps.contains { $0.status == .failed } ? .failed : .succeeded }
    }

    mutating func fail(step i: Int, error: String, at date: Date = Date()) {
        guard steps.indices.contains(i) else { return }
        steps[i].status = .failed
        steps[i].error = error
        steps[i].finishedAt = date
        status = .failed
    }

    mutating func cancel() {
        for i in steps.indices where steps[i].status == .pending || steps[i].status == .running {
            steps[i].status = .skipped
        }
        status = .cancelled
    }

    /// After an app restart, a step that was running is unknown → retry it.
    mutating func markInterrupted() {
        guard !isFinished else { return }
        for i in steps.indices where steps[i].status == .running { steps[i].status = .pending }
        status = .interrupted
    }

    /// Human-readable process narration (requirement 2-(3)).
    func narration(_ language: DetectedLanguage) -> String {
        var lines: [String] = []
        for (n, s) in steps.enumerated() {
            let mark: String
            switch s.status {
            case .succeeded: mark = "✓"
            case .failed: mark = "✗"
            case .running: mark = "…"
            case .skipped: mark = "–"
            case .pending: mark = "○"
            }
            var line = "\(mark) \(n + 1). \(s.title)"
            if let d = s.duration { line += language == .korean ? String(format: " (%.1f초)", d) : String(format: " (%.1fs)", d) }
            if let e = s.error { line += language == .korean ? " — 오류: \(e)" : " — error: \(e)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

/// Snapshot persisted after every workflow state change (latest checkpoint wins).
struct WorkflowCheckpoint: Codable, Equatable {
    var workflow: Workflow
    var savedAt: Date
    /// Opaque app state needed to resume (e.g. current 3D scene JSON).
    var context: [String: String] = [:]
}

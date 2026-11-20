import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// Records **everything** (requirement 2): tasks run, commands entered, every
/// output (files of any type, conversation text, explanations by purpose,
/// adjustment options, recommendations) and the latest workflow checkpoint.
///
/// Storage: SQLite (queryable, crash-safe WAL) + an append-only JSONL journal
/// per day in `Documents/Jarvis/Logs` (human-readable in the Files app).
final class RecordKeeper: @unchecked Sendable {
    static let shared = RecordKeeper()

    private let queue = DispatchQueue(label: "jarvis.records")
    private var db: SQLiteDatabase?
    let conversationID: String

    struct MessageRecord: Identifiable, Equatable {
        var id: String
        var timestamp: Date
        var role: String
        var text: String
        var language: String
        var runID: String?
    }

    struct RunRecord: Identifiable, Equatable {
        var id: String
        var title: String
        var status: String
        var action: String
        var start: Date
        var end: Date?
        var estimated: Double?
        var actual: Double?
        var error: String?
    }

    struct ArtifactRecord: Identifiable, Equatable {
        var id: String
        var path: String
        var type: String
        var size: Int
        var timestamp: Date
        var description: String
    }

    struct Stats: Equatable {
        var commands = 0, runs = 0, messages = 0, explanations = 0, artifacts = 0
    }

    private init() {
        conversationID = UUID().uuidString
        queue.sync {
            do {
                let database = try SQLiteDatabase(url: JarvisPaths.database)
                try Self.migrate(database)
                db = database
            } catch {
                Log.memory.error("Database unavailable: \(String(describing: error))")
            }
        }
    }

    private static func migrate(_ db: SQLiteDatabase) throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS commands(id TEXT PRIMARY KEY, ts REAL, text TEXT, modality TEXT, language TEXT,
            transcript TEXT, confidence REAL, intent TEXT);
        CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY, command_id TEXT, ts_start REAL, ts_end REAL, title TEXT,
            status TEXT, action TEXT, estimated REAL, actual REAL, error TEXT);
        CREATE TABLE IF NOT EXISTS steps(id TEXT PRIMARY KEY, run_id TEXT, idx INTEGER, title TEXT, tool TEXT, args TEXT,
            result TEXT, status TEXT, ts_start REAL, ts_end REAL, error TEXT);
        CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY, conversation_id TEXT, ts REAL, role TEXT, text TEXT,
            language TEXT, run_id TEXT);
        CREATE TABLE IF NOT EXISTS explanations(id TEXT PRIMARY KEY, run_id TEXT, ts REAL, kind TEXT, text TEXT, language TEXT);
        CREATE TABLE IF NOT EXISTS options(id TEXT PRIMARY KEY, run_id TEXT, ts REAL, label TEXT, utterance TEXT, chosen INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS recommendations(id TEXT PRIMARY KEY, run_id TEXT, ts REAL, text TEXT, utterance TEXT);
        CREATE TABLE IF NOT EXISTS artifacts(id TEXT PRIMARY KEY, run_id TEXT, ts REAL, path TEXT, uti TEXT, size INTEGER,
            sha256 TEXT, description TEXT);
        CREATE TABLE IF NOT EXISTS checkpoints(workflow_id TEXT PRIMARY KEY, ts REAL, finished INTEGER, json TEXT);
        CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT);
        CREATE INDEX IF NOT EXISTS idx_messages_ts ON messages(ts);
        CREATE INDEX IF NOT EXISTS idx_commands_ts ON commands(ts);
        CREATE INDEX IF NOT EXISTS idx_runs_ts ON runs(ts_start);
        """)
    }

    // MARK: Journal

    private func journal(_ type: String, _ payload: [String: Any]) {
        var entry = payload
        entry["type"] = type
        entry["ts"] = ISO8601DateFormatter().string(from: Date())
        guard JSONSerialization.isValidJSONObject(entry),
              let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        let day = Self.dayFormatter.string(from: Date())
        let url = JarvisPaths.logs.appendingPathComponent("\(day).jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data("\n".utf8))
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func write(_ sql: String, _ values: [SQLiteDatabase.Value]) {
        queue.async { [weak self] in
            do { try self?.db?.run(sql, values) } catch { Log.memory.error("DB write failed: \(String(describing: error))") }
        }
    }

    // MARK: Logging API

    @discardableResult
    func logCommand(text: String, modality: InputModality, language: DetectedLanguage, transcript: String?, confidence: Double?, intent: String?) -> String {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        write("INSERT INTO commands VALUES(?,?,?,?,?,?,?,?)",
              [.text(id), .real(now), .text(text), .text(modality.rawValue), .text(language.rawValue),
               .optionalText(transcript), .optionalReal(confidence), .optionalText(intent)])
        journal("command", ["id": id, "text": text, "modality": modality.rawValue, "language": language.rawValue,
                            "intent": intent ?? NSNull(), "confidence": confidence ?? NSNull()])
        return id
    }

    @discardableResult
    func beginRun(commandID: String?, title: String, action: String, estimated: Double?) -> String {
        let id = UUID().uuidString
        write("INSERT INTO runs(id, command_id, ts_start, title, status, action, estimated) VALUES(?,?,?,?,?,?,?)",
              [.text(id), .optionalText(commandID), .real(Date().timeIntervalSince1970), .text(title),
               .text("running"), .text(action), .optionalReal(estimated)])
        journal("run.begin", ["id": id, "title": title, "action": action, "estimated": estimated ?? NSNull()])
        return id
    }

    func endRun(_ id: String, success: Bool, actual: Double, error: String?) {
        write("UPDATE runs SET ts_end=?, status=?, actual=?, error=? WHERE id=?",
              [.real(Date().timeIntervalSince1970), .text(success ? "succeeded" : "failed"), .real(actual), .optionalText(error), .text(id)])
        journal("run.end", ["id": id, "success": success, "actual": actual, "error": error ?? NSNull()])
    }

    func logStep(runID: String, index: Int, title: String, tool: String?, arguments: String?, result: String?,
                 status: StepStatus, start: Date?, end: Date?, error: String?) {
        write("INSERT OR REPLACE INTO steps VALUES(?,?,?,?,?,?,?,?,?,?,?)",
              [.text("\(runID)#\(index)"), .text(runID), .int(Int64(index)), .text(title), .optionalText(tool), .optionalText(arguments),
               .optionalText(result), .text(status.rawValue), .optionalReal(start?.timeIntervalSince1970),
               .optionalReal(end?.timeIntervalSince1970), .optionalText(error)])
        journal("step", ["run": runID, "index": index, "title": title, "tool": tool ?? NSNull(), "status": status.rawValue,
                         "result": result ?? NSNull(), "error": error ?? NSNull()])
    }

    func logMessage(role: String, text: String, language: DetectedLanguage, runID: String?) {
        guard !text.isEmpty else { return }
        write("INSERT INTO messages VALUES(?,?,?,?,?,?,?)",
              [.text(UUID().uuidString), .text(conversationID), .real(Date().timeIntervalSince1970), .text(role), .text(text),
               .text(language.rawValue), .optionalText(runID)])
        journal("message", ["role": role, "text": text, "language": language.rawValue, "run": runID ?? NSNull()])
    }

    func logTurn(_ result: AgentTurnResult, runID: String) {
        let now = Date().timeIntervalSince1970
        for e in result.explanations {
            write("INSERT INTO explanations VALUES(?,?,?,?,?,?)",
                  [.text(UUID().uuidString), .text(runID), .real(now), .text(e.kind.rawValue), .text(e.text), .text(result.language.rawValue)])
            journal("explanation", ["run": runID, "kind": e.kind.rawValue, "text": e.text])
        }
        for o in result.options {
            write("INSERT INTO options(id, run_id, ts, label, utterance) VALUES(?,?,?,?,?)",
                  [.text(o.id), .text(runID), .real(now), .text(o.label), .text(o.utterance)])
            journal("option", ["run": runID, "label": o.label, "utterance": o.utterance])
        }
        for r in result.recommendations {
            write("INSERT INTO recommendations VALUES(?,?,?,?,?)",
                  [.text(r.id), .text(runID), .real(now), .text(r.text), .optionalText(r.utterance)])
            journal("recommendation", ["run": runID, "text": r.text])
        }
    }

    func markOptionChosen(_ optionID: String) {
        write("UPDATE options SET chosen=1 WHERE id=?", [.text(optionID)])
    }

    /// Store any generated file and record it (requirement 2: files of all types).
    @discardableResult
    func saveArtifact(data: Data, filename: String, runID: String?, description: String) -> URL? {
        let day = Self.dayFormatter.string(from: Date())
        let dir = JarvisPaths.ensure(JarvisPaths.artifacts.appendingPathComponent(day).appendingPathComponent(runID ?? "manual"))
        let url = dir.appendingPathComponent(filename)
        do { try data.write(to: url, options: .atomic) } catch {
            Log.memory.error("Artifact write failed: \(error.localizedDescription)")
            return nil
        }
        registerArtifact(at: url, runID: runID, description: description)
        return url
    }

    /// Record a file that was written elsewhere (exports, downloads, snapshots).
    func registerArtifact(at url: URL, runID: String?, description: String) {
        let data = (try? Data(contentsOf: url, options: .mappedIfSafe)) ?? Data()
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let uti = UTType(filenameExtension: url.pathExtension)?.identifier ?? "public.data"
        let rel = url.path.replacingOccurrences(of: JarvisPaths.documents.path + "/", with: "")
        write("INSERT INTO artifacts VALUES(?,?,?,?,?,?,?,?)",
              [.text(UUID().uuidString), .optionalText(runID), .real(Date().timeIntervalSince1970), .text(rel), .text(uti),
               .int(Int64(data.count)), .text(sha), .text(description)])
        journal("artifact", ["path": rel, "uti": uti, "size": data.count, "sha256": sha, "description": description])
    }

    // MARK: Checkpoints

    func saveCheckpoint(_ checkpoint: WorkflowCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint), let json = String(data: data, encoding: .utf8) else { return }
        write("INSERT OR REPLACE INTO checkpoints VALUES(?,?,?,?)",
              [.text(checkpoint.workflow.id), .real(checkpoint.savedAt.timeIntervalSince1970),
               .int(checkpoint.workflow.isFinished ? 1 : 0), .text(json)])
        journal("checkpoint", ["workflow": checkpoint.workflow.id, "status": checkpoint.workflow.status.rawValue,
                               "progress": checkpoint.workflow.progress])
    }

    func latestUnfinishedCheckpoint() -> WorkflowCheckpoint? {
        queue.sync {
            guard let rows = try? db?.query("SELECT json FROM checkpoints WHERE finished=0 ORDER BY ts DESC LIMIT 1"),
                  let json = rows.first?.string("json"), let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(WorkflowCheckpoint.self, from: data)
        }
    }

    // MARK: Queries

    func recentMessages(limit: Int = 30, search: String? = nil) -> [MessageRecord] {
        queue.sync {
            let sql: String
            var values: [SQLiteDatabase.Value] = []
            if let s = search, !s.isEmpty {
                sql = "SELECT * FROM messages WHERE text LIKE ? ORDER BY ts DESC LIMIT ?"
                values = [.text("%\(s)%"), .int(Int64(limit))]
            } else {
                sql = "SELECT * FROM messages ORDER BY ts DESC LIMIT ?"
                values = [.int(Int64(limit))]
            }
            let rows = (try? db?.query(sql, values)) ?? []
            return rows.compactMap { r in
                guard let id = r.string("id"), let ts = r.double("ts") else { return nil }
                return MessageRecord(id: id, timestamp: Date(timeIntervalSince1970: ts), role: r.string("role") ?? "",
                                     text: r.string("text") ?? "", language: r.string("language") ?? "en", runID: r.string("run_id"))
            }
        }
    }

    func recentRuns(limit: Int = 50) -> [RunRecord] {
        queue.sync {
            let rows = (try? db?.query("SELECT * FROM runs ORDER BY ts_start DESC LIMIT ?", [.int(Int64(limit))])) ?? []
            return rows.compactMap { r in
                guard let id = r.string("id"), let start = r.double("ts_start") else { return nil }
                return RunRecord(id: id, title: r.string("title") ?? "", status: r.string("status") ?? "",
                                 action: r.string("action") ?? "", start: Date(timeIntervalSince1970: start),
                                 end: r.double("ts_end").map { Date(timeIntervalSince1970: $0) },
                                 estimated: r.double("estimated"), actual: r.double("actual"), error: r.string("error"))
            }
        }
    }

    func explanations(for runID: String) -> [Explanation] {
        queue.sync {
            let rows = (try? db?.query("SELECT kind, text FROM explanations WHERE run_id=? ORDER BY ts", [.text(runID)])) ?? []
            return rows.compactMap { r in
                guard let k = r.string("kind").flatMap(ExplanationKind.init(rawValue:)), let t = r.string("text") else { return nil }
                return Explanation(kind: k, text: t)
            }
        }
    }

    func recentArtifacts(limit: Int = 50) -> [ArtifactRecord] {
        queue.sync {
            let rows = (try? db?.query("SELECT * FROM artifacts ORDER BY ts DESC LIMIT ?", [.int(Int64(limit))])) ?? []
            return rows.compactMap { r in
                guard let id = r.string("id"), let path = r.string("path") else { return nil }
                return ArtifactRecord(id: id, path: path, type: r.string("uti") ?? "", size: r.int("size") ?? 0,
                                      timestamp: Date(timeIntervalSince1970: r.double("ts") ?? 0), description: r.string("description") ?? "")
            }
        }
    }

    func stats() -> Stats {
        queue.sync {
            func count(_ table: String) -> Int {
                (try? db?.query("SELECT COUNT(*) AS n FROM \(table)"))?.first?.int("n") ?? 0
            }
            return Stats(commands: count("commands"), runs: count("runs"), messages: count("messages"),
                         explanations: count("explanations"), artifacts: count("artifacts"))
        }
    }

    // MARK: Settings (key–value)

    func setting(_ key: String) -> String? {
        queue.sync { (try? db?.query("SELECT value FROM kv WHERE key=?", [.text(key)]))?.first?.string("value") }
    }

    func setSetting(_ key: String, _ value: String) {
        write("INSERT OR REPLACE INTO kv VALUES(?,?)", [.text(key), .text(value)])
    }

    /// Export the whole conversation history as a Markdown file (an artefact itself).
    func exportTranscript() -> URL? {
        let messages = recentMessages(limit: 10_000).reversed()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var md = "# Jarvis transcript\n\n"
        for m in messages { md += "**\(m.role)** · \(df.string(from: m.timestamp))\n\n\(m.text)\n\n" }
        let name = "transcript-\(Self.dayFormatter.string(from: Date())).md"
        let url = JarvisPaths.exports.appendingPathComponent(name)
        do { try md.data(using: .utf8)?.write(to: url, options: .atomic) } catch { return nil }
        registerArtifact(at: url, runID: nil, description: "Conversation transcript export")
        return url
    }
}

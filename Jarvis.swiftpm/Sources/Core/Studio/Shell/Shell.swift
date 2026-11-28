import Foundation

struct ShellOutput: Equatable {
    var stdout: [UInt8] = []
    var stderr = ""
    var status: Int32 = 0

    var text: String { String(decoding: stdout, as: UTF8.self) }
    /// Everything the user should see, stdout then stderr.
    var combined: String {
        let out = text
        if stderr.isEmpty { return out }
        return out.isEmpty ? stderr : (out.hasSuffix("\n") ? out : out + "\n") + stderr
    }

    static func ok(_ s: String = "") -> ShellOutput {
        ShellOutput(stdout: Array((s.isEmpty || s.hasSuffix("\n") ? s : s + "\n").utf8))
    }
    static func bytes(_ b: [UInt8]) -> ShellOutput { ShellOutput(stdout: b) }
    static func fail(_ s: String, _ code: Int32 = 1) -> ShellOutput { ShellOutput(stderr: s.hasSuffix("\n") ? s : s + "\n", status: code) }

    /// Marker the terminal view treats as "clear the screen".
    static let clearMarker = "\u{1B}[2J"
}

/// Features the app provides to the terminal (web runtime, Python, sharing, the coding agent, network).
protocol ShellHost: AnyObject {
    /// kind: "js", "python", "preview", "serve", "verify", "share", "open", "edit".
    func perform(_ kind: String, path: String, args: [String], shell: Shell, stdin: [UInt8]) async -> ShellOutput?
    /// Run the coding agent on the current workspace.
    func agent(_ request: String, shell: Shell) async -> ShellOutput?
    /// Download (user-initiated: lib add, fetch, git clone).
    func fetch(_ url: URL) async throws -> (data: Data, mime: String?)
}

/// A shell for one workspace: a familiar command line over a sandboxed file tree.
/// iOS lets apps run no foreign executables, so every command is built in; programs run
/// in the app's runtimes (JavaScript and web pages in WebKit, Python through Pyodide).
final class Shell {
    var fs: SandboxFS
    let store: WorkspaceStore?
    var workspaceID: String
    var cwd = "/"
    var env: [String: String]
    private(set) var history: [String] = []
    var lastStatus: Int32 = 0
    weak var host: ShellHost?

    init(fs: SandboxFS, store: WorkspaceStore? = nil, workspaceID: String = "", host: ShellHost? = nil) {
        self.fs = fs
        self.store = store
        self.workspaceID = workspaceID
        self.host = host
        env = ["HOME": "/", "USER": "jarvis", "SHELL": "jsh", "PATH": "(built-in)", "LANG": "en_GB.UTF-8"]
    }

    var prompt: String {
        let name = store?.workspace(workspaceID)?.name ?? "jarvis"
        return "\(name):\(cwd)$ "
    }

    /// Switch to another workspace's files.
    func attach(workspaceID id: String, fs newFS: SandboxFS) {
        workspaceID = id
        fs = newFS
        cwd = "/"
    }

    // MARK: Running a command line

    func run(_ line: String) async -> ShellOutput {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return ShellOutput() }
        history.append(trimmed)
        if history.count > 500 { history.removeFirst(history.count - 500) }
        let tokens: [ShellToken]
        do { tokens = try ShellLexer.tokenize(trimmed) } catch {
            lastStatus = 2
            return .fail("jsh: \(error)", 2)
        }
        var combined = ShellOutput()
        var connector = ";"
        for (pipeline, next) in ShellLexer.sequence(tokens) {
            let shouldRun = connector == ";" || (connector == "&&" && lastStatus == 0) || (connector == "||" && lastStatus != 0)
            if shouldRun {
                let out = await runPipeline(pipeline)
                combined.stdout += out.stdout
                combined.stderr += out.stderr
                combined.status = out.status
                lastStatus = out.status
            }
            connector = next
        }
        return combined
    }

    /// Run a script (one command per line; `#` comments).
    func runScript(_ text: String) async -> ShellOutput {
        var all = ShellOutput()
        for line in text.components(separatedBy: .newlines) {
            let out = await run(line)
            all.stdout += out.stdout
            all.stderr += out.stderr
            all.status = out.status
        }
        return all
    }

    private func runPipeline(_ commands: [[ShellToken]]) async -> ShellOutput {
        var input: [UInt8] = []
        var errors = ""
        var last = ShellOutput()
        for (index, tokens) in commands.enumerated() {
            var words: [String] = []
            var redirects: [(String, String)] = []
            var i = 0
            while i < tokens.count {
                switch tokens[i] {
                case .op(let op) where [">", ">>", "<", "2>", "&>"].contains(op):
                    if i + 1 < tokens.count, case .word(let target, _) = tokens[i + 1] { redirects.append((op, expand(target))); i += 2; continue }
                    return .fail("jsh: missing file name after \(op)", 2)
                case .op("2>&1"):
                    redirects.append(("2>&1", ""))
                case .word(let raw, let glob):
                    let w = expand(raw)
                    if glob, w.contains("*") || w.contains("?") || w.contains("[") { words += expandGlob(w) } else { words.append(w) }
                default:
                    break
                }
                i += 1
            }
            for (op, target) in redirects where op == "<" {
                do { input = try fs.read(target, cwd: cwd) } catch { return .fail("jsh: \(error)") }
            }
            guard let name = words.first else { continue }
            // Variable assignment: NAME=value
            if words.count == 1, let eq = name.firstIndex(of: "="), name[..<eq].allSatisfy({ $0.isLetter || $0 == "_" || $0.isNumber }), !name.hasPrefix("=") {
                env[String(name[..<eq])] = String(name[name.index(after: eq)...])
                last = ShellOutput()
                continue
            }
            var out = await execute(name, Array(words.dropFirst()), stdin: index == 0 ? input : last.stdout)
            var merged = false
            for (op, target) in redirects {
                do {
                    switch op {
                    case ">": try fs.write(target, out.stdout, cwd: cwd); out.stdout = []
                    case ">>": try fs.append(target, out.stdout, cwd: cwd); out.stdout = []
                    case "2>": try fs.write(target, Array(out.stderr.utf8), cwd: cwd); out.stderr = ""
                    case "&>": try fs.write(target, out.stdout + Array(out.stderr.utf8), cwd: cwd); out.stdout = []; out.stderr = ""
                    case "2>&1": merged = true
                    default: break
                    }
                } catch {
                    return .fail("jsh: \(error)")
                }
            }
            if merged { out.stdout += Array(out.stderr.utf8); out.stderr = "" }
            errors += out.stderr
            last = out
            input = out.stdout
        }
        last.stderr = errors
        return last
    }

    /// Replace variable placeholders with their current values.
    func expand(_ word: String) -> String {
        guard word.contains(ShellLexer.varStart) else { return word }
        var out = ""
        var name: String?
        for ch in word {
            if ch == ShellLexer.varStart { name = ""; continue }
            if ch == ShellLexer.varEnd, let n = name {
                out += n == "?" ? String(lastStatus) : (env[n] ?? "")
                name = nil
                continue
            }
            if name != nil { name!.append(ch) } else { out.append(ch) }
        }
        return out
    }

    private func expandGlob(_ pattern: String) -> [String] {
        let dir = (pattern as NSString).deletingLastPathComponent
        let base = (pattern as NSString).lastPathComponent
        let listDir = dir.isEmpty ? "." : dir
        guard let entries = try? fs.list(listDir, cwd: cwd, hidden: base.hasPrefix(".")) else { return [pattern] }
        let matches = entries.map(\.name).filter { SandboxFS.glob(base, $0) }.sorted()
        if matches.isEmpty { return [pattern] }
        return matches.map { dir.isEmpty ? $0 : dir + "/" + $0 }
    }

    // MARK: Helpers for commands

    func path(_ p: String) -> String { SandboxFS.normalize(p, cwd: cwd) }

    func readText(_ p: String) throws -> String { try fs.readText(p, cwd: cwd) }

    func readBytes(_ p: String) throws -> [UInt8] { try fs.read(p, cwd: cwd) }

    /// Text from the named files, or from standard input when there are none.
    func inputText(_ files: [String], _ stdin: [UInt8]) throws -> String {
        if files.isEmpty { return String(decoding: stdin, as: UTF8.self) }
        return try files.map { try readText($0) }.joined()
    }
}

// MARK: - Lexing

enum ShellToken: Equatable {
    case word(String, glob: Bool)
    case op(String)
}

enum ShellLexer {
    struct LexError: Error, CustomStringConvertible { var description: String }

    /// Variables are left as placeholders and expanded when each command runs (so `X=1; echo $X` works).
    static let varStart: Character = "\u{1}"
    static let varEnd: Character = "\u{2}"

    static func tokenize(_ line: String, env: [String: String] = [:], lastStatus: Int32 = 0) throws -> [ShellToken] {
        var tokens: [ShellToken] = []
        let s = Array(line)
        var i = 0
        var word = ""
        var inWord = false
        var globbable = true
        func flush() {
            if inWord { tokens.append(.word(word, glob: globbable)) }
            word = ""
            inWord = false
            globbable = true
        }
        func placeholder(_ name: String) -> String { String(varStart) + name + String(varEnd) }
        func variable(_ start: Int) -> (String, Int) {
            var j = start
            if j < s.count && s[j] == "?" { return (placeholder("?"), j + 1) }
            if j < s.count && s[j] == "{" {
                guard let close = s[j...].firstIndex(of: "}") else { return ("$", start) }
                return (placeholder(String(s[(j + 1)..<close])), close + 1)
            }
            while j < s.count && (s[j].isLetter || s[j].isNumber || s[j] == "_") { j += 1 }
            if j == start { return ("$", start) }
            return (placeholder(String(s[start..<j])), j)
        }
        while i < s.count {
            let c = s[i]
            if c == " " || c == "\t" { flush(); i += 1; continue }
            if c == "'" {
                guard let close = s[(i + 1)...].firstIndex(of: "'") else { throw LexError(description: "unterminated single quote") }
                word += String(s[(i + 1)..<close])
                inWord = true
                globbable = false
                i = close + 1
                continue
            }
            if c == "\"" {
                var j = i + 1
                inWord = true
                globbable = false
                while j < s.count && s[j] != "\"" {
                    if s[j] == "\\" && j + 1 < s.count && "\"\\$`".contains(s[j + 1]) { word.append(s[j + 1]); j += 2; continue }
                    if s[j] == "$" {
                        let (value, next) = variable(j + 1)
                        word += value
                        j = next
                        continue
                    }
                    word.append(s[j])
                    j += 1
                }
                guard j < s.count else { throw LexError(description: "unterminated double quote") }
                i = j + 1
                continue
            }
            if c == "\\" && i + 1 < s.count { word.append(s[i + 1]); inWord = true; i += 2; continue }
            if c == "$" {
                let (value, next) = variable(i + 1)
                word += value
                inWord = true
                i = next
                continue
            }
            // Operators.
            let rest = String(s[i..<Swift.min(s.count, i + 4)])
            if let op = ["2>&1", "&&", "||", ">>", "2>", "&>", "|", ";", ">", "<"].first(where: { rest.hasPrefix($0) }) {
                // "2>" only as an operator when it starts a word.
                if (op == "2>" || op == "2>&1") && inWord { word.append(c); i += 1; continue }
                flush()
                tokens.append(.op(op))
                i += op.count
                continue
            }
            if c == "#" && !inWord { break }
            word.append(c)
            inWord = true
            i += 1
        }
        flush()
        return tokens
    }

    /// Split into pipelines joined by ;, && and ||; each pipeline is a list of commands joined by |.
    static func sequence(_ tokens: [ShellToken]) -> [([[ShellToken]], String)] {
        var out: [([[ShellToken]], String)] = []
        var pipeline: [[ShellToken]] = []
        var command: [ShellToken] = []
        for t in tokens {
            if case .op(let op) = t {
                if op == "|" { pipeline.append(command); command = []; continue }
                if op == ";" || op == "&&" || op == "||" {
                    pipeline.append(command)
                    out.append((pipeline, op))
                    pipeline = []
                    command = []
                    continue
                }
            }
            command.append(t)
        }
        if !command.isEmpty || !pipeline.isEmpty {
            pipeline.append(command)
            out.append((pipeline, ";"))
        }
        return out.filter { !$0.0.allSatisfy { $0.isEmpty } }
    }
}

/// Command-line flags: -la, -n 10, -n10, --name value, --flag.
struct ShellFlags {
    var flags: Set<String> = []
    var values: [String: String] = [:]
    var positional: [String] = []

    init(_ args: [String], valued: Set<String> = []) {
        var i = 0
        var onlyPositional = false
        while i < args.count {
            let a = args[i]
            if onlyPositional || a == "-" || !a.hasPrefix("-") || Double(a) != nil {
                positional.append(a)
            } else if a == "--" {
                onlyPositional = true
            } else if a.hasPrefix("--") {
                let body = String(a.dropFirst(2))
                if let eq = body.firstIndex(of: "=") {
                    values[String(body[..<eq])] = String(body[body.index(after: eq)...])
                } else if valued.contains(body), i + 1 < args.count {
                    values[body] = args[i + 1]
                    i += 1
                } else {
                    flags.insert(body)
                }
            } else {
                let body = Array(a.dropFirst())
                var k = 0
                while k < body.count {
                    let f = String(body[k])
                    if valued.contains(f) {
                        let rest = String(body[(k + 1)...])
                        if !rest.isEmpty { values[f] = rest } else if i + 1 < args.count { values[f] = args[i + 1]; i += 1 }
                        break
                    }
                    flags.insert(f)
                    k += 1
                }
            }
            i += 1
        }
    }

    func has(_ f: String) -> Bool { flags.contains(f) }
    func int(_ f: String, _ fallback: Int) -> Int { values[f].flatMap { Int($0) } ?? fallback }
}

import Foundation

/// Built-in commands of the Jarvis shell.
extension Shell {
    static let commandHelp: [(group: String, commands: [(String, String)])] = [
        ("Files", [("ls [-la] [path]", "list files"), ("tree [path]", "folder tree"), ("cd / pwd", "change / show folder"),
                   ("cat, head, tail [-n N]", "show files"), ("touch, mkdir [-p]", "create"), ("cp [-r], mv, rm [-r]", "copy, move, delete"),
                   ("find [path] -name '*.js'", "search names"), ("stat path", "size and date"), ("tee file, write file", "save input")]),
        ("Text", [("grep [-inrvcl] pattern [paths]", "search text"), ("sed 's/a/b/g' [-i] file", "edit with regex"),
                  ("replace 'old' 'new' files", "replace text"), ("diff a b", "unified diff"), ("patch [file] < diff", "apply a diff"),
                  ("sort [-rnu], uniq [-c], wc [-lwc]", "text tools"), ("echo, printf", "print")]),
        ("Binaries & ROMs", [("file path", "what is it"), ("inspect path", "full report (exe, dll, elf, rom, zip…)"),
                             ("hexdump [-s off] [-n len] path", "hex view"), ("strings [-n 5] path", "printable text"),
                             ("hexpatch path offset hex", "write bytes"), ("binreplace path 'from' 'to' [--utf16]", "same-length replace"),
                             ("compare a b", "byte differences"), ("ips|bps|ups apply patch rom [out]", "apply a ROM patch"),
                             ("ips|bps|ups create original modified out", "make a patch"), ("romfix rom, romtitle rom 'TITLE'", "ROM header")]),
        ("Archives & formats", [("zip out.zip paths", "compress"), ("unzip [-l] file [-d dir]", "extract (also .exe installers)"),
                                ("tar -czf / -xzf / -tf", "tar archives"), ("gzip, gunzip", "gzip"),
                                ("convert in out | --to ext", "convert between formats"),
                                ("pack exe|app|sh|html|zip [path] [--open file]", "make a program or package"),
                                ("sha256, crc32, base64 [-d]", "checksums")]),
        ("Run", [("run path", "run by type (.js .html .py .sh .json)"), ("node file.js, python file.py, sh script.sh", "runtimes"),
                 ("preview [index.html]", "open in the web view"), ("verify [path]", "check it works (errors, liveness)"),
                 ("serve [folder]", "local web link"), ("share paths", "send files"), ("lib add three", "cache a JS library"),
                 ("fetch url [out]", "download"), ("git clone url", "download a GitHub repo")]),
        ("Workspace", [("ws [list|new|use|rename|rm|info]", "workspace slots"), ("versions [list|save|restore N|diff N]", "history"),
                       ("git status|log|diff|commit -m", "versions, git style"), ("queue [list|add|run|clear]", "stacked requests"),
                       ("ai <request>", "build or change the product"), ("fix [path]", "find and repair errors"), ("explain path", "explain code")]),
        ("Shell", [("env, export K=V, unset K", "variables"), ("history, clear", "session"), ("date, whoami, uname, which", "info")]),
    ]

    static let builtins: Set<String> = [
        "help", "ls", "dir", "tree", "cd", "pwd", "cat", "head", "tail", "touch", "mkdir", "cp", "mv", "rm", "rmdir", "find", "stat",
        "tee", "write", "grep", "sed", "replace", "diff", "patch", "sort", "uniq", "wc", "echo", "printf", "file", "inspect", "rominfo",
        "hexdump", "xxd", "strings", "hexpatch", "binreplace", "compare", "cmp", "ips", "bps", "ups", "romfix", "romtitle", "zip", "unzip",
        "tar", "gzip", "gunzip", "convert", "pack", "sha256", "sha256sum", "crc32", "base64", "run", "node", "js", "python", "python3", "sh",
        "bash", "preview", "open", "edit", "verify", "test", "serve", "share", "lib", "fetch", "curl", "wget", "git", "ws", "workspace",
        "versions", "queue", "ai", "fix", "explain", "build", "env", "export", "unset", "history", "clear", "date", "whoami", "uname",
        "which", "true", "false", "exit", "chmod", "du",
    ]

    static let nativeTools: [String: String] = [
        "npm": "npm can't run on iOS. For browser libraries use `lib add <package>` (cached from jsDelivr, then offline).",
        "npx": "npx can't run on iOS. Use `lib add <package>` for browser libraries.",
        "yarn": "yarn can't run on iOS. Use `lib add <package>`.", "pnpm": "pnpm can't run on iOS. Use `lib add <package>`.",
        "pip": "pip can't run natively. Python runs in Pyodide: pure-Python packages install from inside Python with micropip when online.",
        "pip3": "pip can't run natively. Python runs in Pyodide: use micropip inside Python when online.",
        "gcc": "iOS forbids apps from compiling and running native code. I can still write C/C++ and package it for you to build on a PC, or rebuild the program in JavaScript/Python, which run here.",
        "g++": "iOS forbids apps from compiling and running native code. I can write the C++ for a PC build, or port it to a language that runs here.",
        "clang": "iOS forbids apps from compiling and running native code. I can write the code for a PC build, or port it to JavaScript/Python.",
        "cc": "iOS forbids native compilation inside apps.", "make": "No native build tools on iOS; `pack` and `ai` build web and Python products here.",
        "cmake": "No native build tools on iOS.", "cargo": "Rust can't compile inside an iOS app; I can write it for a PC build or port it.",
        "rustc": "Rust can't compile inside an iOS app.", "go": "Go can't compile inside an iOS app; I can write it for a PC build or port it.",
        "java": "No Java VM is allowed in iOS apps; I can port the program or write it for a PC build.", "javac": "No Java compiler on iOS.",
        "dotnet": ".NET can't run inside an iOS app.", "mono": ".NET can't run inside an iOS app.",
        "wine": "Windows programs can't run on iOS (no foreign executables). `inspect` analyses them; `ai` can rebuild their features.",
        "apt": "There is no package manager inside iOS apps; everything Jarvis needs is built in.", "apt-get": "No package manager inside iOS apps.",
        "brew": "No package manager inside iOS apps.", "sudo": "There is no root access on iOS, and none is needed in your workspace.",
        "docker": "Containers can't run on iOS.", "ssh": "SSH isn't available in the workspace shell.", "scp": "SSH isn't available in the workspace shell.",
        "ps": "Apps on iOS can't list or start processes; the workspace runs everything in the app's own runtimes.",
        "kill": "Apps on iOS can't manage processes.", "top": "Apps on iOS can't see other processes.",
        "vim": "Use `edit <file>` to open the editor, or ask me to change the file.", "nano": "Use `edit <file>` to open the editor.",
    ]

    func execute(_ name: String, _ args: [String], stdin: [UInt8]) async -> ShellOutput {
        do {
            switch name {
            case "help": return help(args)
            case "ls", "dir": return try ls(args)
            case "tree": return try tree(args)
            case "cd": return try cd(args)
            case "pwd": return .ok(cwd)
            case "cat": return try cat(args, stdin)
            case "head", "tail": return try headTail(name == "head", args, stdin)
            case "touch": return try touch(args)
            case "mkdir": return try mkdir(args)
            case "cp": return try cp(args)
            case "mv": return try mv(args)
            case "rm", "rmdir": return try rm(args)
            case "find": return find(args)
            case "stat": return try stat(args)
            case "du": return .ok(ByteCountFormatter.string(fromByteCount: Int64(fs.totalSize), countStyle: .file) + "\t" + cwd)
            case "tee", "write": return try tee(args, stdin)
            case "grep": return try grep(args, stdin)
            case "sed": return try sed(args, stdin)
            case "replace": return try replace(args)
            case "diff": return try diff(args)
            case "patch": return try patch(args, stdin)
            case "sort": return try sort(args, stdin)
            case "uniq": return try uniq(args, stdin)
            case "wc": return try wc(args, stdin)
            case "echo": return echo(args)
            case "printf": return printf(args)
            case "file": return try file(args)
            case "inspect", "rominfo": return try inspect(args)
            case "hexdump", "xxd": return try hexdump(args)
            case "strings": return try strings(args)
            case "hexpatch": return try hexpatch(args)
            case "binreplace": return try binreplace(args)
            case "compare", "cmp": return try compare(args)
            case "ips", "bps", "ups": return try romPatch(name, args)
            case "romfix": return try romfix(args)
            case "romtitle": return try romtitle(args)
            case "zip": return try zip(args)
            case "unzip": return try unzip(args)
            case "tar": return try tar(args)
            case "gzip": return try gzip(args)
            case "gunzip": return try gunzip(args)
            case "convert": return try await convert(args)
            case "pack": return try pack(args)
            case "sha256", "sha256sum", "crc32": return try checksum(name, args, stdin)
            case "base64": return try base64(args, stdin)
            case "run": return try await runFile(args, stdin)
            case "node", "js": return try await runtime("js", args, stdin)
            case "python", "python3": return try await runtime("python", args, stdin)
            case "sh", "bash": return try await shellScript(args)
            case "preview", "open", "edit", "verify", "test", "serve", "share": return await hostAction(name, args, stdin)
            case "lib": return try await lib(args)
            case "fetch", "curl", "wget": return try await fetch(args)
            case "git": return try await git(args)
            case "ws", "workspace": return ws(args)
            case "versions": return try versions(args)
            case "queue": return queue(args)
            case "ai", "build", "fix", "explain": return await agent(name, args)
            case "env": return .ok(env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
            case "export":
                for a in args { if let eq = a.firstIndex(of: "=") { env[String(a[..<eq])] = String(a[a.index(after: eq)...]) } }
                return ShellOutput()
            case "unset":
                for a in args { env[a] = nil }
                return ShellOutput()
            case "history": return .ok(history.enumerated().map { String(format: "%5d  %@", $0.offset + 1, $0.element) }.joined(separator: "\n"))
            case "clear": return ShellOutput(stdout: Array(ShellOutput.clearMarker.utf8))
            case "date": return .ok(ISO8601DateFormatter().string(from: Date()))
            case "whoami": return .ok("jarvis")
            case "uname": return .ok(args.contains("-a") ? "Jarvis jsh 1.0 (iPadOS/iOS sandbox, built-in commands, WebKit + Pyodide runtimes)" : "Jarvis")
            case "which": return .ok(args.map { Self.builtins.contains($0) ? "\($0): built-in" : "\($0): not available" }.joined(separator: "\n"))
            case "true", "exit": return ShellOutput()
            case "false": return ShellOutput(status: 1)
            case "chmod": return .ok("(permissions don't apply inside the workspace; `pack` marks scripts executable)")
            default:
                if let reason = Self.nativeTools[name] { return .fail("\(name): \(reason)", 127) }
                if fs.exists(name, cwd: cwd) { return try await runFile([name] + args, stdin) }
                return .fail("\(name): command not found (type `help`)", 127)
            }
        } catch {
            return .fail("\(name): \(error)")
        }
    }

    private func help(_ args: [String]) -> ShellOutput {
        if let topic = args.first {
            for group in Self.commandHelp {
                for (usage, what) in group.commands where usage.split(separator: " ").first.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: ",")) == topic || usage.contains(topic + " ") || usage.hasPrefix(topic) {
                    return .ok("\(usage)\n  \(what)")
                }
            }
            if let native = Self.nativeTools[topic] { return .ok(native) }
            return .fail("help: no command named \(topic)")
        }
        var lines = ["Jarvis shell — every command runs inside this workspace (type `help <command>`).", ""]
        for group in Self.commandHelp {
            lines.append("[\(group.group)]")
            for (usage, what) in group.commands {
                let pad = usage.count < 44 ? String(repeating: " ", count: 44 - usage.count) : "  "
                lines.append("  \(usage)\(pad)\(what)")
            }
        }
        return .ok(lines.joined(separator: "\n"))
    }

    // MARK: Files

    private func ls(_ args: [String]) throws -> ShellOutput {
        let f = ShellFlags(args)
        let long = f.has("l"), all = f.has("a")
        let targets = f.positional.isEmpty ? ["."] : f.positional
        var lines: [String] = []
        for t in targets {
            let entries = try fs.list(t, cwd: cwd, hidden: all)
            if targets.count > 1 { lines.append("\(t):") }
            if long {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                for e in entries {
                    let size = e.isDirectory ? "-" : ByteCountFormatter.string(fromByteCount: Int64(e.size), countStyle: .file)
                    let padded = String(repeating: " ", count: Swift.max(0, 10 - size.count)) + size
                    lines.append("\(e.isDirectory ? "d" : "-")  \(padded)  \(formatter.string(from: e.modified))  \(e.name)\(e.isDirectory ? "/" : "")")
                }
            } else {
                lines.append(entries.map { $0.name + ($0.isDirectory ? "/" : "") }.joined(separator: "  "))
            }
        }
        return .ok(lines.joined(separator: "\n"))
    }

    private func tree(_ args: [String]) throws -> ShellOutput {
        let start = args.first ?? "."
        var lines = [path(start)]
        var count = 0
        func walk(_ p: String, _ prefix: String) throws {
            let entries = try fs.list(p, cwd: cwd)
            for (i, e) in entries.enumerated() {
                count += 1
                if count > 800 { return }
                let last = i == entries.count - 1
                lines.append(prefix + (last ? "└── " : "├── ") + e.name + (e.isDirectory ? "/" : ""))
                if e.isDirectory { try walk(e.path, prefix + (last ? "    " : "│   ")) }
            }
        }
        try walk(start, "")
        return .ok(lines.joined(separator: "\n"))
    }

    private func cd(_ args: [String]) throws -> ShellOutput {
        let target = path(args.first ?? "/")
        guard fs.isDirectory(target) else { return .fail("cd: \(args.first ?? ""): not a folder") }
        cwd = target
        return ShellOutput()
    }

    private func cat(_ args: [String], _ stdin: [UInt8]) throws -> ShellOutput {
        let files = args.filter { !$0.hasPrefix("-") }
        if files.isEmpty { return .bytes(stdin) }
        var out: [UInt8] = []
        for f in files {
            let b = try readBytes(f)
            if TextSniffer.decode(b) == nil && b.count > 0 {
                return .fail("cat: \(f): binary file (\(b.count) bytes) — try `inspect`, `hexdump` or `strings`")
            }
            out += b
        }
        return .bytes(out)
    }

    private func headTail(_ head: Bool, _ args: [String], _ stdin: [UInt8]) throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["n"])
        var n = f.int("n", 10)
        var files = f.positional
        if let first = files.first, first.hasPrefix("-"), let v = Int(first.dropFirst()) { n = v; files.removeFirst() }
        let lines = TextDiff.lines(try inputText(files, stdin))
        let picked = head ? lines.prefix(n) : lines.suffix(n)
        return .ok(picked.joined(separator: "\n"))
    }

    private func touch(_ args: [String]) throws -> ShellOutput {
        for a in args where !fs.exists(a, cwd: cwd) { try fs.write(a, [], cwd: cwd) }
        return ShellOutput()
    }

    private func mkdir(_ args: [String]) throws -> ShellOutput {
        for a in ShellFlags(args).positional { try fs.makeDirectory(a, cwd: cwd) }
        return ShellOutput()
    }

    private func cp(_ args: [String]) throws -> ShellOutput {
        let p = ShellFlags(args).positional
        guard p.count >= 2 else { return .fail("usage: cp [-r] source... destination") }
        for src in p.dropLast() { try fs.copy(src, p.last!, cwd: cwd) }
        return ShellOutput()
    }

    private func mv(_ args: [String]) throws -> ShellOutput {
        let p = ShellFlags(args).positional
        guard p.count >= 2 else { return .fail("usage: mv source... destination") }
        for src in p.dropLast() { try fs.move(src, p.last!, cwd: cwd) }
        return ShellOutput()
    }

    private func rm(_ args: [String]) throws -> ShellOutput {
        let f = ShellFlags(args)
        for p in f.positional {
            do { try fs.remove(p, cwd: cwd, recursive: f.has("r") || f.has("R") || f.has("rf")) } catch {
                if !f.has("f") { throw error }
            }
        }
        return ShellOutput()
    }

    private func find(_ args: [String]) -> ShellOutput {
        var start = "."
        var pattern: String?
        var type: String?
        var i = 0
        while i < args.count {
            switch args[i] {
            case "-name", "-iname": pattern = i + 1 < args.count ? args[i + 1] : nil; i += 2
            case "-type": type = i + 1 < args.count ? args[i + 1] : nil; i += 2
            default: start = args[i]; i += 1
            }
        }
        let base = path(start)
        var results: [String] = []
        if type != "f" {
            // Folders too.
            var dirs: [String] = []
            func collect(_ p: String) {
                for e in (try? fs.list(p)) ?? [] where e.isDirectory { dirs.append(e.path); collect(e.path) }
            }
            collect(base)
            results += dirs
        }
        if type != "d" { results += fs.walk(base) }
        if let pattern { results = results.filter { SandboxFS.glob(pattern.lowercased(), ($0 as NSString).lastPathComponent.lowercased()) } }
        return .ok(results.sorted().joined(separator: "\n"))
    }

    private func stat(_ args: [String]) throws -> ShellOutput {
        var lines: [String] = []
        for a in args {
            let e = try fs.list(a, cwd: cwd).first { $0.path == path(a) } ?? fs.list((path(a) as NSString).deletingLastPathComponent).first { $0.path == path(a) }
            guard let e else { continue }
            let kind = e.isDirectory ? "folder" : FileKind.detect((try? readBytes(a).prefix(4096)).map(Array.init) ?? [], filename: e.name).name
            lines.append("\(e.path): \(kind), \(e.size) bytes, modified \(ISO8601DateFormatter().string(from: e.modified))")
        }
        return .ok(lines.joined(separator: "\n"))
    }

    private func tee(_ args: [String], _ stdin: [UInt8]) throws -> ShellOutput {
        let f = ShellFlags(args)
        for p in f.positional { if f.has("a") { try fs.append(p, stdin, cwd: cwd) } else { try fs.write(p, stdin, cwd: cwd) } }
        return .bytes(stdin)
    }

    // MARK: Text

    private func grep(_ args: [String], _ stdin: [UInt8]) throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["e"])
        var positional = f.positional
        guard let pattern = f.values["e"] ?? (positional.isEmpty ? nil : positional.removeFirst()) else { return .fail("usage: grep [-inrvcl] pattern [paths]") }
        let options: NSRegularExpression.Options = f.has("i") ? [.caseInsensitive] : []
        let re: NSRegularExpression
        if let compiled = try? NSRegularExpression(pattern: pattern, options: options) {
            re = compiled
        } else {
            re = try NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: pattern), options: options)
        }
        var targets: [(String, String)] = []
        if positional.isEmpty {
            if f.has("r") { positional = ["."] } else { targets = [("", String(decoding: stdin, as: UTF8.self))] }
        }
        for p in positional {
            if fs.isDirectory(p, cwd: cwd) {
                guard f.has("r") || f.has("R") else { continue }
                for file in fs.walk(p, cwd: cwd) { if let t = try? fs.readText(file) { targets.append((file, t)) } }
            } else if let t = try? readText(p) {
                targets.append((path(p), t))
            }
        }
        var out: [String] = []
        var total = 0
        let showName = targets.count > 1 || f.has("r")
        for (name, text) in targets {
            var count = 0
            for (n, line) in TextDiff.lines(text).enumerated() {
                let found = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
                guard found != f.has("v") else { continue }
                count += 1
                if f.has("c") || f.has("l") { continue }
                out.append((showName ? name + ":" : "") + (f.has("n") ? "\(n + 1):" : "") + line)
            }
            if f.has("c") { out.append((showName ? name + ":" : "") + String(count)) }
            if f.has("l") && count > 0 { out.append(name) }
            total += count
        }
        return ShellOutput(stdout: Array((out.joined(separator: "\n") + (out.isEmpty ? "" : "\n")).utf8), status: total > 0 ? 0 : 1)
    }

    private func sed(_ args: [String], _ stdin: [UInt8]) throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["e"])
        var positional = f.positional
        guard let script = f.values["e"] ?? (positional.isEmpty ? nil : positional.removeFirst()) else { return .fail("usage: sed 's/regex/replacement/g' [-i] [file]") }
        func transform(_ text: String) throws -> String {
            if script.hasPrefix("s"), script.count > 2 {
                let delimiter = script[script.index(after: script.startIndex)]
                let parts = script.dropFirst(2).components(separatedBy: String(delimiter))
                guard parts.count >= 2 else { throw SandboxError.io("bad s command") }
                let flags = parts.count > 2 ? parts[2] : ""
                let re = try NSRegularExpression(pattern: parts[0], options: flags.contains("i") ? [.caseInsensitive] : [])
                // sed's \1 and & become NSRegularExpression's $1 and $0.
                let template = parts[1].replacingOccurrences(of: "\\\\([0-9])", with: "\\$$1", options: .regularExpression)
                    .replacingOccurrences(of: "&", with: "$0")
                return TextDiff.lines(text).map { (line: String) -> String in
                    let whole = NSRange(line.startIndex..., in: line)
                    if flags.contains("g") { return re.stringByReplacingMatches(in: line, range: whole, withTemplate: template) }
                    guard let m = re.firstMatch(in: line, range: whole) else { return line }
                    return re.stringByReplacingMatches(in: line, range: m.range, withTemplate: template)
                }.joined(separator: "\n") + "\n"
            }
            if script.hasPrefix("/") && script.hasSuffix("/d") {
                let re = try NSRegularExpression(pattern: String(script.dropFirst().dropLast(2)))
                return TextDiff.lines(text).filter { re.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) == nil }.joined(separator: "\n") + "\n"
            }
            throw SandboxError.io("supported: s/regex/replacement/[gi] and /regex/d")
        }
        if f.has("i") {
            for p in positional { try fs.writeText(p, try transform(try readText(p)), cwd: cwd) }
            return ShellOutput()
        }
        return .ok(try transform(try inputText(positional, stdin)))
    }

    private func replace(_ args: [String]) throws -> ShellOutput {
        guard args.count >= 3 else { return .fail("usage: replace 'old text' 'new text' files...") }
        var lines: [String] = []
        for p in args.dropFirst(2) {
            let text = try readText(p)
            let count = text.components(separatedBy: args[0]).count - 1
            if count > 0 { try fs.writeText(p, text.replacingOccurrences(of: args[0], with: args[1]), cwd: cwd) }
            lines.append("\(path(p)): \(count) replacement(s)")
        }
        return .ok(lines.joined(separator: "\n"))
    }

    private func diff(_ args: [String]) throws -> ShellOutput {
        let p = ShellFlags(args).positional
        guard p.count == 2 else { return .fail("usage: diff a b") }
        let out = TextDiff.unified(try readText(p[0]), try readText(p[1]), oldName: path(p[0]), newName: path(p[1]))
        return ShellOutput(stdout: Array(out.utf8), status: out.isEmpty ? 0 : 1)
    }

    private func patch(_ args: [String], _ stdin: [UInt8]) throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["p", "i"])
        var diffText = String(decoding: stdin, as: UTF8.self)
        if let file = f.values["i"] { diffText = try readText(file) }
        var target = f.positional.first
        if target == nil {
            let strip = f.int("p", 0)
            if let line = diffText.components(separatedBy: "\n").first(where: { $0.hasPrefix("+++ ") }) {
                var name = String(line.dropFirst(4)).components(separatedBy: "\t").first ?? ""
                for _ in 0..<strip { if let slash = name.firstIndex(of: "/") { name = String(name[name.index(after: slash)...]) } }
                target = name
            }
        }
        guard let t = target, !diffText.isEmpty else { return .fail("usage: patch [file] < changes.diff") }
        let original = (try? readText(t)) ?? ""
        try fs.writeText(t, try TextDiff.apply(diffText, to: original), cwd: cwd)
        return .ok("patched \(path(t))")
    }

    private func sort(_ args: [String], _ stdin: [UInt8]) throws -> ShellOutput {
        let f = ShellFlags(args)
        var lines = TextDiff.lines(try inputText(f.positional, stdin))
        if f.has("n") {
            func key(_ line: String) -> Double {
                let first: Substring = line.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? ""
                return Double(first) ?? 0
            }
            lines.sort { (a: String, b: String) -> Bool in key(a) < key(b) }
        } else {
            lines.sort()
        }
        if f.has("r") { lines.reverse() }
        if f.has("u") { var seen = Set<String>(); lines = lines.filter { seen.insert($0).inserted } }
        return .ok(lines.joined(separator: "\n"))
    }

    private func uniq(_ args: [String], _ stdin: [UInt8]) throws -> ShellOutput {
        let f = ShellFlags(args)
        var out: [(String, Int)] = []
        for line in TextDiff.lines(try inputText(f.positional, stdin)) {
            if let last = out.last, last.0 == line { out[out.count - 1].1 += 1 } else { out.append((line, 1)) }
        }
        return .ok(out.map { f.has("c") ? String(format: "%7d %@", $0.1, $0.0) : $0.0 }.joined(separator: "\n"))
    }

    private func wc(_ args: [String], _ stdin: [UInt8]) throws -> ShellOutput {
        let f = ShellFlags(args)
        let files = f.positional
        var rows: [String] = []
        let all = !f.has("l") && !f.has("w") && !f.has("c")
        func row(_ text: String, _ bytes: Int, _ name: String) -> String {
            var parts: [String] = []
            if all || f.has("l") { parts.append(String(text.filter { $0 == "\n" }.count)) }
            if all || f.has("w") { parts.append(String(text.split { $0.isWhitespace }.count)) }
            if all || f.has("c") { parts.append(String(bytes)) }
            return parts.joined(separator: "\t") + (name.isEmpty ? "" : "\t" + name)
        }
        if files.isEmpty { rows.append(row(String(decoding: stdin, as: UTF8.self), stdin.count, "")) }
        for p in files {
            let b = try readBytes(p)
            rows.append(row(String(decoding: b, as: UTF8.self), b.count, p))
        }
        return .ok(rows.joined(separator: "\n"))
    }

    private func echo(_ args: [String]) -> ShellOutput {
        var a = args
        var newline = true, escapes = false
        while let first = a.first, first == "-n" || first == "-e" {
            if first == "-n" { newline = false } else { escapes = true }
            a.removeFirst()
        }
        var text = a.joined(separator: " ")
        if escapes { text = text.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t") }
        return ShellOutput(stdout: Array((text + (newline ? "\n" : "")).utf8))
    }

    private func printf(_ args: [String]) -> ShellOutput {
        guard var format = args.first else { return ShellOutput() }
        format = format.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
        var out = ""
        var values = Array(args.dropFirst())
        var i = format.startIndex
        while i < format.endIndex {
            if format[i] == "%", format.index(after: i) < format.endIndex {
                let spec = format[format.index(after: i)]
                if spec == "%" { out += "%" } else { out += values.isEmpty ? "" : values.removeFirst() }
                i = format.index(i, offsetBy: 2)
                continue
            }
            out.append(format[i])
            i = format.index(after: i)
        }
        return ShellOutput(stdout: Array(out.utf8))
    }
}

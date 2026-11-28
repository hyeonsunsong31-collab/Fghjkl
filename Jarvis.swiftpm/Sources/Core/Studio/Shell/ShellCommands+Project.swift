import Foundation

/// Binary, archive, conversion, runtime, workspace and agent commands.
extension Shell {
    // MARK: Binaries & ROMs

    func file(_ args: [String]) throws -> ShellOutput {
        var lines: [String] = []
        for a in args {
            if fs.isDirectory(a, cwd: cwd) { lines.append("\(a): folder"); continue }
            let b = try readBytes(a)
            lines.append("\(a): \(FileKind.detect(b, filename: a).name), \(b.count) bytes")
        }
        return .ok(lines.joined(separator: "\n"))
    }

    func inspect(_ args: [String]) throws -> ShellOutput {
        guard let a = args.first else { return .fail("usage: inspect path") }
        return .ok(BinaryInspector.report(try readBytes(a), filename: (a as NSString).lastPathComponent))
    }

    func hexdump(_ args: [String]) throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["s", "n", "l"])
        guard let p = f.positional.first else { return .fail("usage: hexdump [-s offset] [-n length] path") }
        let offset = parseNumber(f.values["s"] ?? "0") ?? 0
        let length = parseNumber(f.values["n"] ?? f.values["l"] ?? "512") ?? 512
        return .ok(BinaryTools.hexdump(try readBytes(p), offset: offset, length: length))
    }

    func strings(_ args: [String]) throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["n"])
        guard let p = f.positional.first else { return .fail("usage: strings [-n min] path") }
        let found = BinaryTools.strings(try readBytes(p), minimum: f.int("n", 5))
        return .ok(found.map { String(format: "%08x  ", $0.offset) + $0.text }.joined(separator: "\n"))
    }

    func hexpatch(_ args: [String]) throws -> ShellOutput {
        let p = ShellFlags(args).positional
        guard p.count >= 3, let offset = parseNumber(p[1]), let bytes = [UInt8](hex: p[2]) else { return .fail("usage: hexpatch path offset hexbytes [output]") }
        let patched = BinaryTools.patch(try readBytes(p[0]), at: offset, with: bytes)
        let out = p.count > 3 ? p[3] : p[0]
        try fs.write(out, patched, cwd: cwd)
        return .ok(String(format: "wrote %d byte(s) at 0x%X in %@", bytes.count, offset, path(out)) + romNote(out))
    }

    func binreplace(_ args: [String]) throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["o"])
        let p = f.positional
        guard p.count >= 3 else { return .fail("usage: binreplace path 'from' 'to' [--hex] [--utf16] [--any-length] [-o output]") }
        let find: [UInt8]? = f.has("hex") ? [UInt8](hex: p[1]) : BinaryTools.encode(p[1], utf16: f.has("utf16"))
        let to: [UInt8]? = f.has("hex") ? [UInt8](hex: p[2]) : BinaryTools.encode(p[2], utf16: f.has("utf16"))
        guard let find, let to else { return .fail("binreplace: bad hex bytes") }
        let result = BinaryTools.replaceAll(try readBytes(p[0]), find: find, with: to, mode: f.has("any-length") ? .any : .sameLength)
        if let error = result.error { return .fail("binreplace: \(error)") }
        let out = f.values["o"] ?? p[0]
        if result.count > 0 { try fs.write(out, result.bytes, cwd: cwd) }
        return .ok("\(result.count) replacement(s) in \(path(out))" + (result.count > 0 ? romNote(out) : ""))
    }

    func compare(_ args: [String]) throws -> ShellOutput {
        let p = ShellFlags(args).positional
        guard p.count == 2 else { return .fail("usage: compare a b") }
        let a = try readBytes(p[0]), b = try readBytes(p[1])
        return ShellOutput(stdout: Array((BinaryTools.compare(a, b) + "\n").utf8), status: a == b ? 0 : 1)
    }

    func romPatch(_ format: String, _ args: [String]) throws -> ShellOutput {
        let p = ShellFlags(args).positional
        guard p.count >= 3, ["apply", "create"].contains(p[0]) else {
            return .fail("usage: \(format) apply patch rom [output]  |  \(format) create original modified output")
        }
        if p[0] == "apply" {
            let patchBytes = try readBytes(p[1]), rom = try readBytes(p[2])
            let result: [UInt8]
            switch format {
            case "ips": result = try IPSPatch.apply(patchBytes, to: rom)
            case "bps": result = try BPSPatch.apply(patchBytes, to: rom)
            default: result = try UPSPatch.apply(patchBytes, to: rom)
            }
            let ext = (p[2] as NSString).pathExtension
            let out = p.count > 3 ? p[3] : FormatConverter.baseName(p[2]) + "-patched" + (ext.isEmpty ? "" : "." + ext)
            try fs.write(out, result, cwd: cwd)
            return .ok("patched → \(path(out)) (\(result.count) bytes)")
        }
        guard p.count >= 4 else { return .fail("usage: \(format) create original modified output") }
        let original = try readBytes(p[1]), modified = try readBytes(p[2])
        let made: [UInt8]
        switch format {
        case "ips": made = try IPSPatch.create(original: original, modified: modified)
        case "bps": made = BPSPatch.create(original: original, modified: modified)
        default: made = UPSPatch.create(original: original, modified: modified)
        }
        try fs.write(p[3], made, cwd: cwd)
        return .ok("\(format.uppercased()) patch \(path(p[3])): \(made.count) bytes (share the patch, not the ROM)")
    }

    func romfix(_ args: [String]) throws -> ShellOutput {
        guard let p = args.first else { return .fail("usage: romfix rom") }
        var b = try readBytes(p)
        switch FileKind.detect(b, filename: p).id {
        case "gba": GBAHeader.fixChecksum(&b)
        case "gb", "gbc": GBHeader.fixChecksums(&b)
        default: return .fail("romfix: \(p) is not a GBA or Game Boy ROM")
        }
        try fs.write(p, b, cwd: cwd)
        return .ok("header checksum fixed in \(path(p))")
    }

    func romtitle(_ args: [String]) throws -> ShellOutput {
        guard args.count >= 2 else { return .fail("usage: romtitle rom 'NEW TITLE'") }
        var b = try readBytes(args[0])
        guard GBAHeader.parse(b) != nil else { return .fail("romtitle: only GBA ROMs are supported") }
        GBAHeader.setTitle(&b, args[1])
        try fs.write(args[0], b, cwd: cwd)
        return .ok("title set to \(GBAHeader.parse(b)?.title ?? "") (checksum fixed)")
    }

    private func romNote(_ p: String) -> String {
        guard let b = try? readBytes(p) else { return "" }
        if let g = GBAHeader.parse(b), !g.checksumValid { return "\nnote: the GBA header checksum is now wrong — run `romfix \(p)`" }
        return ""
    }

    func parseNumber(_ s: String) -> Int? {
        let t = s.lowercased()
        if t.hasPrefix("0x") { return Int(t.dropFirst(2), radix: 16) }
        if t.hasSuffix("h") { return Int(t.dropLast(), radix: 16) }
        return Int(t)
    }

    // MARK: Archives & formats

    func zip(_ args: [String]) throws -> ShellOutput {
        let p = ShellFlags(args).positional
        guard p.count >= 2 else { return .fail("usage: zip out.zip paths...") }
        var items: [ZipArchive.Item] = []
        for src in p.dropFirst() {
            let base = path(src)
            let name = (base as NSString).lastPathComponent
            if fs.isDirectory(base) {
                for f in fs.walk(base) { items.append(ZipArchive.Item(path: name + String(f.dropFirst(base.count)), data: try fs.read(f))) }
            } else {
                items.append(ZipArchive.Item(path: name, data: try fs.read(base)))
            }
        }
        let zipped = ZipArchive.build(items)
        try fs.write(p[0], zipped, cwd: cwd)
        return .ok("\(path(p[0])): \(items.count) file(s), \(zipped.count) bytes")
    }

    func unzip(_ args: [String]) throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["d"])
        guard let archive = f.positional.first else { return .fail("usage: unzip [-l] archive [-d folder]") }
        let bytes = try readBytes(archive)
        let files = try FormatConverter.unpack(bytes, filename: archive)
        if f.has("l") { return .ok(files.map { "\($0.data.count)\t\($0.path)" }.joined(separator: "\n")) }
        let dest = f.values["d"] ?? FormatConverter.baseName(archive)
        for item in files { try fs.write(dest + "/" + item.path, item.data, cwd: cwd) }
        return .ok("extracted \(files.count) file(s) to \(path(dest))")
    }

    func tar(_ args: [String]) throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["f", "C"])
        guard let archive = f.values["f"] else { return .fail("usage: tar -czf out.tar.gz paths | tar -xzf archive [-C dir] | tar -tf archive") }
        let gz = f.has("z") || archive.hasSuffix(".gz") || archive.hasSuffix(".tgz")
        if f.has("c") {
            var entries: [TarArchive.Entry] = []
            for src in f.positional {
                let base = path(src)
                let name = (base as NSString).lastPathComponent
                if fs.isDirectory(base) {
                    for file in fs.walk(base) { entries.append(TarArchive.Entry(path: name + String(file.dropFirst(base.count)), data: try fs.read(file))) }
                } else {
                    entries.append(TarArchive.Entry(path: name, data: try fs.read(base)))
                }
            }
            let built = TarArchive.build(entries)
            try fs.write(archive, gz ? Gzip.compress(built) : built, cwd: cwd)
            return .ok("\(path(archive)): \(entries.count) file(s)")
        }
        var bytes = try readBytes(archive)
        if Gzip.isGzip(bytes) { bytes = try Gzip.decompress(bytes).data }
        let entries = try TarArchive.read(bytes)
        if f.has("t") { return .ok(entries.map(\.path).joined(separator: "\n")) }
        let dest = f.values["C"] ?? "."
        var count = 0
        for e in entries where !e.isDirectory {
            guard let safe = ZipArchive.safePath(e.path) else { continue }
            try fs.write(dest + "/" + safe, e.data, cwd: cwd)
            count += 1
        }
        return .ok("extracted \(count) file(s)")
    }

    func gzip(_ args: [String]) throws -> ShellOutput {
        for p in ShellFlags(args).positional {
            try fs.write(p + ".gz", Gzip.compress(try readBytes(p), name: (p as NSString).lastPathComponent), cwd: cwd)
        }
        return ShellOutput()
    }

    func gunzip(_ args: [String]) throws -> ShellOutput {
        for p in ShellFlags(args).positional {
            let inner = try Gzip.decompress(try readBytes(p))
            let out = p.hasSuffix(".gz") ? String(p.dropLast(3)) : (inner.name ?? p + ".out")
            try fs.write(out, inner.data, cwd: cwd)
        }
        return ShellOutput()
    }

    func convert(_ args: [String]) async throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["to", "open"])
        let p = f.positional
        guard let input = p.first else { return .fail("usage: convert input output  |  convert input --to ext") }
        let target: String
        var outputName: String?
        if let t = f.values["to"] { target = t } else if p.count >= 2 {
            outputName = p[1]
            target = p[1].lowercased().hasSuffix(".tar.gz") ? "tgz" : (p[1].lowercased().hasSuffix(".app.zip") ? "app" : (p[1] as NSString).pathExtension.isEmpty ? p[1] : (p[1] as NSString).pathExtension)
        } else {
            return .fail("convert: say what to convert to, e.g. `convert \(input) --to json`")
        }
        let bytes: [UInt8]
        let name: String
        if fs.isDirectory(input, cwd: cwd) {
            bytes = Packager.zip(try fs.packageFiles(input, cwd: cwd))
            name = (path(input) as NSString).lastPathComponent + ".zip"
        } else {
            bytes = try readBytes(input)
            name = (input as NSString).lastPathComponent
        }
        let result = try await FormatConverter.convert(bytes, filename: name, to: target, open: f.values["open"])
        let folder = (path(input) as NSString).deletingLastPathComponent
        let out = outputName ?? (folder == "/" ? "/" : folder + "/") + result.filename
        try fs.write(out, result.data, cwd: cwd)
        return .ok("\(path(out)) (\(ByteCountFormatter.string(fromByteCount: Int64(result.data.count), countStyle: .file)))\n\(result.note)")
    }

    func pack(_ args: [String]) throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["open", "name", "o"])
        let p = f.positional
        guard let kind = p.first, ["exe", "app", "sh", "html", "zip"].contains(kind) else {
            return .fail("usage: pack exe|app|sh|html|zip [path] [--open main.html] [--name Name] [-o output]")
        }
        let src = p.count > 1 ? p[1] : "."
        let files = try fs.packageFiles(src, cwd: cwd).filter { !$0.path.hasPrefix("dist/") }
        guard !files.isEmpty else { return .fail("pack: nothing to package in \(src)") }
        let folderName = (path(src) as NSString).lastPathComponent
        let name = f.values["name"] ?? (store?.workspace(workspaceID)?.product?.title ?? (folderName.isEmpty ? (store?.workspace(workspaceID)?.name ?? "App") : folderName))
        let entry = f.values["open"] ?? FormatConverter.mainEntry(files)
        let safe = Packager.sanitizedName(name)
        var output: [UInt8]
        var outName: String
        var note: String
        switch kind {
        case "exe":
            output = Packager.windowsExe(name: name, files: files, open: entry)
            outName = safe + ".exe"
            note = "Windows program: double-click to run\(entry.map { " (opens \($0))" } ?? "")."
        case "app":
            output = Packager.macApp(name: name, files: files, open: entry ?? files[0].path)
            outName = safe + ".app.zip"
            note = "macOS app (zipped). First launch: right-click → Open."
        case "sh":
            output = Packager.shellInstaller(name: name, files: files, open: entry)
            outName = safe + ".sh"
            note = "Self-extracting script for Linux/macOS: sh \(safe).sh"
        case "html":
            guard let e = entry, e.hasSuffix(".html") else { return .fail("pack html: no HTML page to start from") }
            output = Array(Packager.singleHTML(files: files, entry: e).utf8)
            outName = safe + ".html"
            note = "One self-contained page: works offline in any browser."
        default:
            output = Packager.zip(files, folder: safe)
            outName = safe + ".zip"
            note = "ZIP archive."
        }
        let out = f.values["o"] ?? "/dist/" + outName
        try fs.write(out, output, cwd: cwd)
        return .ok("\(path(out)) (\(ByteCountFormatter.string(fromByteCount: Int64(output.count), countStyle: .file)), \(files.count) file(s))\n\(note)")
    }

    func checksum(_ name: String, _ args: [String], _ stdin: [UInt8]) throws -> ShellOutput {
        let files = ShellFlags(args).positional
        func one(_ b: [UInt8]) -> String { name == "crc32" ? String(format: "%08x", CRC32.checksum(b)) : PortableSHA256.hex(b) }
        if files.isEmpty { return .ok(one(stdin)) }
        return .ok(try files.map { "\(one(try readBytes($0)))  \($0)" }.joined(separator: "\n"))
    }

    func base64(_ args: [String], _ stdin: [UInt8]) throws -> ShellOutput {
        let f = ShellFlags(args)
        let input = try f.positional.first.map { try readBytes($0) } ?? stdin
        if f.has("d") || f.has("D") {
            guard let d = Data(base64Encoded: String(decoding: input, as: UTF8.self), options: .ignoreUnknownCharacters) else { return .fail("base64: invalid input") }
            return .bytes([UInt8](d))
        }
        return .ok(Data(input).base64EncodedString(options: [.lineLength76Characters]))
    }

    // MARK: Running things

    func runFile(_ args: [String], _ stdin: [UInt8]) async throws -> ShellOutput {
        guard let p = args.first else { return .fail("usage: run path [args]") }
        let ext = (p as NSString).pathExtension.lowercased()
        switch ext {
        case "js", "mjs", "cjs": return try await runtime("js", args, stdin)
        case "py": return try await runtime("python", args, stdin)
        case "html", "htm": return await hostAction("preview", [p], stdin)
        case "sh", "jsh": return try await shellScript(args)
        case "json":
            let v = try JSONValueParser.parse(try readText(p))
            return .ok("valid JSON (\(FormatConverter.summary(v)))")
        default:
            let b = try readBytes(p)
            let kind = FileKind.detect(b, filename: p)
            switch kind.category {
            case .executable:
                return .fail("\(p): \(kind.name) — iOS lets apps run no foreign executables. `inspect \(p)` shows what it is; `ai rebuild \(p) as a web app` recreates it in a form that runs here.", 126)
            case .rom:
                return .fail("\(p): \(kind.name) — open it in an emulator app (use `share \(p)`); I can inspect, patch and fix it here.", 126)
            default:
                return .fail("\(p): no runtime for .\(ext) files in the workspace (runs here: .js .html .py .sh)", 126)
            }
        }
    }

    func runtime(_ kind: String, _ args: [String], _ stdin: [UInt8]) async throws -> ShellOutput {
        guard let p = args.first else { return .fail(kind == "js" ? "usage: node file.js [args]" : "usage: python file.py [args]") }
        if p == "-e" || p == "-c" {
            // Inline code: write it to a scratch file first.
            let code = args.dropFirst().joined(separator: " ")
            let scratch = kind == "js" ? "/.scratch.js" : "/.scratch.py"
            try fs.writeText(scratch, code)
            return await hostAction(kind, [scratch], stdin)
        }
        guard fs.exists(p, cwd: cwd) else { throw SandboxError.notFound(p) }
        return await hostAction(kind, args, stdin)
    }

    func shellScript(_ args: [String]) async throws -> ShellOutput {
        guard let p = args.first else { return .fail("usage: sh script.sh") }
        let text = try readText(p)
        for (i, a) in args.dropFirst().enumerated() { env[String(i + 1)] = a }
        return await runScript(text)
    }

    func hostAction(_ name: String, _ args: [String], _ stdin: [UInt8]) async -> ShellOutput {
        let kind = name == "test" ? "verify" : name
        var target = args.first ?? ""
        if target.isEmpty {
            switch kind {
            case "preview", "verify", "serve":
                target = store?.workspace(workspaceID)?.product?.entry ?? FormatConverter.mainEntry((try? fs.packageFiles("/")) ?? []).map { "/" + $0 } ?? "/index.html"
                if kind == "serve" { target = (target as NSString).deletingLastPathComponent }
                if target.isEmpty { target = "/" }
            default:
                return .fail("usage: \(name) path")
            }
        }
        guard let host else {
            return .fail("\(name): needs the app's runtime (not available in this environment)", 127)
        }
        if let out = await host.perform(kind, path: path(target), args: Array(args.dropFirst()), shell: self, stdin: stdin) { return out }
        return .fail("\(name): not available", 127)
    }

    // MARK: Network (user-initiated)

    func lib(_ args: [String]) async throws -> ShellOutput {
        guard args.first == "add", args.count >= 2 else {
            if args.first == "list" { return .ok(((try? fs.list("/lib")) ?? []).map(\.name).joined(separator: "\n")) }
            return .fail("usage: lib add <package>[@version]  |  lib list   (browser ES modules from jsDelivr, cached in /lib)")
        }
        guard let host else { return .fail("lib: needs the network from the app") }
        var lines: [String] = []
        for spec in args.dropFirst() {
            let name = spec.split(separator: "@", omittingEmptySubsequences: false).first.map(String.init) ?? spec
            guard let url = URL(string: "https://cdn.jsdelivr.net/npm/\(spec)/+esm") else { continue }
            let (data, _) = try await host.fetch(url)
            let file = "/lib/\(name.replacingOccurrences(of: "/", with: "_")).js"
            try fs.write(file, [UInt8](data))
            lines.append("\(file) (\(data.count) bytes) — import it with: import * as \(name.filter { $0.isLetter }) from './lib/\((file as NSString).lastPathComponent)'")
        }
        return .ok(lines.joined(separator: "\n"))
    }

    func fetch(_ args: [String]) async throws -> ShellOutput {
        let f = ShellFlags(args, valued: ["o", "O"])
        guard let s = f.positional.first, let url = URL(string: s), url.scheme == "https" || url.scheme == "http" else { return .fail("usage: fetch https://… [output]") }
        guard let host else { return .fail("fetch: needs the network from the app") }
        let (data, _) = try await host.fetch(url)
        let out = f.values["o"] ?? (f.positional.count > 1 ? f.positional[1] : (url.lastPathComponent.isEmpty || url.lastPathComponent == "/" ? "download" : url.lastPathComponent))
        try fs.write(out, [UInt8](data), cwd: cwd)
        return .ok("\(path(out)) (\(data.count) bytes)")
    }

    func git(_ args: [String]) async throws -> ShellOutput {
        guard let sub = args.first else { return .fail("usage: git clone <github url> | status | log | diff | commit -m message") }
        switch sub {
        case "clone":
            guard args.count >= 2, let url = URL(string: args[1]), url.host?.contains("github.com") == true else { return .fail("git clone: give a https://github.com/owner/repo address") }
            guard let host else { return .fail("git clone: needs the network from the app") }
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return .fail("git clone: expected github.com/owner/repo") }
            let repo = parts[1].replacingOccurrences(of: ".git", with: "")
            let branch = parts.count >= 4 && parts[2] == "tree" ? parts[3] : "HEAD"
            guard let zipURL = URL(string: "https://codeload.github.com/\(parts[0])/\(repo)/zip/\(branch == "HEAD" ? "HEAD" : "refs/heads/" + branch)") else { return .fail("git clone: bad address") }
            let (data, _) = try await host.fetch(zipURL)
            let files = try FormatConverter.unpack([UInt8](data), filename: repo + ".zip")
            let dest = args.count > 2 ? args[2] : repo
            for item in files {
                // Drop GitHub's "repo-branch/" top folder.
                let inner = item.path.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) ?? item.path
                try fs.write(dest + "/" + inner, item.data, cwd: cwd)
            }
            return .ok("cloned \(parts[0])/\(repo) into \(path(dest)) (\(files.count) files, no git history)")
        case "status", "diff":
            guard let store, let ws = store.workspace(workspaceID) else { return .fail("git: no workspace") }
            guard ws.latestVersion > 0 else { return .ok("no saved version yet; everything is new (`git commit -m message` saves one)") }
            return .ok(store.changes(workspaceID, from: ws.latestVersion, to: 0, diffs: sub == "diff"))
        case "log": return try versions(["list"])
        case "commit":
            let f = ShellFlags(Array(args.dropFirst()), valued: ["m"])
            return try versions(["save", f.values["m"] ?? "manual save"])
        case "checkout", "restore", "reset":
            if args.count >= 2, let n = Int(args[1].replacingOccurrences(of: "v", with: "")) { return try versions(["restore", String(n)]) }
            return .fail("git \(sub): give a version number from `git log`")
        default:
            return .fail("git \(sub): the workspace keeps versions instead of a git repository (status, log, diff, commit, clone are supported)")
        }
    }

    // MARK: Workspace, versions, queue, agent

    func ws(_ args: [String]) -> ShellOutput {
        guard let store else { return .fail("ws: no workspace store") }
        let sub = args.first ?? "list"
        let rest = args.dropFirst().joined(separator: " ")
        switch sub {
        case "list", "ls":
            let lines = store.workspaces.enumerated().map { (i, w) -> String in
                let mark = w.id == workspaceID ? "*" : " "
                let product = w.product.map { " — \($0.kind): \($0.title)" } ?? ""
                return "\(mark) \(i + 1). \(w.name)\(product)  [v\(w.latestVersion), \(w.pending.count) queued]"
            }
            return .ok(lines.isEmpty ? "no workspaces (ws new <name>)" : lines.joined(separator: "\n"))
        case "new", "add", "create":
            let w = store.create(name: rest)
            attach(workspaceID: w.id, fs: store.files(w.id))
            return .ok("created and switched to workspace \"\(w.name)\"")
        case "use", "switch", "cd":
            guard let w = store.find(rest) else { return .fail("ws: no workspace named \(rest)") }
            store.activate(w.id)
            attach(workspaceID: w.id, fs: store.files(w.id))
            return .ok("switched to \"\(w.name)\"")
        case "rename":
            store.rename(workspaceID, to: rest)
            return .ok("renamed to \"\(rest)\"")
        case "rm", "delete":
            guard let w = rest.isEmpty ? store.workspace(workspaceID) : store.find(rest) else { return .fail("ws: no such workspace") }
            store.delete(w.id)
            if let next = store.active { attach(workspaceID: next.id, fs: store.files(next.id)) }
            return .ok("deleted \"\(w.name)\"")
        case "info":
            guard let w = store.workspace(workspaceID) else { return .fail("ws: no workspace") }
            var lines = ["\(w.name) (\(w.id))", "files: \(fs.walk().count), \(ByteCountFormatter.string(fromByteCount: Int64(fs.totalSize), countStyle: .file))",
                         "versions: \(w.versions.count), requests: \(w.requests.count) (\(w.pending.count) waiting)"]
            if let p = w.product { lines.append("product: \(p.kind) \"\(p.title)\"\(p.entry.map { ", main file \($0)" } ?? "")\(p.template.map { ", template \($0)" } ?? "")") }
            return .ok(lines.joined(separator: "\n"))
        default:
            return .fail("usage: ws [list|new NAME|use NAME|rename NAME|rm [NAME]|info]")
        }
    }

    func versions(_ args: [String]) throws -> ShellOutput {
        guard let store, let ws = store.workspace(workspaceID) else { return .fail("versions: no workspace") }
        let sub = args.first ?? "list"
        switch sub {
        case "list", "log":
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm"
            let lines = ws.versions.reversed().map { "v\($0.number)  \(f.string(from: $0.created))  \($0.fileCount) files  \($0.summary)" }
            return .ok(lines.isEmpty ? "no versions yet" : lines.joined(separator: "\n"))
        case "save":
            let v = try store.snapshot(workspaceID, summary: args.dropFirst().joined(separator: " ").isEmpty ? "manual save" : args.dropFirst().joined(separator: " "))
            return .ok("saved v\(v.number) (\(v.fileCount) files)")
        case "restore":
            guard args.count >= 2, let n = Int(args[1].replacingOccurrences(of: "v", with: "")) else { return .fail("usage: versions restore N") }
            try store.restore(workspaceID, version: n)
            return .ok("restored v\(n) (the files before it are kept as a version too)")
        case "diff":
            guard args.count >= 2, let a = Int(args[1].replacingOccurrences(of: "v", with: "")) else { return .fail("usage: versions diff N [M]") }
            let b = args.count >= 3 ? Int(args[2].replacingOccurrences(of: "v", with: "")) ?? 0 : 0
            return .ok(store.changes(workspaceID, from: a, to: b))
        default:
            return .fail("usage: versions [list|save MESSAGE|restore N|diff N [M]]")
        }
    }

    func queue(_ args: [String]) -> ShellOutput {
        guard let store, let ws = store.workspace(workspaceID) else { return .fail("queue: no workspace") }
        let sub = args.first ?? "list"
        switch sub {
        case "list", "ls":
            let icons: [WorkRequest.Status: String] = [.queued: "…", .running: "▶", .done: "✓", .failed: "✗", .cancelled: "–"]
            let lines = ws.requests.suffix(30).map { r in "\(icons[r.status] ?? "?") \(r.text)" + (r.summary.map { "\n    \($0)" } ?? "") }
            return .ok(lines.isEmpty ? "no requests yet" : lines.joined(separator: "\n"))
        case "add":
            let text = args.dropFirst().joined(separator: " ")
            guard !text.isEmpty else { return .fail("usage: queue add <request>") }
            store.enqueue(text, in: workspaceID, korean: text.unicodeScalars.contains { Hangul.isSyllable($0) })
            return .ok("queued: \(text) (\(store.workspace(workspaceID)?.pending.count ?? 1) waiting)")
        case "clear":
            var w = ws
            for i in w.requests.indices where w.requests[i].status == .queued { w.requests[i].status = .cancelled }
            store.save(w)
            return .ok("cleared the waiting requests")
        case "run":
            return .ok("the queue runs automatically while Jarvis works on this workspace")
        default:
            return .fail("usage: queue [list|add REQUEST|clear]")
        }
    }

    func agent(_ name: String, _ args: [String]) async -> ShellOutput {
        var request = args.joined(separator: " ")
        switch name {
        case "fix": request = args.isEmpty ? "Find and fix every error in this product until it runs without errors." : "Find and fix every error in \(args.joined(separator: " ")) until it runs without errors."
        case "explain": request = "Explain what \(args.joined(separator: " ")) does, briefly."
        default: break
        }
        guard !request.isEmpty else { return .fail("usage: ai <what to build or change>") }
        guard let host else { return .fail("\(name): the coding agent needs the app (Apple Intelligence or Deep Think)", 127) }
        return await host.agent(request, shell: self) ?? .fail("\(name): the coding agent is not available")
    }
}

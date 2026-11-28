import Foundation

enum SandboxError: Error, CustomStringConvertible {
    case outside(String)
    case notFound(String)
    case notDirectory(String)
    case isDirectory(String)
    case exists(String)
    case io(String)

    var description: String {
        switch self {
        case .outside(let p): return "\(p): outside this workspace"
        case .notFound(let p): return "\(p): no such file or folder"
        case .notDirectory(let p): return "\(p): not a folder"
        case .isDirectory(let p): return "\(p): is a folder"
        case .exists(let p): return "\(p): already exists"
        case .io(let s): return s
        }
    }
}

/// File operations confined to one folder. Paths are virtual: "/" is the folder itself,
/// relative paths start at `cwd`, ".." never climbs out.
struct SandboxFS {
    struct Entry: Equatable {
        var name: String
        var path: String
        var isDirectory: Bool
        var size: Int
        var modified: Date
    }

    let root: URL
    private var fm: FileManager { FileManager.default }

    init(root: URL) {
        self.root = root.standardizedFileURL
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    /// Normalised virtual path ("/a/b") for `path` seen from `cwd`.
    static func normalize(_ path: String, cwd: String = "/") -> String {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p == "~" || p.isEmpty { p = "/" } else if p.hasPrefix("~/") { p = "/" + p.dropFirst(2) }
        let full = p.hasPrefix("/") ? p : (cwd.hasSuffix("/") ? cwd : cwd + "/") + p
        var parts: [Substring] = []
        for piece in full.split(separator: "/") {
            if piece == "." || piece.isEmpty { continue }
            if piece == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(piece)
        }
        return "/" + parts.joined(separator: "/")
    }

    func url(_ path: String, cwd: String = "/") throws -> URL {
        let v = Self.normalize(path, cwd: cwd)
        let u = v == "/" ? root : root.appendingPathComponent(String(v.dropFirst()))
        let resolved = u.standardizedFileURL.path
        guard resolved == root.path || resolved.hasPrefix(root.path + "/") else { throw SandboxError.outside(path) }
        return u
    }

    func virtualPath(of url: URL) -> String {
        let p = url.standardizedFileURL.path
        guard p.hasPrefix(root.path) else { return "/" }
        let rest = String(p.dropFirst(root.path.count))
        return rest.isEmpty ? "/" : rest
    }

    func exists(_ path: String, cwd: String = "/") -> Bool {
        guard let u = try? url(path, cwd: cwd) else { return false }
        return fm.fileExists(atPath: u.path)
    }

    func isDirectory(_ path: String, cwd: String = "/") -> Bool {
        guard let u = try? url(path, cwd: cwd) else { return false }
        var dir: ObjCBool = false
        return fm.fileExists(atPath: u.path, isDirectory: &dir) && dir.boolValue
    }

    func list(_ path: String = "/", cwd: String = "/", hidden: Bool = false) throws -> [Entry] {
        let u = try url(path, cwd: cwd)
        guard fm.fileExists(atPath: u.path) else { throw SandboxError.notFound(path) }
        guard isDirectory(path, cwd: cwd) else {
            return [try entry(u)]
        }
        let names = try fm.contentsOfDirectory(atPath: u.path).filter { hidden || !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return try names.map { try entry(u.appendingPathComponent($0)) }
    }

    private func entry(_ u: URL) throws -> Entry {
        let attrs = try fm.attributesOfItem(atPath: u.path)
        let dir = (attrs[.type] as? FileAttributeType) == .typeDirectory
        return Entry(name: u.lastPathComponent, path: virtualPath(of: u), isDirectory: dir,
                     size: (attrs[.size] as? NSNumber)?.intValue ?? 0, modified: (attrs[.modificationDate] as? Date) ?? Date())
    }

    /// Every file under `path`, as virtual paths (sorted).
    func walk(_ path: String = "/", cwd: String = "/", hidden: Bool = false) -> [String] {
        guard let u = try? url(path, cwd: cwd) else { return [] }
        if !isDirectory(path, cwd: cwd) { return fm.fileExists(atPath: u.path) ? [virtualPath(of: u)] : [] }
        var out: [String] = []
        if let e = fm.enumerator(at: u, includingPropertiesForKeys: [.isDirectoryKey], options: hidden ? [] : [.skipsHiddenFiles]) {
            for case let f as URL in e {
                let dir = (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if !dir { out.append(virtualPath(of: f)) }
            }
        }
        return out.sorted()
    }

    func read(_ path: String, cwd: String = "/") throws -> [UInt8] {
        let u = try url(path, cwd: cwd)
        guard fm.fileExists(atPath: u.path) else { throw SandboxError.notFound(path) }
        guard !isDirectory(path, cwd: cwd) else { throw SandboxError.isDirectory(path) }
        return [UInt8](try Data(contentsOf: u))
    }

    func readText(_ path: String, cwd: String = "/") throws -> String {
        let bytes = try read(path, cwd: cwd)
        guard let text = TextSniffer.decode(bytes) else { throw SandboxError.io("\(path): binary file (use hexdump or inspect)") }
        return text
    }

    func write(_ path: String, _ bytes: [UInt8], cwd: String = "/") throws {
        let u = try url(path, cwd: cwd)
        guard virtualPath(of: u) != "/" else { throw SandboxError.isDirectory(path) }
        if isDirectory(path, cwd: cwd) { throw SandboxError.isDirectory(path) }
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: u, options: .atomic)
    }

    func writeText(_ path: String, _ text: String, cwd: String = "/") throws { try write(path, Array(text.utf8), cwd: cwd) }

    func append(_ path: String, _ bytes: [UInt8], cwd: String = "/") throws {
        let existing = (try? read(path, cwd: cwd)) ?? []
        try write(path, existing + bytes, cwd: cwd)
    }

    func makeDirectory(_ path: String, cwd: String = "/") throws {
        try fm.createDirectory(at: try url(path, cwd: cwd), withIntermediateDirectories: true)
    }

    func remove(_ path: String, cwd: String = "/", recursive: Bool = false) throws {
        let u = try url(path, cwd: cwd)
        guard virtualPath(of: u) != "/" else { throw SandboxError.io("refusing to delete the whole workspace (use `ws rm`)") }
        guard fm.fileExists(atPath: u.path) else { throw SandboxError.notFound(path) }
        if isDirectory(path, cwd: cwd) && !recursive && !((try? fm.contentsOfDirectory(atPath: u.path))?.isEmpty ?? true) {
            throw SandboxError.isDirectory(path + " (use rm -r)")
        }
        try fm.removeItem(at: u)
    }

    func copy(_ from: String, _ to: String, cwd: String = "/") throws {
        let a = try url(from, cwd: cwd)
        var b = try url(to, cwd: cwd)
        guard fm.fileExists(atPath: a.path) else { throw SandboxError.notFound(from) }
        if isDirectory(to, cwd: cwd) { b = b.appendingPathComponent(a.lastPathComponent) }
        if fm.fileExists(atPath: b.path) { try fm.removeItem(at: b) }
        try fm.createDirectory(at: b.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: a, to: b)
    }

    func move(_ from: String, _ to: String, cwd: String = "/") throws {
        let a = try url(from, cwd: cwd)
        var b = try url(to, cwd: cwd)
        guard fm.fileExists(atPath: a.path) else { throw SandboxError.notFound(from) }
        if isDirectory(to, cwd: cwd) { b = b.appendingPathComponent(a.lastPathComponent) }
        if fm.fileExists(atPath: b.path) { try fm.removeItem(at: b) }
        try fm.createDirectory(at: b.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: a, to: b)
    }

    /// Files under `path` as package entries (paths relative to it).
    func packageFiles(_ path: String = "/", cwd: String = "/") throws -> [PackageFile] {
        let base = Self.normalize(path, cwd: cwd)
        if !isDirectory(base) {
            return [PackageFile(path: (base as NSString).lastPathComponent, data: try read(base))]
        }
        let prefix = base == "/" ? "/" : base + "/"
        return try walk(base).map { p in
            PackageFile(path: String(p.dropFirst(prefix.count)), data: try read(p), executable: p.hasSuffix(".sh"))
        }
    }

    var totalSize: Int { walk().reduce(0) { $0 + ((try? entrySize($1)) ?? 0) } }

    private func entrySize(_ path: String) throws -> Int {
        ((try fm.attributesOfItem(atPath: try url(path).path))[.size] as? NSNumber)?.intValue ?? 0
    }

    /// Shell-style wildcard match (*, ?, [abc]).
    static func glob(_ pattern: String, _ name: String) -> Bool {
        let p = Array(pattern), n = Array(name)
        func match(_ i: Int, _ j: Int) -> Bool {
            if i == p.count { return j == n.count }
            switch p[i] {
            case "*":
                var k = j
                while k <= n.count { if match(i + 1, k) { return true }; k += 1 }
                return false
            case "?": return j < n.count && match(i + 1, j + 1)
            case "[":
                guard let close = p[(i + 1)...].firstIndex(of: "]"), j < n.count else { return false }
                let set = p[(i + 1)..<close]
                return set.contains(n[j]) && match(close + 1, j + 1)
            default: return j < n.count && p[i] == n[j] && match(i + 1, j + 1)
            }
        }
        return match(0, 0)
    }
}

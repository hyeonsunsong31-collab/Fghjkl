import Foundation

/// One adjustment or build request stacked on a workspace's product.
struct WorkRequest: Codable, Identifiable, Equatable {
    enum Status: String, Codable { case queued, running, done, failed, cancelled }

    var id: String = UUID().uuidString
    var text: String
    var created = Date()
    var status: Status = .queued
    /// What was done, or exactly what still fails.
    var summary: String?
    /// Version produced by this request.
    var version: Int?
    var attempts = 0
    /// Verification results ("✓ no runtime errors", "✗ score never changes").
    var checks: [String] = []
    var korean = false
    var started: Date?
    var finished: Date?
}

struct WorkVersion: Codable, Equatable {
    var number: Int
    var created: Date
    var summary: String
    var requestID: String?
    var fileCount: Int
    var bytes: Int
}

/// What the workspace holds: kind, title, main file, how it was made.
struct ProductInfo: Codable, Equatable {
    var kind: String            // game, website, app, ai, tool, file, rom, program …
    var title: String
    var entry: String?          // main file, e.g. /index.html
    var template: String?       // program library template, when one was used
    var brief: String?          // JSON of the ProgramBrief (for adjustments)
    var stack: String?          // html, javascript, python …
    var origin: String?         // "generated", "imported: game.zip"
}

struct Workspace: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var created = Date()
    var updated = Date()
    var product: ProductInfo?
    var requests: [WorkRequest] = []
    var versions: [WorkVersion] = []
    /// "self" (Jarvis's own scripts) or "source" (Jarvis.swiftpm), else nil.
    var special: String?

    var pending: [WorkRequest] { requests.filter { $0.status == .queued || $0.status == .running } }
    var latestVersion: Int { versions.last?.number ?? 0 }
}

/// Workspace slots: each has its own files, product, stacked requests and version history.
/// Layout: <root>/index.json, <root>/<id>/workspace.json, <root>/<id>/files/, <root>/<id>/versions/<n>/.
final class WorkspaceStore {
    let root: URL
    private(set) var workspaces: [Workspace] = []
    private(set) var activeID: String?
    /// Folders outside the store used as a workspace's files (Jarvis's own source, granted by the user).
    var externalRoots: [String: URL] = [:]
    private let fm = FileManager.default

    init(root: URL) {
        self.root = root
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    private struct Index: Codable {
        var order: [String]
        var active: String?
    }

    private func load() {
        let index = (try? Data(contentsOf: root.appendingPathComponent("index.json"))).flatMap { try? JSONDecoder().decode(Index.self, from: $0) }
        var found: [Workspace] = []
        let ids = index?.order ?? ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        for id in ids {
            let file = root.appendingPathComponent(id).appendingPathComponent("workspace.json")
            if let data = try? Data(contentsOf: file), var ws = try? decoder.decode(Workspace.self, from: data) {
                // A request that was running when the app stopped resumes as queued.
                for i in ws.requests.indices where ws.requests[i].status == .running { ws.requests[i].status = .queued }
                found.append(ws)
            }
        }
        workspaces = found
        activeID = index?.active.flatMap { id in found.contains { $0.id == id } ? id : nil } ?? found.first?.id
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func saveIndex() {
        let index = Index(order: workspaces.map(\.id), active: activeID)
        try? encoder.encode(index).write(to: root.appendingPathComponent("index.json"), options: .atomic)
    }

    func save(_ ws: Workspace) {
        var w = ws
        w.updated = Date()
        if let i = workspaces.firstIndex(where: { $0.id == w.id }) { workspaces[i] = w } else { workspaces.append(w) }
        let dir = root.appendingPathComponent(w.id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? encoder.encode(w).write(to: dir.appendingPathComponent("workspace.json"), options: .atomic)
        saveIndex()
    }

    // MARK: Slots

    var active: Workspace? { activeID.flatMap(workspace) }

    func workspace(_ id: String) -> Workspace? { workspaces.first { $0.id == id } }

    /// Find by id or (fuzzy) name.
    func find(_ nameOrID: String) -> Workspace? {
        let q = nameOrID.lowercased().trimmingCharacters(in: .whitespaces)
        if let w = workspaces.first(where: { $0.id == q || $0.name.lowercased() == q }) { return w }
        if let n = Int(q), n >= 1, n <= workspaces.count { return workspaces[n - 1] }
        return workspaces.first { $0.name.lowercased().contains(q) || q.contains($0.name.lowercased()) }
    }

    @discardableResult
    func create(name: String, special: String? = nil) -> Workspace {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var finalName = base.isEmpty ? "Workspace \(workspaces.count + 1)" : base
        var n = 2
        while workspaces.contains(where: { $0.name.lowercased() == finalName.lowercased() }) { finalName = "\(base) \(n)"; n += 1 }
        let slug = String(finalName.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.prefix(24))
        let id = "\(slug)-\(UUID().uuidString.prefix(6).lowercased())"
        let ws = Workspace(id: id, name: finalName, special: special)
        save(ws)
        _ = files(id)
        activeID = id
        saveIndex()
        return ws
    }

    func activate(_ id: String) {
        guard workspace(id) != nil else { return }
        activeID = id
        saveIndex()
    }

    func rename(_ id: String, to name: String) {
        guard var ws = workspace(id) else { return }
        ws.name = name
        save(ws)
    }

    func delete(_ id: String) {
        try? fm.removeItem(at: root.appendingPathComponent(id))
        workspaces.removeAll { $0.id == id }
        if activeID == id { activeID = workspaces.first?.id }
        saveIndex()
    }

    /// The workspace's files.
    func files(_ id: String) -> SandboxFS {
        if let external = externalRoots[id] { return SandboxFS(root: external) }
        return SandboxFS(root: root.appendingPathComponent(id).appendingPathComponent("files"))
    }

    // MARK: Requests

    @discardableResult
    func enqueue(_ text: String, in id: String, korean: Bool) -> WorkRequest? {
        guard var ws = workspace(id) else { return nil }
        let r = WorkRequest(text: text, korean: korean)
        ws.requests.append(r)
        save(ws)
        return r
    }

    func update(_ request: WorkRequest, in id: String) {
        guard var ws = workspace(id), let i = ws.requests.firstIndex(where: { $0.id == request.id }) else { return }
        ws.requests[i] = request
        save(ws)
    }

    func nextQueued(in id: String) -> WorkRequest? { workspace(id)?.requests.first { $0.status == .queued } }

    func setProduct(_ product: ProductInfo?, in id: String) {
        guard var ws = workspace(id) else { return }
        ws.product = product
        save(ws)
    }

    // MARK: Versions

    private func versionsDir(_ id: String) -> URL { root.appendingPathComponent(id).appendingPathComponent("versions") }

    /// Snapshot the current files as a new version (APFS clones make this cheap on the device).
    @discardableResult
    func snapshot(_ id: String, summary: String, requestID: String? = nil) throws -> WorkVersion {
        guard var ws = workspace(id) else { throw SandboxError.notFound(id) }
        let number = ws.latestVersion + 1
        let dest = versionsDir(id).appendingPathComponent(String(number))
        try fm.createDirectory(at: versionsDir(id), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        let source = files(id)
        try fm.copyItem(at: source.root, to: dest)
        let paths = source.walk()
        let bytes = paths.reduce(0) { $0 + ((try? source.read($1).count) ?? 0) }
        let v = WorkVersion(number: number, created: Date(), summary: summary, requestID: requestID, fileCount: paths.count, bytes: bytes)
        ws.versions.append(v)
        save(ws)
        return v
    }

    func versionFiles(_ id: String, _ number: Int) -> SandboxFS? {
        let dir = versionsDir(id).appendingPathComponent(String(number))
        return fm.fileExists(atPath: dir.path) ? SandboxFS(root: dir) : nil
    }

    /// Put the files of an earlier version back (the current files become a new version first).
    func restore(_ id: String, version number: Int) throws {
        guard let snapshotFS = versionFiles(id, number) else { throw SandboxError.notFound("version \(number)") }
        try snapshot(id, summary: "before restoring version \(number)")
        let current = files(id)
        for entry in (try? current.list("/", hidden: true)) ?? [] { try? current.remove(entry.path, recursive: true) }
        for path in snapshotFS.walk(hidden: true) { try current.write(path, try snapshotFS.read(path)) }
        try snapshot(id, summary: "restored version \(number)")
    }

    /// What changed between two versions (0 = current files).
    func changes(_ id: String, from a: Int, to b: Int = 0, diffs: Bool = true) -> String {
        guard let left = a == 0 ? files(id) : versionFiles(id, a), let right = b == 0 ? files(id) : versionFiles(id, b) else { return "unknown version" }
        let l = Set(left.walk()), r = Set(right.walk())
        var out: [String] = []
        for p in r.subtracting(l).sorted() { out.append("+ added \(p)") }
        for p in l.subtracting(r).sorted() { out.append("- removed \(p)") }
        for p in l.intersection(r).sorted() {
            guard let x = try? left.read(p), let y = try? right.read(p), x != y else { continue }
            if diffs, let tx = TextSniffer.decode(x), let ty = TextSniffer.decode(y) {
                out.append(TextDiff.unified(tx, ty, oldName: "v\(a)\(p)", newName: (b == 0 ? "now" : "v\(b)") + p))
            } else {
                out.append("~ changed \(p) (\(x.count) → \(y.count) bytes)")
            }
        }
        return out.isEmpty ? "no differences" : out.joined(separator: "\n")
    }

    // MARK: Import

    /// Bring a file into a workspace; archives can be unpacked into a folder.
    @discardableResult
    func importFile(named name: String, data: [UInt8], into id: String, unpack: Bool = false) throws -> [String] {
        let fs = files(id)
        let clean = Packager.sanitizedName((name as NSString).lastPathComponent)
        if unpack, let items = try? FormatConverter.unpack(data, filename: clean), !items.isEmpty {
            let folder = FormatConverter.baseName(clean)
            for item in items { try fs.write("/\(folder)/\(item.path)", item.data) }
            return items.map { "/\(folder)/\($0.path)" }
        }
        try fs.write("/" + clean, data)
        return ["/" + clean]
    }
}

import SwiftUI
import UIKit
import os

/// The local development studio inside Jarvis: workspace slots, each with its own files,
/// stacked requests, versions and a terminal (the Jarvis shell). Requests build or adjust the
/// workspace's product; web products get a preview and a link, file products a file to share.
@MainActor
@Observable
final class StudioController {
    static let shared = StudioController()

    struct TerminalLine: Identifiable, Equatable {
        enum Kind: Equatable { case input, output, error, info }
        let id = UUID()
        var text: String
        var kind: Kind
    }

    /// A finished file the user can save or send.
    struct Delivery: Identifiable, Equatable {
        let id = UUID()
        var url: URL
        var title: String
    }

    @ObservationIgnored let store: WorkspaceStore
    private(set) var workspaces: [Workspace] = []
    private(set) var activeID: String?
    private(set) var lines: [TerminalLine] = []
    private(set) var fileList: [String] = []
    private(set) var busy = false
    /// The web product shown in the preview tab.
    var previewURL: URL?
    var previewReload = 0
    /// A link other devices on the same Wi-Fi can open while Jarvis runs.
    private(set) var shareLink: URL?
    var delivery: Delivery?
    @ObservationIgnored private var shells: [String: Shell] = [:]
    @ObservationIgnored private var transcripts: [String: [TerminalLine]] = [:]
    @ObservationIgnored let host = StudioHost()
    /// A request finished: the request, its outcome and the product's link (web products).
    @ObservationIgnored var onFinished: ((WorkRequest, Outcome, URL?) -> Void)?
    @ObservationIgnored private var queueTask: Task<Void, Never>?

    private init() {
        store = WorkspaceStore(root: JarvisPaths.root.appendingPathComponent("Workspaces", isDirectory: true))
        if store.workspaces.isEmpty { _ = store.create(name: "Workspace 1") }
        if store.activeID == nil, let first = store.workspaces.first { store.activate(first.id) }
        host.controller = self
        refresh()
    }

    var active: Workspace? { activeID.flatMap { store.workspace($0) } }

    func refresh() {
        workspaces = store.workspaces
        activeID = store.activeID
        if let id = activeID {
            fileList = store.files(id).walk().sorted()
            lines = transcripts[id] ?? []
        } else {
            fileList = []
            lines = []
        }
    }

    // MARK: Workspaces

    @discardableResult
    func newWorkspace(_ name: String? = nil) -> Workspace {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ws = store.create(name: (n?.isEmpty ?? true) ? "Workspace \(store.workspaces.count + 1)" : n!)
        store.activate(ws.id)
        refresh()
        return ws
    }

    func select(_ id: String) {
        store.activate(id)
        previewURL = nil
        shareLink = nil
        refresh()
    }

    func rename(_ id: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        store.rename(id, to: clean)
        refresh()
    }

    func delete(_ id: String) {
        store.delete(id)
        shells[id] = nil
        transcripts[id] = nil
        if store.workspaces.isEmpty { _ = store.create(name: "Workspace 1") }
        if store.activeID == nil, let first = store.workspaces.first { store.activate(first.id) }
        refresh()
    }

    func shell(for id: String) -> Shell {
        if let s = shells[id] { return s }
        let s = Shell(fs: store.files(id), store: store, workspaceID: id, host: host)
        shells[id] = s
        return s
    }

    // MARK: Terminal

    func log(_ text: String, _ kind: TerminalLine.Kind = .info) {
        guard let id = activeID else { return }
        var t = transcripts[id] ?? []
        t.append(TerminalLine(text: text, kind: kind))
        if t.count > 600 { t.removeFirst(t.count - 600) }
        transcripts[id] = t
        lines = t
    }

    /// Run a command line in the active workspace's shell.
    func run(_ line: String) async {
        let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let id = activeID else { return }
        log("$ " + clean, .input)
        busy = true
        let out = await shell(for: id).run(clean)
        busy = false
        let text = out.combined.trimmingCharacters(in: .newlines)
        if !text.isEmpty { log(text, out.status == 0 ? .output : .error) }
        refresh()
    }

    // MARK: Requests

    /// Stack a build or adjustment request on the active workspace and work through the queue.
    @discardableResult
    func request(_ text: String, korean: Bool) -> String {
        guard let id = activeID else { return "" }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        store.enqueue(clean, in: id, korean: korean)
        log("▶ " + clean, .input)
        refresh()
        processQueue()
        return id
    }

    func processQueue() {
        guard queueTask == nil else { return }
        queueTask = Task { [weak self] in
            while let self, let id = self.activeID, var next = self.store.nextQueued(in: id) {
                next.status = .running
                next.started = Date()
                next.attempts += 1
                self.store.update(next, in: id)
                self.busy = true
                let outcome = await self.carryOut(next, in: id)
                next.status = outcome.ok ? .done : .failed
                next.summary = outcome.summary
                next.checks = outcome.checks
                next.version = outcome.version
                next.finished = Date()
                self.store.update(next, in: id)
                self.log((outcome.ok ? "✓ " : "✗ ") + outcome.summary, outcome.ok ? .output : .error)
                self.busy = false
                self.refresh()
                self.onFinished?(next, outcome, self.previewURL == nil ? nil : self.shareLink)
            }
            self?.queueTask = nil
        }
    }

    struct Outcome {
        var ok: Bool
        var summary: String
        var checks: [String] = []
        var version: Int?
    }

    /// Build a new product from the request, or apply it to the product already here.
    private func carryOut(_ r: WorkRequest, in id: String) async -> Outcome {
        let fs = store.files(id)
        let existing = store.workspace(id)?.product
        var brief = ProgramBrief.parse(r.text)
        if let json = existing?.brief, let old = try? JSONDecoder().decode(ProgramBrief.self, from: Data(json.utf8)),
           brief.template == nil || brief.template == old.template {
            // An adjustment of what is already here ("make the snake faster", "add a timer").
            brief = old.refined(by: brief, editText: r.text)
        }
        guard let build = ProgramLibrary.build(brief) else {
            let what: String = brief.template ?? brief.kind
            let msg = r.korean
                ? "아직 '\(what)'(을)를 직접 만들 수 있는 템플릿이 없습니다. 터미널에서 파일을 직접 편집하거나 'ai 요청'으로 코딩 에이전트를 사용할 수 있습니다."
                : "I have no tested template for '\(what)' yet. You can edit the files in the terminal, or use 'ai <request>' for the coding agent."
            return Outcome(ok: false, summary: msg)
        }
        do {
            for (path, content) in build.files { try fs.writeText(path, content) }
            let product = ProductInfo(kind: build.kind, title: build.title, entry: build.entry, template: build.template,
                                      brief: String(data: (try? JSONEncoder().encode(brief)) ?? Data(), encoding: .utf8),
                                      stack: "html", origin: existing?.origin ?? "generated")
            store.setProduct(product, in: id)
            let version = try store.snapshot(id, summary: r.text, requestID: r.id)
            refresh()
            let checks = await host.verify(entryURL: fs.root.appendingPathComponent(String(build.entry.dropFirst())))
            await showPreview(of: id)
            let failed = checks.filter { $0.hasPrefix("✗") }
            let made = r.korean ? "\(build.title) 완성 (버전 \(version.number))" : "\(build.title) is ready (version \(version.number))"
            let missing = build.unhandled.isEmpty ? "" : (r.korean ? " · 아직 없는 것: " : " · not included yet: ") + build.unhandled.joined(separator: ", ")
            return Outcome(ok: failed.isEmpty, summary: made + missing, checks: checks, version: version.number)
        } catch {
            return Outcome(ok: false, summary: "\(error)")
        }
    }

    /// A path as one shell word.
    static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Preview, links and files

    func showPreview(of id: String? = nil) async {
        guard let wid = id ?? activeID, let ws = store.workspace(wid) else { return }
        let fs = store.files(wid)
        let entry = ws.product?.entry ?? "/index.html"
        guard fs.exists(entry), entry.lowercased().hasSuffix(".html") || entry.lowercased().hasSuffix(".htm") else { return }
        previewURL = fs.root.appendingPathComponent(String(entry.dropFirst()))
        previewReload += 1
        if let link = await host.link(for: fs.root) {
            shareLink = link.appendingPathComponent(String(entry.dropFirst()))
        }
    }

    /// Package the active product as a file (zip, exe, app, sh or single html) and offer it.
    func deliver(as format: String) async {
        guard let id = activeID else { return }
        let title: String = active?.product?.title ?? active?.name ?? "product"
        let safe = Packager.sanitizedName(title.replacingOccurrences(of: " ", with: "-"))
        let ext: String = format == "app" ? "app.zip" : format
        let out = "/dist/\(safe).\(ext)"
        await run("pack \(format) / -o \(Self.quote(out))")
        let fs = store.files(id)
        guard fs.exists(out), let url = try? fs.url(out) else { return }
        delivery = Delivery(url: url, title: (out as NSString).lastPathComponent)
    }

    /// Bring a file the user picked into the active workspace (archives are unpacked too).
    func importFile(_ url: URL) async {
        guard let id = activeID else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            log("could not read \(url.lastPathComponent)", .error)
            return
        }
        do {
            let name = url.lastPathComponent
            let paths = try store.importFile(named: name, data: [UInt8](data), into: id, unpack: false)
            log("imported \(name) (\(data.count) bytes)", .output)
            if store.workspace(id)?.product == nil {
                store.setProduct(ProductInfo(kind: "file", title: (name as NSString).deletingPathExtension, entry: paths.first, origin: "imported: \(name)"), in: id)
            }
            refresh()
            if let p = paths.first { await run("inspect \(Self.quote(p))") }
        } catch {
            log("\(error)", .error)
        }
    }
}

import XCTest
@testable import JarvisCore

final class StudioShellTests: XCTestCase {
    var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-studio-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func makeShell() -> (WorkspaceStore, Shell) {
        let store = WorkspaceStore(root: root)
        let ws = store.create(name: "Arcade")
        return (store, Shell(fs: store.files(ws.id), store: store, workspaceID: ws.id))
    }

    func testDiffAndPatch() throws {
        let old = (1...40).map { "line \($0)" }.joined(separator: "\n") + "\n"
        var newLines = (1...40).map { "line \($0)" }
        newLines[4] = "line five (changed)"
        newLines.insert("inserted after 20", at: 20)
        newLines.remove(at: 35)
        let new = newLines.joined(separator: "\n") + "\n"
        let patch = TextDiff.unified(old, new)
        XCTAssertTrue(patch.contains("-line 5\n+line five (changed)"))
        XCTAssertEqual(try TextDiff.apply(patch, to: old), new)
        // The file moved on a little (two lines added at the top): the patch still applies.
        let shifted = "header 1\nheader 2\n" + old
        XCTAssertEqual(try TextDiff.apply(patch, to: shifted), "header 1\nheader 2\n" + new)
        XCTAssertEqual(TextDiff.unified(old, old), "")
        XCTAssertThrowsError(try TextDiff.apply(patch, to: "something else entirely\n"))
    }

    func testSandboxKeepsPathsInside() throws {
        let fs = SandboxFS(root: root.appendingPathComponent("box"))
        XCTAssertEqual(SandboxFS.normalize("../../etc/passwd", cwd: "/src"), "/etc/passwd")
        try fs.writeText("../../../escape.txt", "x", cwd: "/a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("box/escape.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.txt").path))
        XCTAssertThrowsError(try fs.remove("/"))
        XCTAssertTrue(SandboxFS.glob("*.js", "game.js"))
        XCTAssertFalse(SandboxFS.glob("*.js", "game.json"))
        XCTAssertTrue(SandboxFS.glob("level[12].map", "level2.map"))
    }

    func testShellBasics() async throws {
        let (_, sh) = makeShell()
        _ = await sh.run("mkdir -p src/js")
        _ = await sh.run("echo hello > src/a.txt; echo world >> src/a.txt")
        var out = await sh.run("cat src/a.txt")
        XCTAssertEqual(out.text, "hello\nworld\n")
        out = await sh.run("cat src/a.txt | grep -n wor")
        XCTAssertEqual(out.text, "2:world\n")
        out = await sh.run("wc -l src/a.txt")
        XCTAssertTrue(out.text.hasPrefix("2"))
        out = await sh.run("cd src && pwd")
        XCTAssertEqual(out.text, "/src\n")
        out = await sh.run("ls *.txt")
        XCTAssertEqual(out.text, "a.txt\n")
        _ = await sh.run("cd /")
        _ = await sh.run("sed -i 's/world/there/' src/a.txt")
        out = await sh.run("replace there Jarvis src/a.txt")
        XCTAssertTrue(out.text.contains("1 replacement"))
        out = await sh.run("cat src/a.txt")
        XCTAssertEqual(out.text, "hello\nJarvis\n")
        out = await sh.run("false || echo recovered; true && echo chained")
        XCTAssertEqual(out.text, "recovered\nchained\n")
        out = await sh.run("NAME=Ana; echo \"hi $NAME\" 'and $NAME'")
        XCTAssertEqual(out.text, "hi Ana and $NAME\n")
        out = await sh.run("echo one two | wc -w")
        XCTAssertEqual(out.text.trimmingCharacters(in: .whitespacesAndNewlines), "2")
        out = await sh.run("printf '%s=%s\\n' speed 7 > cfg.ini; cat cfg.ini")
        XCTAssertEqual(out.text, "speed=7\n")
        out = await sh.run("cat missing.txt")
        XCTAssertNotEqual(out.status, 0)
        XCTAssertTrue(out.stderr.contains("no such file"))
        out = await sh.run("frobnicate")
        XCTAssertEqual(out.status, 127)
        out = await sh.run("npm install three")
        XCTAssertTrue(out.stderr.contains("lib add"))
        out = await sh.run("help")
        XCTAssertTrue(out.text.contains("[Binaries & ROMs]"))
    }

    func testShellArchivesConversionAndPackaging() async throws {
        let (_, sh) = makeShell()
        _ = await sh.run("mkdir site")
        try sh.fs.writeText("/site/index.html", "<!DOCTYPE html><html><body><script src=\"app.js\"></script></body></html>")
        try sh.fs.writeText("/site/app.js", "document.body.textContent = 'ok';")
        try sh.fs.writeText("/settings.ini", "[game]\nspeed = 7\nname = Hopper\n")
        var out = await sh.run("zip site.zip site")
        XCTAssertTrue(out.text.contains("2 file(s)"))
        out = await sh.run("unzip -l site.zip")
        XCTAssertTrue(out.text.contains("site/index.html"))
        out = await sh.run("unzip site.zip -d copy && ls copy/site")
        XCTAssertTrue(out.text.contains("index.html"))
        out = await sh.run("tar -czf site.tgz site && tar -tzf site.tgz")
        XCTAssertTrue(out.text.contains("site/app.js"))
        out = await sh.run("convert settings.ini --to json")
        XCTAssertTrue(out.text.contains("/settings.json"))
        out = await sh.run("cat settings.json")
        XCTAssertTrue(out.text.contains("\"speed\": 7"))
        out = await sh.run("convert settings.ini settings.yaml && cat settings.yaml")
        XCTAssertTrue(out.text.contains("speed: 7"))
        out = await sh.run("pack exe site --name Hopper")
        XCTAssertTrue(out.text.contains("/dist/Hopper.exe"), out.combined)
        out = await sh.run("inspect dist/Hopper.exe")
        XCTAssertTrue(out.text.contains("Windows program"))
        XCTAssertTrue(out.text.contains("Appended data"))
        out = await sh.run("unzip -l dist/Hopper.exe")
        XCTAssertTrue(out.text.contains("index.html"))
        out = await sh.run("pack html site")
        XCTAssertTrue(out.text.contains(".html"))
        out = await sh.run("run dist/Hopper.exe")
        XCTAssertEqual(out.status, 126)
        XCTAssertTrue(out.stderr.contains("no foreign executables"))
        out = await sh.run("sha256 settings.ini")
        XCTAssertEqual(out.text.count, 64 + 2 + "settings.ini".count + 1)
    }

    func testShellBinaryAndROMCommands() async throws {
        let (_, sh) = makeShell()
        try sh.fs.write("/demo.gba", StudioBinaryTests.fakeGBA())
        var out = await sh.run("file demo.gba")
        XCTAssertTrue(out.text.contains("Game Boy Advance ROM"))
        out = await sh.run("cp demo.gba hack.gba && binreplace hack.gba SRAM_V113 SRAM_V999")
        XCTAssertTrue(out.text.contains("1 replacement"))
        out = await sh.run("romtitle hack.gba 'jarvis hack'")
        XCTAssertTrue(out.text.contains("JARVIS HACK"))
        out = await sh.run("ips create demo.gba hack.gba hack.ips && ips apply hack.ips demo.gba rebuilt.gba && compare hack.gba rebuilt.gba")
        XCTAssertEqual(out.status, 0, out.combined)
        out = await sh.run("hexpatch demo.gba 0xA0 41")
        XCTAssertTrue(out.text.contains("romfix"))
        out = await sh.run("romfix demo.gba && inspect demo.gba")
        XCTAssertTrue(out.text.contains("header check OK"))
        out = await sh.run("hexdump -s 0xA0 -n 16 demo.gba")
        XCTAssertTrue(out.text.hasPrefix("000000a0  41"))
        out = await sh.run("strings -n 6 demo.gba")
        XCTAssertTrue(out.text.contains("SRAM_V113"))
        out = await sh.run("run demo.gba")
        XCTAssertTrue(out.stderr.contains("emulator"))
    }

    func testWorkspacesVersionsAndQueue() async throws {
        let (store, sh) = makeShell()
        try sh.fs.writeText("/game.js", "let speed = 5;\n")
        var out = await sh.run("git commit -m 'first version'")
        XCTAssertTrue(out.text.contains("saved v1"))
        try sh.fs.writeText("/game.js", "let speed = 9;\n")
        out = await sh.run("git status")
        XCTAssertTrue(out.text.contains("game.js"))
        out = await sh.run("git diff")
        XCTAssertTrue(out.text.contains("-let speed = 5;"))
        XCTAssertTrue(out.text.contains("+let speed = 9;"))
        out = await sh.run("versions restore 1 && cat game.js")
        XCTAssertTrue(out.text.hasSuffix("let speed = 5;\n"))
        out = await sh.run("versions list")
        XCTAssertTrue(out.text.contains("restored version 1"))

        out = await sh.run("queue add make the snake blue")
        XCTAssertTrue(out.text.contains("1 waiting"))
        out = await sh.run("queue add 뱀을 더 빠르게 해줘")
        XCTAssertTrue(out.text.contains("2 waiting"))
        XCTAssertEqual(store.nextQueued(in: sh.workspaceID)?.text, "make the snake blue")
        XCTAssertEqual(store.workspace(sh.workspaceID)?.requests.last?.korean, true)

        out = await sh.run("ws new Second")
        XCTAssertTrue(out.text.contains("Second"))
        XCTAssertFalse(sh.fs.exists("/game.js"))
        out = await sh.run("ws list")
        XCTAssertTrue(out.text.contains("* 2. Second"))
        out = await sh.run("ws use arcade")
        XCTAssertTrue(sh.fs.exists("/game.js"))

        // A fresh store reloads everything; a request left running is queued again.
        var w = try XCTUnwrap(store.workspace(sh.workspaceID))
        w.requests[0].status = .running
        store.save(w)
        let reloaded = WorkspaceStore(root: root)
        XCTAssertEqual(reloaded.workspaces.count, 2)
        XCTAssertEqual(reloaded.workspace(sh.workspaceID)?.requests.first?.status, .queued)
        XCTAssertEqual(reloaded.workspace(sh.workspaceID)?.versions.count, 3)

        // Importing an archive unpacks it into a folder.
        let zip = Packager.zip([PackageFile(path: "rom/readme.txt", data: Array("hi".utf8))])
        let paths = try reloaded.importFile(named: "pack.zip", data: zip, into: sh.workspaceID, unpack: true)
        XCTAssertEqual(paths, ["/pack/rom/readme.txt"])
    }
}

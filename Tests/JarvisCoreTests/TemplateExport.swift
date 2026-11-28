import XCTest
@testable import JarvisCore

/// Builds sample products for browser checks (tools/verify-templates.mjs). Runs only when
/// JARVIS_TEMPLATE_EXPORT names a folder; files are written (overwritten) inside it, nothing is deleted.
final class TemplateExport: XCTestCase {
    static let requests: [String] = [
        "make a snake game with a blue snake and sound",
        "벽돌깨기 게임 만들어줘 목숨 5개, 아이템도 넣어줘",
        "two player pong game, first to 5",
        "a flappy bird style game with power ups, hard",
        "space shooter game with a boss and power ups",
        "공룡 게임처럼 무한 달리기 게임 만들어줘",
        "a dodge game where I avoid falling rocks for 60 seconds",
        "make a platformer game with 2 levels and a green player",
    ]

    /// Every request above picks the intended template and builds a complete product.
    func testRequestsPickTheirTemplates() {
        let expected = ["snake", "breakout", "pong", "hopper", "shooter", "runner", "dodge", "platformer"]
        for (request, template) in zip(Self.requests, expected) {
            let brief = ProgramBrief.parse(request)
            XCTAssertEqual(brief.template, template, request)
            let build = ProgramLibrary.build(brief)
            XCTAssertNotNil(build, request)
            for file in ["/index.html", "/kit.js", "/config.js", "/game.js", "/README.md"] {
                XCTAssertFalse((build?.files[file] ?? "").isEmpty, "\(request): \(file)")
            }
        }
        let korean = ProgramLibrary.build(ProgramBrief.parse("공룡 게임처럼 무한 달리기 게임 만들어줘"))
        XCTAssertTrue(korean?.files["/config.js"]?.contains("최대한 멀리 달리세요") ?? false)
        let timed = ProgramLibrary.build(ProgramBrief.parse("a dodge game where I avoid falling rocks for 60 seconds"))
        XCTAssertTrue(timed?.files["/config.js"]?.contains("\"time\": 60") ?? false, timed?.files["/config.js"] ?? "")
    }

    func testExportTemplates() throws {
        guard let dir = ProcessInfo.processInfo.environment["JARVIS_TEMPLATE_EXPORT"], !dir.isEmpty else { throw XCTSkip("set JARVIS_TEMPLATE_EXPORT") }
        let root = URL(fileURLWithPath: dir, isDirectory: true)
        var manifest: [DataValue] = []
        for (i, request) in Self.requests.enumerated() {
            let brief = ProgramBrief.parse(request)
            guard let build = ProgramLibrary.build(brief) else { XCTFail("no template for: \(request)"); continue }
            let folder = String(format: "%02d-%@", i, build.template)
            let fs = SandboxFS(root: root.appendingPathComponent(folder))
            for (path, content) in build.files { try fs.writeText(path, content) }
            manifest.append(.object([DataPair(key: "folder", value: .string(folder)), DataPair(key: "request", value: .string(request)),
                                     DataPair(key: "template", value: .string(build.template)), DataPair(key: "kind", value: .string(build.kind)),
                                     DataPair(key: "unhandled", value: .array(build.unhandled.map { .string($0) }))]))
        }
        try JSONWriter.write(.array(manifest)).write(to: root.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    }
}

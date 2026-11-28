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
    ]

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

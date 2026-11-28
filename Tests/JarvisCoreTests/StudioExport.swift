import XCTest
@testable import JarvisCore

/// Writes sample packages for checks with outside tools (unzip, tar, Python) and on a real
/// Windows machine in CI. Runs only when JARVIS_STUDIO_EXPORT names a folder.
final class StudioExport: XCTestCase {
    static let settingsINI = "; Jarvis export sample\n[player]\nname = Ana\nspeed = 7\n"
    static let gameHTML = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Tiny</title><link rel=\"stylesheet\" href=\"style.css\"></head>"
        + "<body><canvas id=\"c\" width=\"200\" height=\"100\"></canvas><script src=\"js/game.js\"></script></body></html>\n"

    func testExportSamples() async throws {
        guard let dir = ProcessInfo.processInfo.environment["JARVIS_STUDIO_EXPORT"] else { throw XCTSkip("set JARVIS_STUDIO_EXPORT to export samples") }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func save(_ r: ConversionResult) throws { try Data(r.data).write(to: out.appendingPathComponent(r.filename)) }

        try save(try await FormatConverter.convert(Array(Self.settingsINI.utf8), filename: "settings.ini", to: "exe"))
        let site = Packager.zip([
            PackageFile(path: "index.html", data: Array(Self.gameHTML.utf8)),
            PackageFile(path: "style.css", data: Array("body{margin:0;background:#012}".utf8)),
            PackageFile(path: "js/game.js", data: Array("const c=document.getElementById('c').getContext('2d');c.fillStyle='#0ef';c.fillRect(10,10,50,50);".utf8)),
            PackageFile(path: "assets/한글 이름.txt", data: Array("유니코드 경로 테스트\n".utf8)),
        ])
        try Data(site).write(to: out.appendingPathComponent("webgame.zip"))
        for target in ["exe", "app", "sh", "tar.gz"] {
            try save(try await FormatConverter.convert(site, filename: "webgame.zip", to: target))
        }
        try Data(Self.settingsINI.utf8).write(to: out.appendingPathComponent("settings.ini"))
    }
}

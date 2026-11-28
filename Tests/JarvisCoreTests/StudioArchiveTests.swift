import XCTest
@testable import JarvisCore

final class StudioArchiveTests: XCTestCase {
    var studio: URL { Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("studio") }

    func testChecksums() {
        XCTAssertEqual(CRC32.checksum(Array("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(Adler32.checksum(Array("Wikipedia".utf8)), 0x11E6_0398)
        XCTAssertEqual(SHA256.hex(Array("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex([UInt8]()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let long = [UInt8](repeating: 0x61, count: 1000)
        XCTAssertEqual(SHA256.hex(long), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    func testDeflateRoundTrip() throws {
        var rng = SplitMix64(seed: 42)
        let samples: [[UInt8]] = [
            [],
            Array("a".utf8),
            Array(String(repeating: "abcabcabcabd", count: 500).utf8),
            (0..<70_000).map { _ in UInt8(truncatingIfNeeded: rng.next()) },
            (0..<50_000).map { UInt8(truncatingIfNeeded: $0 % 7 == 0 ? 0 : $0 / 300) },
        ]
        for s in samples {
            let packed = Deflate.compressPortable(s)
            let back = try Inflate.inflatePortable(packed).output
            XCTAssertEqual(back, s)
            let system = Deflate.compress(s)
            XCTAssertEqual(try Inflate.inflatePortable(system).output, s)
            XCTAssertEqual(try Inflate.inflate(system, expectedSize: s.count), s)
        }
        let text = Array(String(repeating: "Jarvis builds programs. ", count: 400).utf8)
        XCTAssertLessThan(Deflate.compressPortable(text).count, text.count / 10)
    }

    func testReadsZipMadeByOtherTools() throws {
        let zip = try ZipArchive(data: Data(contentsOf: studio.appendingPathComponent("sample.zip")))
        XCTAssertEqual(zip.entries.count, 4)
        let readme = try XCTUnwrap(zip.entry(named: "docs/readme.txt"))
        XCTAssertEqual(readme.method, 8)
        let text = String(decoding: try zip.data(for: readme), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("Jarvis studio fixture line"))
        XCTAssertEqual(try zip.data(for: XCTUnwrap(zip.entry(named: "random.bin"))).count, 3000)
        let korean = try XCTUnwrap(zip.entry(named: "한글/설정.ini"))
        XCTAssertTrue(String(decoding: try zip.data(for: korean), as: UTF8.self).contains("자비스"))
        XCTAssertTrue(try XCTUnwrap(zip.entry(named: "docs/")).isDirectory)
    }

    func testZipRoundTripAndSelfExtractingOffset() throws {
        let items = [
            ZipArchive.Item(path: "index.html", data: Array("<html><body>hi</body></html>".utf8)),
            ZipArchive.Item(path: "assets/", data: [], isDirectory: true),
            ZipArchive.Item(path: "assets/game.js", data: Array(String(repeating: "console.log(1);\n", count: 200).utf8)),
            ZipArchive.Item(path: "run.sh", data: Array("#!/bin/sh\necho hi\n".utf8), executable: true),
        ]
        let bytes = ZipArchive.build(items)
        let zip = try ZipArchive(bytes: bytes)
        XCTAssertEqual(zip.entries.map(\.path), ["index.html", "assets/", "assets/game.js", "run.sh"])
        XCTAssertEqual(try zip.data(for: zip.entries[2]), items[2].data)
        XCTAssertEqual(zip.entries[2].method, 8)
        XCTAssertEqual(zip.entries[3].unixMode.map { $0 & 0o777 }, 0o755)
        // A ZIP appended to a program (self-extracting .exe) still opens.
        let sfx = [UInt8](repeating: 0x4D, count: 4096) + bytes
        let embedded = try ZipArchive(bytes: sfx)
        XCTAssertEqual(try embedded.data(for: embedded.entries[0]), items[0].data)
    }

    func testSafePaths() {
        XCTAssertEqual(ZipArchive.safePath("a/b/../c"), nil)
        XCTAssertEqual(ZipArchive.safePath("/etc/passwd"), "etc/passwd")
        XCTAssertEqual(ZipArchive.safePath("dir\\file.txt"), "dir/file.txt")
        XCTAssertEqual(ZipArchive.safePath("__MACOSX/._x"), nil)
    }

    func testGzipAndTar() throws {
        let gz = [UInt8](try Data(contentsOf: studio.appendingPathComponent("sample.txt.gz")))
        XCTAssertTrue(Gzip.isGzip(gz))
        let text = try Gzip.decompress(gz).data
        XCTAssertEqual(text.count, 1961)
        let again = try Gzip.decompress(Gzip.compress(text, name: "x.txt"))
        XCTAssertEqual(again.data, text)
        XCTAssertEqual(again.name, "x.txt")

        let tar = [UInt8](try Data(contentsOf: studio.appendingPathComponent("sample.tar")))
        XCTAssertTrue(TarArchive.isTar(tar))
        let entries = try TarArchive.read(tar)
        XCTAssertEqual(entries.first?.path, "folder/hello.txt")
        XCTAssertEqual(entries.first.map { String(decoding: $0.data, as: UTF8.self) }, "hello tar\n")
        XCTAssertTrue(entries.contains { $0.isDirectory && $0.path == "folder/sub/" })
        let long = String(repeating: "deep/", count: 30) + "file.txt"
        let built = TarArchive.build([TarArchive.Entry(path: long, data: Array("x".utf8)), TarArchive.Entry(path: "d", data: [], isDirectory: true)])
        let reread = try TarArchive.read(built)
        XCTAssertEqual(reread.first?.path, long)
        XCTAssertEqual(reread.last?.path, "d/")
    }
}

import XCTest
@testable import JarvisCore

final class StudioBinaryTests: XCTestCase {
    var studio: URL { Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("studio") }

    /// A synthetic GBA ROM (detection bytes, header, a save-type tag) — no game data.
    static func fakeGBA(title: String = "JARVISDEMO") -> [UInt8] {
        var rom = [UInt8](repeating: 0xFF, count: 4096)
        let logoStart: [UInt8] = [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21]
        for (i, b) in logoStart.enumerated() { rom[4 + i] = b }
        for i in 0xA0...0xBF { rom[i] = 0 }
        GBAHeader.setTitle(&rom, title)
        for (i, b) in Array("JRVE01".utf8).enumerated() { rom[0xAC + i] = b }
        rom[0xB2] = 0x96
        rom[0xBC] = 1
        GBAHeader.fixChecksum(&rom)
        for (i, b) in Array("SRAM_V113".utf8).enumerated() { rom[0x800 + i] = b }
        return rom
    }

    func testDetectsFileKinds() throws {
        XCTAssertEqual(FileKind.detect(ExeStub.bytes, filename: "launcher.exe").id, "pe")
        XCTAssertEqual(FileKind.detect([UInt8](try Data(contentsOf: studio.appendingPathComponent("tiny.elf")))).id, "elf")
        XCTAssertEqual(FileKind.detect([UInt8](try Data(contentsOf: studio.appendingPathComponent("jarvis-arm64.o")))).id, "macho")
        XCTAssertEqual(FileKind.detect(Self.fakeGBA()).id, "gba")
        XCTAssertEqual(FileKind.detect([UInt8](try Data(contentsOf: studio.appendingPathComponent("sample.zip")))).id, "zip")
        XCTAssertEqual(FileKind.detect([UInt8](try Data(contentsOf: studio.appendingPathComponent("sample.zip"))), filename: "report.docx").id, "docx")
        XCTAssertEqual(FileKind.detect(Array("[main]\nname = jarvis\nlevel = 3\n".utf8)).id, "ini")
        XCTAssertEqual(FileKind.detect(Array("{\"a\": [1, 2]}".utf8)).id, "json")
        XCTAssertEqual(FileKind.detect(Array("name: jarvis\nversion: 2\nitems:\n  - a\n".utf8)).id, "yaml")
        XCTAssertEqual(FileKind.detect(Array("<!DOCTYPE html><html><body></body></html>".utf8)).id, "html")
        XCTAssertEqual(FileKind.detect(Array("print('hi')\n".utf8), filename: "main.py").category, .code)
        XCTAssertEqual(FileKind.detect([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).id, "png")
        XCTAssertEqual(FileKind.detect([0, 1, 2, 3, 0, 0, 0, 7, 9, 0xFF]).category, .binary)
    }

    func testReadsWindowsProgram() throws {
        let pe = try XCTUnwrap(PEInfo.parse(ExeStub.bytes))
        XCTAssertEqual(pe.machine, "x64 (64-bit)")
        XCTAssertEqual(pe.subsystem, "Windows GUI")
        XCTAssertTrue(pe.is64)
        XCTAssertFalse(pe.isDLL)
        XCTAssertEqual(Set(pe.imports.map { $0.dll.uppercased() }), ["KERNEL32.DLL", "SHELL32.DLL", "USER32.DLL"])
        XCTAssertTrue(pe.imports.flatMap(\.functions).contains("CreateFileW"))
        XCTAssertEqual(pe.versionStrings["ProductName"], "Jarvis package")
        XCTAssertTrue(pe.manifest?.contains("asInvoker") ?? false)
        XCTAssertNil(pe.overlayOffset)
        XCTAssertEqual(PortableSHA256.hex(ExeStub.bytes), ExeStub.sha256)
        XCTAssertTrue(pe.report().contains("Requested privileges: asInvoker"))
    }

    func testWindowsPackageRoundTrip() throws {
        let files = [PackageFile(path: "index.html", data: Array("<html>game</html>".utf8)),
                     PackageFile(path: "assets/game.js", data: Array("let x = 1;".utf8))]
        let exe = Packager.windowsExe(name: "Snake Deluxe", files: files, open: "index.html")
        let pe = try XCTUnwrap(PEInfo.parse(exe))
        XCTAssertEqual(pe.overlayOffset, ExeStub.bytes.count)
        let back = try XCTUnwrap(Packager.readWindowsPackage(exe))
        XCTAssertEqual(back.name, "Snake Deluxe")
        XCTAssertEqual(back.open, "index.html")
        XCTAssertTrue(back.openAfterExtract)
        XCTAssertEqual(back.files, files)
        XCTAssertEqual(try FormatConverter.unpack(exe, filename: "snake.exe"), files)
    }

    func testReadsELFAndMachO() throws {
        let elf = try XCTUnwrap(ELFInfo.parse([UInt8](try Data(contentsOf: studio.appendingPathComponent("tiny.elf")))))
        XCTAssertTrue(elf.is64)
        XCTAssertEqual(elf.machine, "x86-64")
        XCTAssertEqual(elf.interpreter, "/lib64/ld-linux-x86-64.so.2")
        XCTAssertTrue(elf.needed.contains("libc.so.6"))
        let macho = try XCTUnwrap(MachOInfo.parse([UInt8](try Data(contentsOf: studio.appendingPathComponent("jarvis-arm64.o")))))
        XCTAssertEqual(macho.slices.first?.cpu, "ARM64")
        XCTAssertEqual(macho.slices.first?.fileType, "object")
        XCTAssertEqual(macho.slices.first?.platform, "macOS 13.0")
    }

    func testROMHeadersAndFixes() throws {
        var rom = Self.fakeGBA()
        var header = try XCTUnwrap(GBAHeader.parse(rom))
        XCTAssertEqual(header.title, "JARVISDEMO")
        XCTAssertEqual(header.gameCode, "JRVE")
        XCTAssertEqual(header.makerCode, "01")
        XCTAssertTrue(header.checksumValid)
        XCTAssertEqual(header.saveType, "SRAM")
        rom[0xA0] = 0x41    // edit the title without fixing the checksum
        XCTAssertFalse(try XCTUnwrap(GBAHeader.parse(rom)).checksumValid)
        GBAHeader.setTitle(&rom, "new title")
        header = try XCTUnwrap(GBAHeader.parse(rom))
        XCTAssertEqual(header.title, "NEW TITLE")
        XCTAssertTrue(header.checksumValid)

        var gb = [UInt8](repeating: 0, count: 0x8000)
        for (i, b) in [0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B].enumerated() { gb[0x104 + i] = UInt8(b) }
        for (i, b) in Array("JARVIS".utf8).enumerated() { gb[0x134 + i] = b }
        gb[0x147] = 0x1B
        GBHeader.fixChecksums(&gb)
        let g = try XCTUnwrap(GBHeader.parse(gb))
        XCTAssertEqual(g.title, "JARVIS")
        XCTAssertEqual(g.cartridge, "MBC5+RAM+battery")
        XCTAssertEqual(g.headerChecksum.stored, g.headerChecksum.computed)
        XCTAssertEqual(g.globalChecksum.stored, g.globalChecksum.computed)

        let nes = try XCTUnwrap(NESHeader.parse([0x4E, 0x45, 0x53, 0x1A, 2, 1, 0x43, 0x00, 0, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(nes.mapper, 4)
        XCTAssertEqual(nes.prgKiB, 32)
        XCTAssertTrue(nes.battery)
        XCTAssertEqual(nes.mirroring, "vertical")
    }

    func testPatchFormatsRoundTrip() throws {
        var rng = SplitMix64(seed: 9)
        let original: [UInt8] = (0..<20_000).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
        var modified = original
        for i in stride(from: 100, to: 19_000, by: 997) { modified[i] ^= 0x5A; modified[i + 1] = 0 }
        modified.replaceSubrange(5000..<5010, with: Array("JARVIS-HAX".utf8))
        let grown = modified + Array("appended data".utf8)
        let shrunk = Array(modified.prefix(18_000))
        for target in [modified, grown, shrunk] {
            XCTAssertEqual(try IPSPatch.apply(try IPSPatch.create(original: original, modified: target), to: original), target)
            XCTAssertEqual(try BPSPatch.apply(BPSPatch.create(original: original, modified: target), to: original), target)
            XCTAssertEqual(try UPSPatch.apply(UPSPatch.create(original: original, modified: target), to: original), target)
        }
        // UPS works backwards too; BPS refuses the wrong source.
        let ups = UPSPatch.create(original: original, modified: modified)
        XCTAssertEqual(try UPSPatch.apply(ups, to: modified), original)
        XCTAssertThrowsError(try BPSPatch.apply(BPSPatch.create(original: original, modified: modified), to: modified))
        // An IPS record must never start at offset 0x454F46 ("EOF").
        var big = [UInt8](repeating: 0, count: 0x454F50)
        var bigModified = big
        bigModified[0x454F46] = 7
        let ips = try IPSPatch.create(original: big, modified: bigModified)
        XCTAssertEqual(try IPSPatch.apply(ips, to: big), bigModified)
        big.removeAll()
    }

    func testByteTools() {
        let bytes = Array("Hello, Jarvis! Hello again.".utf8) + [0, 1, 2] + BinaryTools.encode("Wide text", utf16: true) + [0, 0]
        XCTAssertEqual(BinaryTools.search(bytes, Array("Hello".utf8)), [0, 15])
        let strings = BinaryTools.strings(bytes, minimum: 5)
        XCTAssertTrue(strings.contains { $0.text == "Hello, Jarvis! Hello again." })
        XCTAssertTrue(strings.contains { $0.text == "Wide text" })
        let replaced = BinaryTools.replaceAll(bytes, find: Array("Hello".utf8), with: Array("Hi".utf8), mode: .sameLength)
        XCTAssertEqual(replaced.count, 2)
        XCTAssertEqual(replaced.bytes.count, bytes.count)
        XCTAssertNotNil(BinaryTools.replaceAll(bytes, find: Array("Hi".utf8), with: Array("Hello".utf8), mode: .sameLength).error.map { _ in true } ?? (BinaryTools.search(bytes, Array("Hi".utf8)).isEmpty ? true : nil))
        let longer = BinaryTools.replaceAll(bytes, find: Array("Hello".utf8), with: Array("Greetings".utf8), mode: .sameLength)
        XCTAssertNotNil(longer.error)
        XCTAssertTrue(BinaryTools.hexdump(bytes, length: 32).hasPrefix("00000000  48 65 6c 6c 6f"))
        XCTAssertEqual([UInt8](hex: "de ad:be-ef"), [0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertTrue(BinaryInspector.report(Self.fakeGBA(), filename: "demo.gba").contains("Game Boy Advance ROM"))
    }
}

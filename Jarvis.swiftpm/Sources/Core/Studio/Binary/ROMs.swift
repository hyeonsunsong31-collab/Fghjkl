import Foundation

/// Game Boy Advance ROM header (0xA0–0xBF): title, codes, version and the complement check.
struct GBAHeader {
    var title: String
    var gameCode: String
    var makerCode: String
    var version: UInt8
    var storedComplement: UInt8
    var computedComplement: UInt8
    var saveType: String?
    var size: Int

    var checksumValid: Bool { storedComplement == computedComplement }

    static func parse(_ bytes: [UInt8]) -> GBAHeader? {
        let r = ByteReader(bytes)
        guard bytes.count >= 0xC0, r.u8(0xB2) == 0x96 else { return nil }
        var save: String?
        for tag in ["EEPROM_V", "SRAM_F_V", "SRAM_V", "FLASH1M_V", "FLASH512_V", "FLASH_V"] where save == nil {
            if r.find(Array(tag.utf8)) != nil { save = tag.replacingOccurrences(of: "_V", with: "").replacingOccurrences(of: "_F", with: " (FRAM)") }
        }
        return GBAHeader(title: r.ascii(0xA0, 12) ?? "", gameCode: r.ascii(0xAC, 4) ?? "", makerCode: r.ascii(0xB0, 2) ?? "",
                         version: r.u8(0xBC) ?? 0, storedComplement: r.u8(0xBD) ?? 0, computedComplement: complement(bytes),
                         saveType: save, size: bytes.count)
    }

    static func complement(_ bytes: [UInt8]) -> UInt8 {
        var chk = 0
        for i in 0xA0...0xBC { chk -= Int(bytes[i]) }
        return UInt8(truncatingIfNeeded: chk - 0x19)
    }

    /// Recompute the header complement (needed after editing the title or codes, or the game won't boot).
    static func fixChecksum(_ bytes: inout [UInt8]) {
        guard bytes.count >= 0xC0 else { return }
        bytes[0xBD] = complement(bytes)
    }

    /// Set the 12-character internal title (upper-case ASCII) and fix the checksum.
    static func setTitle(_ bytes: inout [UInt8], _ title: String) {
        guard bytes.count >= 0xC0 else { return }
        let ascii = Array(title.uppercased().unicodeScalars.filter { $0.isASCII && $0.value >= 0x20 }.map { UInt8($0.value) }.prefix(12))
        for i in 0..<12 { bytes[0xA0 + i] = i < ascii.count ? ascii[i] : 0 }
        fixChecksum(&bytes)
    }

    func report() -> String {
        let region: [Character: String] = ["E": "USA", "P": "Europe", "J": "Japan", "K": "Korea", "F": "France", "D": "Germany", "S": "Spain", "I": "Italy"]
        let r = gameCode.last.flatMap { region[$0] } ?? "unknown region"
        var lines = ["Game Boy Advance ROM · \"\(title)\" · code \(gameCode) (\(r)) · maker \(makerCode) · v\(version)",
                     "Size \(size / 1024) KiB (\(size >= 1 << 20 ? "\(size >> 20) MiB" : "<1 MiB")) · header check \(checksumValid ? "OK" : String(format: "WRONG (stored %02X, should be %02X)", storedComplement, computedComplement))"]
        if let s = saveType { lines.append("Save type: \(s)") }
        lines.append("Edits: `romtitle`, `hexpatch`, `replace`, `ips|bps|ups apply`; `romfix` repairs the header. Run it in a GBA emulator app (for example via Share).")
        return lines.joined(separator: "\n")
    }
}

/// Game Boy / Game Boy Color header (0x100–0x14F).
struct GBHeader {
    var title: String
    var color: Bool
    var cartridge: String
    var romSize: Int
    var ramSize: Int
    var headerChecksum: (stored: UInt8, computed: UInt8)
    var globalChecksum: (stored: UInt16, computed: UInt16)

    static func parse(_ bytes: [UInt8]) -> GBHeader? {
        let r = ByteReader(bytes)
        guard bytes.count >= 0x150, r.hasPrefix([0xCE, 0xED, 0x66, 0x66], at: 0x104) else { return nil }
        let cgb = r.u8(0x143) ?? 0
        let titleLength = cgb & 0x80 != 0 ? 11 : 16
        let carts: [UInt8: String] = [0: "ROM only", 1: "MBC1", 2: "MBC1+RAM", 3: "MBC1+RAM+battery", 5: "MBC2", 6: "MBC2+battery",
                                      0x0F: "MBC3+timer+battery", 0x10: "MBC3+timer+RAM+battery", 0x11: "MBC3", 0x13: "MBC3+RAM+battery",
                                      0x19: "MBC5", 0x1B: "MBC5+RAM+battery", 0x1E: "MBC5+rumble+RAM+battery", 0x22: "MBC7"]
        let ramSizes: [UInt8: Int] = [0: 0, 2: 8, 3: 32, 4: 128, 5: 64]
        return GBHeader(title: r.ascii(0x134, titleLength) ?? "", color: cgb & 0x80 != 0,
                        cartridge: carts[r.u8(0x147) ?? 0] ?? String(format: "type 0x%02X", r.u8(0x147) ?? 0),
                        romSize: 32 << Int(r.u8(0x148) ?? 0), ramSize: ramSizes[r.u8(0x149) ?? 0] ?? 0,
                        headerChecksum: (r.u8(0x14D) ?? 0, headerSum(bytes)),
                        globalChecksum: (r.u16be(0x14E) ?? 0, globalSum(bytes)))
    }

    static func headerSum(_ b: [UInt8]) -> UInt8 {
        var x = 0
        for i in 0x134...0x14C { x = x - Int(b[i]) - 1 }
        return UInt8(truncatingIfNeeded: x)
    }

    static func globalSum(_ b: [UInt8]) -> UInt16 {
        var sum = 0
        for (i, v) in b.enumerated() where i != 0x14E && i != 0x14F { sum &+= Int(v) }
        return UInt16(truncatingIfNeeded: sum)
    }

    static func fixChecksums(_ b: inout [UInt8]) {
        guard b.count >= 0x150 else { return }
        b[0x14D] = headerSum(b)
        let g = globalSum(b)
        b[0x14E] = UInt8(g >> 8)
        b[0x14F] = UInt8(g & 0xFF)
    }

    func report() -> String {
        let h = headerChecksum.stored == headerChecksum.computed ? "OK" : "WRONG"
        let g = globalChecksum.stored == globalChecksum.computed ? "OK" : "differs"
        return "Game Boy\(color ? " Color" : "") ROM · \"\(title)\" · \(cartridge) · ROM \(romSize) KiB · RAM \(ramSize) KiB\nHeader checksum \(h) · global checksum \(g) (`romfix` repairs both)"
    }
}

/// iNES / NES 2.0 header.
struct NESHeader {
    var prgKiB: Int
    var chrKiB: Int
    var mapper: Int
    var mirroring: String
    var battery: Bool
    var trainer: Bool
    var nes2: Bool

    static func parse(_ bytes: [UInt8]) -> NESHeader? {
        let r = ByteReader(bytes)
        guard r.hasPrefix([0x4E, 0x45, 0x53, 0x1A]), bytes.count >= 16 else { return nil }
        let f6 = bytes[6], f7 = bytes[7]
        let mapper = Int(f7 & 0xF0) | Int(f6 >> 4)
        return NESHeader(prgKiB: Int(bytes[4]) * 16, chrKiB: Int(bytes[5]) * 8, mapper: mapper,
                         mirroring: f6 & 8 != 0 ? "four-screen" : (f6 & 1 != 0 ? "vertical" : "horizontal"),
                         battery: f6 & 2 != 0, trainer: f6 & 4 != 0, nes2: f7 & 0x0C == 0x08)
    }

    func report() -> String {
        let names = [0: "NROM", 1: "MMC1", 2: "UxROM", 3: "CNROM", 4: "MMC3", 5: "MMC5", 7: "AxROM", 9: "MMC2", 66: "GxROM"]
        return "NES ROM (\(nes2 ? "NES 2.0" : "iNES")) · mapper \(mapper) \(names[mapper] ?? "") · PRG \(prgKiB) KiB · CHR \(chrKiB) KiB · \(mirroring) mirroring\(battery ? " · battery save" : "")\(trainer ? " · trainer" : "")"
    }
}

import Foundation

// MARK: - Windows PE (.exe, .dll)

/// Reads a Windows PE/COFF program: architecture, sections, imports, exports,
/// resources (version strings, manifest), .NET marker, signature and overlay data.
struct PEInfo {
    struct Section {
        var name: String
        var virtualAddress: UInt32
        var virtualSize: UInt32
        var rawOffset: UInt32
        var rawSize: UInt32
        var characteristics: UInt32
        var flags: String {
            var f = ""
            f += characteristics & 0x2000_0000 != 0 ? "x" : "-"
            f += characteristics & 0x4000_0000 != 0 ? "r" : "-"
            f += characteristics & 0x8000_0000 != 0 ? "w" : "-"
            return f
        }
    }

    var machine: String = ""
    var is64 = false
    var isDLL = false
    var subsystem = ""
    var timestamp: Date?
    var entryPoint: UInt32 = 0
    var imageBase: UInt64 = 0
    var sections: [Section] = []
    var imports: [(dll: String, functions: [String])] = []
    var exports: [String] = []
    var resourceTypes: [String: Int] = [:]
    var versionStrings: [String: String] = [:]
    var manifest: String?
    var isDotNet = false
    var isSigned = false
    var overlayOffset: Int?
    var overlaySize = 0
    var embeddedZipOffset: Int?
    var headerOffset = 0

    static func parse(_ bytes: [UInt8]) -> PEInfo? {
        let r = ByteReader(bytes)
        guard r.hasPrefix(Array("MZ".utf8)), let lfanew = r.u32(0x3C).map({ Int($0) }), r.hasPrefix([0x50, 0x45, 0, 0], at: lfanew) else { return nil }
        var info = PEInfo()
        info.headerOffset = lfanew
        let coff = lfanew + 4
        let machine = r.u16(coff) ?? 0
        let machines: [UInt16: String] = [0x14C: "x86 (32-bit)", 0x8664: "x64 (64-bit)", 0xAA64: "ARM64", 0x1C0: "ARM", 0x1C4: "ARM Thumb-2", 0x200: "Itanium"]
        info.machine = machines[machine] ?? String(format: "0x%04X", machine)
        let sectionCount = Int(r.u16(coff + 2) ?? 0)
        let stamp = r.u32(coff + 4) ?? 0
        if stamp > 0 && stamp < 4_102_444_800 { info.timestamp = Date(timeIntervalSince1970: TimeInterval(stamp)) }
        let optSize = Int(r.u16(coff + 16) ?? 0)
        let characteristics = r.u16(coff + 18) ?? 0
        info.isDLL = characteristics & 0x2000 != 0
        let opt = coff + 20
        let magic = r.u16(opt) ?? 0
        info.is64 = magic == 0x20B
        info.entryPoint = r.u32(opt + 16) ?? 0
        info.imageBase = info.is64 ? (r.u64(opt + 24) ?? 0) : UInt64(r.u32(opt + 28) ?? 0)
        let subsystems: [UInt16: String] = [1: "native", 2: "Windows GUI", 3: "console", 7: "POSIX console", 9: "Windows CE",
                                            10: "EFI application", 11: "EFI boot driver", 12: "EFI runtime driver", 14: "Xbox", 16: "boot application"]
        info.subsystem = subsystems[r.u16(opt + 68) ?? 0] ?? "unknown"
        let dirBase = opt + (info.is64 ? 112 : 96)
        let dirCount = Int(r.u32(opt + (info.is64 ? 108 : 92)) ?? 0)
        func directory(_ i: Int) -> (rva: UInt32, size: UInt32) {
            guard i < dirCount else { return (0, 0) }
            return (r.u32(dirBase + i * 8) ?? 0, r.u32(dirBase + i * 8 + 4) ?? 0)
        }
        let sectionTable = opt + optSize
        for i in 0..<Swift.min(sectionCount, 96) {
            let s = sectionTable + i * 40
            guard let name = r.ascii(s, 8) else { break }
            info.sections.append(Section(name: name, virtualAddress: r.u32(s + 12) ?? 0, virtualSize: r.u32(s + 8) ?? 0,
                                         rawOffset: r.u32(s + 20) ?? 0, rawSize: r.u32(s + 16) ?? 0, characteristics: r.u32(s + 36) ?? 0))
        }
        let sectionList = info.sections
        func offset(_ rva: UInt32) -> Int? {
            for s in sectionList {
                let size = Swift.max(s.virtualSize, s.rawSize)
                if rva >= s.virtualAddress && rva < s.virtualAddress + size {
                    let o = Int(rva - s.virtualAddress + s.rawOffset)
                    return o < bytes.count ? o : nil
                }
            }
            return Int(rva) < bytes.count && sectionList.isEmpty ? Int(rva) : nil
        }

        // Imports.
        let imp = directory(1)
        if imp.rva != 0, var d = offset(imp.rva) {
            for _ in 0..<512 {
                let nameRVA = r.u32(d + 12) ?? 0
                if nameRVA == 0 { break }
                let dll = offset(nameRVA).flatMap { r.cString($0, max: 256) } ?? "?"
                var functions: [String] = []
                let thunkRVA = (r.u32(d) ?? 0) != 0 ? (r.u32(d) ?? 0) : (r.u32(d + 16) ?? 0)
                if var t = offset(thunkRVA) {
                    for _ in 0..<4096 {
                        let value: UInt64 = info.is64 ? (r.u64(t) ?? 0) : UInt64(r.u32(t) ?? 0)
                        if value == 0 { break }
                        let ordinalFlag: UInt64 = info.is64 ? 0x8000_0000_0000_0000 : 0x8000_0000
                        if value & ordinalFlag != 0 {
                            functions.append("#\(value & 0xFFFF)")
                        } else if let o = offset(UInt32(truncatingIfNeeded: value)), let fn = r.cString(o + 2, max: 256) {
                            functions.append(fn)
                        }
                        t += info.is64 ? 8 : 4
                    }
                }
                info.imports.append((dll, functions))
                d += 20
            }
        }
        // Exports.
        let exp = directory(0)
        if exp.rva != 0, let e = offset(exp.rva) {
            let names = Int(r.u32(e + 24) ?? 0)
            if let table = offset(r.u32(e + 32) ?? 0) {
                for i in 0..<Swift.min(names, 4096) {
                    if let o = offset(r.u32(table + i * 4) ?? 0), let name = r.cString(o, max: 256) { info.exports.append(name) }
                }
            }
        }
        // Resources.
        let res = directory(2)
        if res.rva != 0, let root = offset(res.rva) {
            info.readResources(r, root: root, offset: offset)
        }
        info.isDotNet = directory(14).rva != 0
        info.isSigned = directory(4).size > 0
        // Overlay: bytes after the last section (installers, self-extracting archives, appended data).
        let end = info.sections.map { Int($0.rawOffset) + Int($0.rawSize) }.max() ?? 0
        let certificate = directory(4)
        let certEnd = certificate.size > 0 ? Int(certificate.rva) + Int(certificate.size) : 0
        let dataEnd = Swift.max(end, certificate.size > 0 && Int(certificate.rva) == end ? certEnd : end)
        if dataEnd > 0 && dataEnd < bytes.count {
            info.overlayOffset = dataEnd
            info.overlaySize = bytes.count - dataEnd
            if let z = r.find([0x50, 0x4B, 0x03, 0x04], from: dataEnd) { info.embeddedZipOffset = z }
        }
        return info
    }

    private static let resourceNames: [UInt32: String] = [1: "cursor", 2: "bitmap", 3: "icon", 4: "menu", 5: "dialog", 6: "string table",
                                                           9: "accelerators", 10: "raw data", 11: "message table", 12: "cursor group",
                                                           14: "icon group", 16: "version", 23: "HTML", 24: "manifest"]

    private mutating func readResources(_ r: ByteReader, root: Int, offset: (UInt32) -> Int?) {
        func entries(_ dir: Int) -> [(id: UInt32, named: Bool, target: UInt32)] {
            let named = Int(r.u16(dir + 12) ?? 0), ids = Int(r.u16(dir + 14) ?? 0)
            var out: [(UInt32, Bool, UInt32)] = []
            for i in 0..<Swift.min(named + ids, 512) {
                let e = dir + 16 + i * 8
                let name = r.u32(e) ?? 0
                out.append((name & 0x7FFF_FFFF, name & 0x8000_0000 != 0, r.u32(e + 4) ?? 0))
            }
            return out
        }
        for type in entries(root) {
            let typeName = type.named ? "named" : (Self.resourceNames[type.id] ?? "type \(type.id)")
            guard type.target & 0x8000_0000 != 0 else { continue }
            let nameDir = root + Int(type.target & 0x7FFF_FFFF)
            var count = 0
            for name in entries(nameDir) {
                guard name.target & 0x8000_0000 != 0 else { continue }
                let langDir = root + Int(name.target & 0x7FFF_FFFF)
                for lang in entries(langDir) where lang.target & 0x8000_0000 == 0 {
                    count += 1
                    let dataEntry = root + Int(lang.target)
                    guard let rva = r.u32(dataEntry), let size = r.u32(dataEntry + 4), let o = offset(rva),
                          let blob = r.slice(o, Int(Swift.min(size, 1 << 20))) else { continue }
                    if type.id == 16 && !type.named && versionStrings.isEmpty { versionStrings = Self.versionStrings(Array(blob)) }
                    if type.id == 24 && !type.named && manifest == nil { manifest = String(decoding: blob, as: UTF8.self) }
                }
            }
            resourceTypes[typeName, default: 0] += count
        }
    }

    /// Key/value pairs of the StringFileInfo block in a VS_VERSIONINFO resource.
    static func versionStrings(_ blob: [UInt8]) -> [String: String] {
        var out: [String: String] = [:]
        let keys = ["CompanyName", "FileDescription", "FileVersion", "InternalName", "LegalCopyright", "OriginalFilename", "ProductName", "ProductVersion", "Comments"]
        let r = ByteReader(blob)
        for key in keys {
            var needle: [UInt8] = BinaryTools.encode(key, utf16: true)
            needle += [0, 0]
            guard var p = r.find(needle) else { continue }
            p += needle.count
            while p % 4 != 0 { p += 1 }
            var chars: [UInt16] = []
            while let c = r.u16(p), c != 0, chars.count < 512 { chars.append(c); p += 2 }
            let value = String(decoding: chars, as: UTF16.self).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { out[key] = value }
        }
        return out
    }

    func report() -> String {
        var lines: [String] = []
        lines.append("Windows \(isDLL ? "DLL" : "program") · \(machine) · \(subsystem)\(isDotNet ? " · .NET assembly" : "")\(isSigned ? " · digitally signed" : " · unsigned")")
        if let t = timestamp { lines.append("Built: \(ISO8601DateFormatter().string(from: t))") }
        for key in ["ProductName", "FileDescription", "CompanyName", "FileVersion", "ProductVersion", "LegalCopyright", "OriginalFilename"] {
            if let v = versionStrings[key] { lines.append("\(key): \(v)") }
        }
        lines.append(String(format: "Entry point RVA 0x%08X · image base 0x%llX", entryPoint, imageBase))
        lines.append("Sections: " + sections.map { "\($0.name)[\($0.flags) \($0.rawSize)B]" }.joined(separator: " "))
        if !imports.isEmpty {
            lines.append("Imports (\(imports.count) DLLs):")
            for (dll, fns) in imports.prefix(24) {
                lines.append("  \(dll): " + fns.prefix(12).joined(separator: ", ") + (fns.count > 12 ? " … (+\(fns.count - 12))" : ""))
            }
        }
        if !exports.isEmpty { lines.append("Exports: " + exports.prefix(20).joined(separator: ", ") + (exports.count > 20 ? " …" : "")) }
        if !resourceTypes.isEmpty { lines.append("Resources: " + resourceTypes.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: ", ")) }
        if let m = manifest, let level = m.range(of: "level=\"") {
            let rest = m[level.upperBound...]
            lines.append("Requested privileges: " + String(rest.prefix { $0 != "\"" }))
        }
        if let o = overlayOffset {
            lines.append("Appended data: \(overlaySize) bytes at offset \(o)" + (embeddedZipOffset != nil ? " — contains a ZIP archive (self-extracting); `unzip` can open it" : ""))
        }
        if isDotNet { lines.append("Note: .NET programs hold IL bytecode; a .NET decompiler (on a PC) can recover C# source.") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - ELF (Linux, Android native libraries)

struct ELFInfo {
    var is64 = false
    var littleEndian = true
    var type = ""
    var machine = ""
    var entry: UInt64 = 0
    var sections: [String] = []
    var interpreter: String?
    var needed: [String] = []
    var osABI = ""

    static func parse(_ bytes: [UInt8]) -> ELFInfo? {
        let r = ByteReader(bytes)
        guard r.hasPrefix([0x7F, 0x45, 0x4C, 0x46]) else { return nil }
        var info = ELFInfo()
        info.is64 = r.u8(4) == 2
        info.littleEndian = r.u8(5) != 2
        let abis: [UInt8: String] = [0: "System V", 3: "Linux", 6: "Solaris", 9: "FreeBSD", 12: "OpenBSD"]
        info.osABI = abis[r.u8(7) ?? 0] ?? "other"
        func u16(_ o: Int) -> Int { Int((info.littleEndian ? r.u16(o) : r.u16be(o)) ?? 0) }
        func u32(_ o: Int) -> Int { Int((info.littleEndian ? r.u32(o) : r.u32be(o)) ?? 0) }
        func u64(_ o: Int) -> UInt64 { (info.littleEndian ? r.u64(o) : r.u64be(o)) ?? 0 }
        func addr(_ o: Int) -> Int { info.is64 ? Int(truncatingIfNeeded: u64(o)) : u32(o) }
        let types = [1: "relocatable object", 2: "executable", 3: "shared library / PIE executable", 4: "core dump"]
        info.type = types[u16(16)] ?? "type \(u16(16))"
        let machines = [3: "x86", 62: "x86-64", 40: "ARM", 183: "AArch64 (ARM64)", 243: "RISC-V", 8: "MIPS", 20: "PowerPC", 21: "PowerPC64"]
        info.machine = machines[u16(18)] ?? "machine \(u16(18))"
        info.entry = info.is64 ? u64(24) : UInt64(u32(24))
        let phoff = info.is64 ? addr(32) : u32(28)
        let shoff = info.is64 ? addr(40) : u32(32)
        let phentsize = u16(info.is64 ? 54 : 42), phnum = u16(info.is64 ? 56 : 44)
        let shentsize = u16(info.is64 ? 58 : 46), shnum = u16(info.is64 ? 60 : 48), shstrndx = u16(info.is64 ? 62 : 50)
        for i in 0..<Swift.min(phnum, 64) {
            let p = phoff + i * phentsize
            if u32(p) == 3 {   // PT_INTERP
                let off = info.is64 ? addr(p + 8) : u32(p + 4)
                info.interpreter = r.cString(off, max: 256)
            }
        }
        struct Sec { var name: Int; var type: Int; var offset: Int; var size: Int; var link: Int }
        var secs: [Sec] = []
        for i in 0..<Swift.min(shnum, 256) {
            let s = shoff + i * shentsize
            if info.is64 {
                secs.append(Sec(name: u32(s), type: u32(s + 4), offset: addr(s + 24), size: addr(s + 32), link: u32(s + 40)))
            } else {
                secs.append(Sec(name: u32(s), type: u32(s + 4), offset: u32(s + 16), size: u32(s + 20), link: u32(s + 24)))
            }
        }
        if shstrndx < secs.count {
            let strtab = secs[shstrndx].offset
            info.sections = secs.compactMap { r.cString(strtab + $0.name, max: 64) }.filter { !$0.isEmpty }
        }
        // DT_NEEDED entries from the dynamic section.
        if let dyn = secs.first(where: { $0.type == 6 }), dyn.link < secs.count {
            let strtab = secs[dyn.link].offset
            let entrySize = info.is64 ? 16 : 8
            var o = dyn.offset
            while o + entrySize <= dyn.offset + dyn.size {
                let tag = info.is64 ? Int(truncatingIfNeeded: u64(o)) : u32(o)
                let val = info.is64 ? Int(truncatingIfNeeded: u64(o + 8)) : u32(o + 4)
                if tag == 0 { break }
                if tag == 1, let name = r.cString(strtab + val, max: 256) { info.needed.append(name) }
                o += entrySize
            }
        }
        return info
    }

    func report() -> String {
        var lines = ["ELF \(is64 ? "64" : "32")-bit \(littleEndian ? "little" : "big")-endian \(type) · \(machine) · \(osABI)",
                     String(format: "Entry point 0x%llX", entry)]
        if let i = interpreter { lines.append("Loader: \(i)") }
        if !needed.isEmpty { lines.append("Libraries: " + needed.joined(separator: ", ")) }
        if !sections.isEmpty { lines.append("Sections: " + sections.prefix(30).joined(separator: " ")) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Mach-O (macOS, iOS)

struct MachOInfo {
    struct Slice {
        var cpu: String
        var is64: Bool
        var fileType: String
        var segments: [String] = []
        var libraries: [String] = []
        var signed = false
        var platform: String?
        var uuid: String?
    }
    var slices: [Slice] = []

    static func cpuName(_ type: UInt32) -> String {
        switch type {
        case 7: return "x86"
        case 0x0100_0007: return "x86-64"
        case 12: return "ARM"
        case 0x0100_000C: return "ARM64"
        case 0x0200_000C: return "ARM64_32"
        case 18: return "PowerPC"
        default: return String(format: "cpu 0x%X", type)
        }
    }

    static func parse(_ bytes: [UInt8]) -> MachOInfo? {
        let r = ByteReader(bytes)
        var info = MachOInfo()
        if r.u32be(0) == 0xCAFE_BABE {
            let n = Int(r.u32be(4) ?? 0)
            guard n > 0 && n < 30 else { return nil }
            for i in 0..<n {
                let a = 8 + i * 20
                guard let off = r.u32be(a + 8), let size = r.u32be(a + 12),
                      let sub = r.slice(Int(off), Int(size)) else { continue }
                if let s = slice(Array(sub)) { info.slices.append(s) }
            }
        } else if let s = slice(bytes) {
            info.slices.append(s)
        }
        return info.slices.isEmpty ? nil : info
    }

    private static func slice(_ b: [UInt8]) -> Slice? {
        let r = ByteReader(b)
        guard let magic = r.u32(0), [0xFEED_FACE, 0xFEED_FACF].contains(magic) else { return nil }
        let is64 = magic == 0xFEED_FACF
        let types: [UInt32: String] = [1: "object", 2: "executable", 6: "dynamic library", 7: "dynamic linker", 8: "bundle", 10: "debug symbols", 11: "kernel extension"]
        var s = Slice(cpu: cpuName(r.u32(4) ?? 0), is64: is64, fileType: types[r.u32(12) ?? 0] ?? "type \(r.u32(12) ?? 0)")
        let ncmds = Int(r.u32(16) ?? 0)
        var p = is64 ? 32 : 28
        let platforms: [UInt32: String] = [1: "macOS", 2: "iOS", 3: "tvOS", 4: "watchOS", 6: "Mac Catalyst", 7: "iOS Simulator", 11: "visionOS"]
        for _ in 0..<Swift.min(ncmds, 512) {
            guard let cmd = r.u32(p), let size = r.u32(p + 4), size >= 8 else { break }
            switch cmd {
            case 0x1, 0x19: if let name = r.ascii(p + 8, 16) { s.segments.append(name) }
            case 0xC, 0x18, 0x8000_0018, 0x1F:
                let nameOffset = Int(r.u32(p + 8) ?? 0)
                if let name = r.cString(p + nameOffset, max: 512) { s.libraries.append(name) }
            case 0x1D: s.signed = true
            case 0x1B: s.uuid = r.slice(p + 8, 16).map { Array($0).hexString.uppercased() }
            case 0x32:
                let platform = r.u32(p + 8) ?? 0
                let minos = r.u32(p + 12) ?? 0
                s.platform = "\(platforms[platform] ?? "platform \(platform)") \(minos >> 16).\((minos >> 8) & 0xFF)"
            default: break
            }
            p += Int(size)
        }
        return s
    }

    func report() -> String {
        var lines: [String] = []
        if slices.count > 1 { lines.append("Universal binary with \(slices.count) architectures") }
        for s in slices {
            lines.append("Mach-O \(s.fileType) · \(s.cpu)\(s.platform.map { " · \($0)" } ?? "") · \(s.signed ? "code-signed" : "unsigned")")
            if !s.libraries.isEmpty { lines.append("  Libraries: " + s.libraries.prefix(16).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")) }
            if !s.segments.isEmpty { lines.append("  Segments: " + s.segments.joined(separator: " ")) }
        }
        return lines.joined(separator: "\n")
    }
}

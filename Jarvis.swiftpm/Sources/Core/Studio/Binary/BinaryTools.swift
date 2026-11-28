import Foundation

/// Byte-level tools behind the terminal's `hexdump`, `strings`, `search`, `hexpatch` and `replace`.
enum BinaryTools {
    /// Classic hex dump: offset, 16 bytes in hex, ASCII column.
    static func hexdump(_ bytes: [UInt8], offset: Int = 0, length: Int = 256) -> String {
        let start = Swift.max(0, Swift.min(offset, bytes.count))
        let end = Swift.min(bytes.count, start + Swift.max(0, length))
        var lines: [String] = []
        var row = start - start % 16
        while row < end {
            var hex = ""
            var ascii = ""
            for i in row..<(row + 16) {
                if i >= start && i < end {
                    hex += String(format: "%02x ", bytes[i])
                    let b = bytes[i]
                    ascii += b >= 0x20 && b < 0x7F ? String(UnicodeScalar(b)) : "."
                } else {
                    hex += "   "
                    ascii += " "
                }
                if i == row + 7 { hex += " " }
            }
            lines.append(String(format: "%08x  ", row) + hex + " |" + ascii + "|")
            row += 16
        }
        return lines.joined(separator: "\n")
    }

    /// Printable runs (ASCII, and UTF-16LE as Windows programs store text), with offsets.
    static func strings(_ bytes: [UInt8], minimum: Int = 5, utf16: Bool = true, limit: Int = 2000) -> [(offset: Int, text: String)] {
        var out: [(Int, String)] = []
        var start = -1
        for (i, b) in bytes.enumerated() {
            let printable = (b >= 0x20 && b < 0x7F) || b == 9
            if printable {
                if start < 0 { start = i }
            } else {
                if start >= 0 && i - start >= minimum { out.append((start, String(decoding: bytes[start..<i], as: UTF8.self))) }
                start = -1
                if out.count >= limit { break }
            }
        }
        if start >= 0 && bytes.count - start >= minimum && out.count < limit { out.append((start, String(decoding: bytes[start...], as: UTF8.self))) }
        if utf16 {
            var i = 0
            var run: [UInt16] = []
            var runStart = 0
            while i + 1 < bytes.count && out.count < limit {
                let c = UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8
                let printable = (c >= 0x20 && c < 0x7F) || (c >= 0xAC00 && c <= 0xD7A3)
                if printable {
                    if run.isEmpty { runStart = i }
                    run.append(c)
                } else {
                    if run.count >= minimum { out.append((runStart, String(decoding: run, as: UTF16.self))) }
                    run = []
                }
                i += 2
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    /// Offsets of every occurrence of `pattern`.
    static func search(_ bytes: [UInt8], _ pattern: [UInt8], limit: Int = 1000) -> [Int] {
        var hits: [Int] = []
        let r = ByteReader(bytes)
        var from = 0
        while hits.count < limit, let hit = r.find(pattern, from: from) {
            hits.append(hit)
            from = hit + 1
        }
        return hits
    }

    /// Overwrite bytes at an offset (the file grows if the patch runs past its end).
    static func patch(_ bytes: [UInt8], at offset: Int, with new: [UInt8]) -> [UInt8] {
        var out = bytes
        if offset + new.count > out.count { out.append(contentsOf: [UInt8](repeating: 0, count: offset + new.count - out.count)) }
        out.replaceSubrange(offset..<(offset + new.count), with: new)
        return out
    }

    enum ReplaceMode { case sameLength, any }

    /// Replace every occurrence. In programs and ROMs the length must stay the same (code refers to
    /// fixed offsets): shorter replacements are padded with NUL (text) bytes, longer ones are refused.
    static func replaceAll(_ bytes: [UInt8], find: [UInt8], with replacement: [UInt8], mode: ReplaceMode) -> (bytes: [UInt8], count: Int, error: String?) {
        guard !find.isEmpty else { return (bytes, 0, "nothing to search for") }
        var rep = replacement
        if mode == .sameLength {
            if rep.count > find.count { return (bytes, 0, "the replacement is \(rep.count - find.count) bytes longer than the original; in a program or ROM it must not be longer") }
            rep += [UInt8](repeating: 0, count: find.count - rep.count)
        }
        let hits = search(bytes, find, limit: 100_000)
        guard !hits.isEmpty else { return (bytes, 0, nil) }
        if mode == .sameLength {
            var out = bytes
            for h in hits { out.replaceSubrange(h..<(h + find.count), with: rep) }
            return (out, hits.count, nil)
        }
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var last = 0
        for h in hits where h >= last {
            out.append(contentsOf: bytes[last..<h])
            out.append(contentsOf: rep)
            last = h + find.count
        }
        out.append(contentsOf: bytes[last...])
        return (out, hits.count, nil)
    }

    /// Text in a program or ROM as bytes: ASCII/UTF-8, or UTF-16LE when asked (Windows resources).
    static func encode(_ text: String, utf16: Bool) -> [UInt8] {
        utf16 ? Array(text.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } : Array(text.utf8)
    }

    /// Byte-for-byte comparison summary of two files.
    static func compare(_ a: [UInt8], _ b: [UInt8], maxRanges: Int = 20) -> String {
        var ranges: [(Int, Int)] = []
        var i = 0
        let n = Swift.min(a.count, b.count)
        var differing = 0
        while i < n {
            if a[i] != b[i] {
                let start = i
                while i < n && a[i] != b[i] { i += 1 }
                differing += i - start
                if ranges.count < maxRanges { ranges.append((start, i - start)) }
            } else {
                i += 1
            }
        }
        var lines = ["\(differing) differing byte(s) in \(ranges.count)\(ranges.count == maxRanges ? "+" : "") range(s)"]
        if a.count != b.count { lines.append("sizes differ: \(a.count) vs \(b.count) bytes") }
        for (s, l) in ranges { lines.append(String(format: "  0x%08x  %d byte(s)", s, l)) }
        return lines.joined(separator: "\n")
    }
}

/// One textual report about any file, for the terminal's `inspect` and the coding agent's context.
enum BinaryInspector {
    static func report(_ bytes: [UInt8], filename: String) -> String {
        let kind = FileKind.detect(bytes, filename: filename)
        var lines = ["\(filename): \(kind.name) · \(ByteCountFormatter.string(fromByteCount: Int64(bytes.count), countStyle: .file)) · sha256 \(SHA256.hex(bytes).prefix(16))…"]
        switch kind.id {
        case "pe":
            if let pe = PEInfo.parse(bytes) { lines.append(pe.report()) }
            lines.append("Windows programs can't run on iPad/iPhone (iOS allows no foreign executables). I can inspect, patch text and data, extract embedded archives, or rebuild the program's features as a new app.")
        case "elf":
            if let elf = ELFInfo.parse(bytes) { lines.append(elf.report()) }
        case "macho":
            if let m = MachOInfo.parse(bytes) { lines.append(m.report()) }
        case "gba":
            if let g = GBAHeader.parse(bytes) { lines.append(g.report()) }
        case "gb", "gbc":
            if let g = GBHeader.parse(bytes) { lines.append(g.report()) }
        case "nes":
            if let n = NESHeader.parse(bytes) { lines.append(n.report()) }
        case "zip", "jar", "apk", "ipa", "docx", "xlsx", "pptx", "epub", "sb3", "usdz":
            if let z = try? ZipArchive(bytes: bytes) {
                let files = z.files
                let total = files.reduce(0) { $0 + $1.size }
                lines.append("\(files.count) file(s), \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)) unpacked:")
                for e in files.prefix(40) { lines.append("  \(e.path)  \(e.size) B  \(e.methodName)\(e.isEncrypted ? "  (encrypted)" : "")") }
                if files.count > 40 { lines.append("  … \(files.count - 40) more") }
            }
        case "tar":
            if let entries = try? TarArchive.read(bytes) { lines.append("\(entries.count) entries: " + entries.prefix(30).map(\.path).joined(separator: ", ")) }
        case "gzip", "tgz":
            if let inner = try? Gzip.decompress(bytes) {
                lines.append("Unpacks to \(inner.data.count) bytes\(inner.name.map { " (\($0))" } ?? "")")
                if TarArchive.isTar(inner.data), let entries = try? TarArchive.read(inner.data) {
                    lines.append("tar with \(entries.count) entries: " + entries.prefix(20).map(\.path).joined(separator: ", "))
                }
            }
        case "ips", "bps", "ups":
            lines.append("ROM patch. Apply with `\(kind.id) apply <patch> <rom>`.")
        case "wasm":
            lines.append("WebAssembly module: runs in the web runtime (`preview` an HTML page that loads it).")
        default:
            if kind.isText, let text = TextSniffer.decode(bytes) {
                let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
                lines.append("\(lineCount) line(s), \(text.count) characters")
                lines.append(String(text.prefix(400)))
            } else {
                lines.append(BinaryTools.hexdump(bytes, offset: 0, length: 128))
            }
        }
        return lines.joined(separator: "\n")
    }
}

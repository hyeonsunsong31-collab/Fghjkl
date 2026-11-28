import Foundation

/// One file or folder inside a ZIP archive.
struct ZipEntry: Equatable {
    var path: String
    var method: UInt16
    var crc: UInt32
    var compressedSize: Int
    var size: Int
    var localHeaderOffset: Int
    var modified: Date
    var isDirectory: Bool
    var isEncrypted: Bool
    var unixMode: UInt32?

    var methodName: String {
        switch method {
        case 0: return "stored"
        case 8: return "deflate"
        case 9: return "deflate64"
        case 12: return "bzip2"
        case 14: return "lzma"
        case 93: return "zstd"
        case 95: return "xz"
        case 99: return "aes"
        default: return "method \(method)"
        }
    }
}

/// ZIP reader/writer (also .jar, .apk, .ipa, .docx, .xlsx, .epub, .sb3 …), with ZIP64 and
/// self-extracting archives (a ZIP appended to an .exe) on the reading side.
struct ZipArchive {
    let bytes: [UInt8]
    let entries: [ZipEntry]
    let comment: String

    init(data: Data) throws { try self.init(bytes: [UInt8](data)) }

    init(bytes: [UInt8]) throws {
        self.bytes = bytes
        let r = ByteReader(bytes)
        guard bytes.count >= 22 else { throw ArchiveError.corrupt("too small to be a ZIP") }
        // End of central directory: last signature within the final 64 KiB + 22 bytes.
        var eocd = -1
        var i = bytes.count - 22
        let stop = Swift.max(0, bytes.count - 65_557)
        while i >= stop {
            if bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 5 && bytes[i + 3] == 6 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ArchiveError.corrupt("no ZIP directory found") }
        var total = Int(r.u16(eocd + 10) ?? 0)
        var cdSize = Int(r.u32(eocd + 12) ?? 0)
        var cdOffset = Int(r.u32(eocd + 16) ?? 0)
        let commentLength = Int(r.u16(eocd + 20) ?? 0)
        comment = String(decoding: r.slice(eocd + 22, Swift.min(commentLength, bytes.count - eocd - 22)) ?? [], as: UTF8.self)
        var directoryEnd = eocd
        if total == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF,
           r.u32(eocd - 20) == 0x0706_4B50, let z64 = r.u64(eocd - 12).map({ Int($0) }), r.u32(z64) == 0x0606_4B50 {
            total = Int(r.u64(z64 + 32) ?? 0)
            cdSize = Int(r.u64(z64 + 40) ?? 0)
            cdOffset = Int(r.u64(z64 + 48) ?? 0)
            directoryEnd = z64
        }
        // Self-extracting archives: offsets are relative to where the ZIP part starts.
        let actualStart = directoryEnd - cdSize
        let shift = actualStart - cdOffset
        var position = cdOffset + Swift.max(0, shift)
        var list: [ZipEntry] = []
        list.reserveCapacity(total)
        for _ in 0..<total {
            guard r.u32(position) == 0x0201_4B50 else { throw ArchiveError.corrupt("bad central directory entry") }
            let made = r.u16(position + 4) ?? 0
            let flags = r.u16(position + 8) ?? 0
            let method = r.u16(position + 10) ?? 0
            let time = r.u16(position + 12) ?? 0
            let date = r.u16(position + 14) ?? 0
            let crc = r.u32(position + 16) ?? 0
            var compressed = Int(r.u32(position + 20) ?? 0)
            var size = Int(r.u32(position + 24) ?? 0)
            let nameLength = Int(r.u16(position + 28) ?? 0)
            let extraLength = Int(r.u16(position + 30) ?? 0)
            let commentLen = Int(r.u16(position + 32) ?? 0)
            let external = r.u32(position + 38) ?? 0
            var local = Int(r.u32(position + 42) ?? 0)
            guard let nameBytes = r.slice(position + 46, nameLength) else { throw ArchiveError.truncated }
            // ZIP64 extended information.
            var e = position + 46 + nameLength
            let extraEnd = e + extraLength
            while e + 4 <= extraEnd {
                let id = r.u16(e) ?? 0
                let len = Int(r.u16(e + 2) ?? 0)
                if id == 1 {
                    var f = e + 4
                    if size == 0xFFFF_FFFF { size = Int(r.u64(f) ?? 0); f += 8 }
                    if compressed == 0xFFFF_FFFF { compressed = Int(r.u64(f) ?? 0); f += 8 }
                    if local == 0xFFFF_FFFF { local = Int(r.u64(f) ?? 0) }
                }
                e += 4 + len
            }
            let name = Self.decodeName(Array(nameBytes), utf8: flags & 0x800 != 0)
            let unix: UInt32? = (made >> 8) == 3 ? (external >> 16) : nil
            let isDir = name.hasSuffix("/") || (unix.map { $0 & 0o170000 == 0o040000 } ?? false) || (external & 0x10 != 0 && size == 0)
            list.append(ZipEntry(path: name, method: method, crc: crc, compressedSize: compressed, size: size,
                                 localHeaderOffset: local + Swift.max(0, shift), modified: Self.dosDate(date, time),
                                 isDirectory: isDir, isEncrypted: flags & 1 != 0, unixMode: unix))
            position += 46 + nameLength + extraLength + commentLen
        }
        entries = list
    }

    static func isZip(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && (bytes[2] == 3 || bytes[2] == 5) && (bytes[3] == 4 || bytes[3] == 6)
    }

    func entry(named path: String) -> ZipEntry? {
        entries.first { $0.path == path } ?? entries.first { $0.path.lowercased() == path.lowercased() }
    }

    var files: [ZipEntry] { entries.filter { !$0.isDirectory } }

    /// The uncompressed contents of one entry (CRC-checked).
    func data(for entry: ZipEntry) throws -> [UInt8] {
        let r = ByteReader(bytes)
        let h = entry.localHeaderOffset
        guard r.u32(h) == 0x0403_4B50 else { throw ArchiveError.corrupt("bad local header for \(entry.path)") }
        guard !entry.isEncrypted else { throw ArchiveError.unsupported("\(entry.path) is password-protected") }
        let start = h + 30 + Int(r.u16(h + 26) ?? 0) + Int(r.u16(h + 28) ?? 0)
        guard let raw = r.slice(start, entry.compressedSize) else { throw ArchiveError.truncated }
        let out: [UInt8]
        switch entry.method {
        case 0: out = Array(raw)
        case 8: out = try Inflate.inflate(Array(raw), expectedSize: entry.size)
        default: throw ArchiveError.unsupported("\(entry.path) uses \(entry.methodName) compression")
        }
        guard CRC32.checksum(out) == entry.crc else { throw ArchiveError.checksumMismatch(entry.path) }
        return out
    }

    /// A path that is safe to extract under a folder (no absolute paths, no "..").
    static func safePath(_ path: String) -> String? {
        let unified: String = path.replacingOccurrences(of: "\\", with: "/")
        let pieces: [String] = unified.split(separator: "/").map { String($0) }
        let parts: [String] = pieces.filter { (p: String) -> Bool in !p.isEmpty && p != "." }
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        if parts.first == "__MACOSX" { return nil }
        return parts.joined(separator: "/")
    }

    private static func decodeName(_ bytes: [UInt8], utf8: Bool) -> String {
        if utf8 || bytes.allSatisfy({ $0 < 0x80 }) { return String(decoding: bytes, as: UTF8.self) }
        if let s = String(bytes: bytes, encoding: .utf8) { return s }
        #if canImport(Darwin)
        // Korean Windows tools write names in CP949 without the UTF-8 flag.
        let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
        if let s = String(bytes: bytes, encoding: cp949) { return s }
        #endif
        return String(bytes: bytes, encoding: .isoLatin1) ?? String(decoding: bytes, as: UTF8.self)
    }

    static func dosDate(_ date: UInt16, _ time: UInt16) -> Date {
        var c = DateComponents()
        c.year = 1980 + Int(date >> 9)
        c.month = Swift.max(1, Int((date >> 5) & 15))
        c.day = Swift.max(1, Int(date & 31))
        c.hour = Int(time >> 11)
        c.minute = Int((time >> 5) & 63)
        c.second = Int(time & 31) * 2
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 315_532_800)
    }

    static func dosStamp(_ d: Date) -> (date: UInt16, time: UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        let year = Swift.max(0, (c.year ?? 1980) - 1980)
        let datePart: Int = (year << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1)
        let timePart: Int = ((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2)
        return (UInt16(truncatingIfNeeded: datePart), UInt16(truncatingIfNeeded: timePart))
    }

    // MARK: Writing

    struct Item {
        var path: String
        var data: [UInt8]
        var modified = Date()
        var isDirectory = false
        var executable = false

        init(path: String, data: [UInt8], modified: Date = Date(), isDirectory: Bool = false, executable: Bool = false) {
            self.path = path
            self.data = data
            self.modified = modified
            self.isDirectory = isDirectory
            self.executable = executable
        }
    }

    /// Already-compressed formats are stored as they are.
    static let storedExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "mp3", "m4a", "aac", "mp4", "mov", "m4v",
                                                "zip", "gz", "tgz", "7z", "rar", "xz", "bz2", "jar", "apk", "ipa", "docx", "xlsx",
                                                "pptx", "epub", "woff2", "usdz", "ogg", "opus", "flac", "webm"]

    static func build(_ items: [Item], compress: Bool = true) -> [UInt8] {
        var w = ByteWriter()
        var central = ByteWriter()
        var count = 0
        for item in items {
            var path = item.path.replacingOccurrences(of: "\\", with: "/")
            while path.hasPrefix("/") { path.removeFirst() }
            if item.isDirectory && !path.hasSuffix("/") { path += "/" }
            guard !path.isEmpty else { continue }
            let nameBytes = Array(path.utf8)
            let ext = (path as NSString).pathExtension.lowercased()
            var method: UInt16 = 0
            var payload = item.data
            if compress && !item.isDirectory && item.data.count > 64 && !storedExtensions.contains(ext) {
                let packed = Deflate.compress(item.data)
                if packed.count < item.data.count {
                    payload = packed
                    method = 8
                }
            }
            let crc = CRC32.checksum(item.data)
            let stamp = dosStamp(item.modified)
            let flags: UInt16 = nameBytes.allSatisfy { $0 < 0x80 } ? 0 : 0x800
            let offset = w.bytes.count
            w.u32(0x0403_4B50); w.u16(20); w.u16(flags); w.u16(method); w.u16(stamp.time); w.u16(stamp.date)
            w.u32(crc); w.u32(UInt32(payload.count)); w.u32(UInt32(item.data.count))
            w.u16(UInt16(nameBytes.count)); w.u16(0)
            w.append(nameBytes)
            w.append(payload)
            let mode: UInt32 = item.isDirectory ? 0o040755 : (item.executable ? 0o100755 : 0o100644)
            central.u32(0x0201_4B50); central.u16(0x031E); central.u16(20); central.u16(flags); central.u16(method)
            central.u16(stamp.time); central.u16(stamp.date); central.u32(crc)
            central.u32(UInt32(payload.count)); central.u32(UInt32(item.data.count))
            central.u16(UInt16(nameBytes.count)); central.u16(0); central.u16(0); central.u16(0); central.u16(0)
            central.u32((mode << 16) | (item.isDirectory ? 0x10 : 0))
            central.u32(UInt32(offset))
            central.append(nameBytes)
            count += 1
        }
        let cdOffset = w.bytes.count
        w.append(central.bytes)
        w.u32(0x0605_4B50); w.u16(0); w.u16(0); w.u16(UInt16(count)); w.u16(UInt16(count))
        w.u32(UInt32(central.bytes.count)); w.u32(UInt32(cdOffset)); w.u16(0)
        return w.bytes
    }
}

/// POSIX ustar archives (.tar, and .tar.gz / .tgz through `Gzip`).
enum TarArchive {
    struct Entry {
        var path: String
        var data: [UInt8]
        var isDirectory = false
        var mode = 0o644
        var modified = Date()
    }

    static func isTar(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 512 && ByteReader(bytes).hasPrefix(Array("ustar".utf8), at: 257)
    }

    static func read(_ bytes: [UInt8]) throws -> [Entry] {
        var out: [Entry] = []
        var p = 0
        var longName: String?
        var paxPath: String?
        let r = ByteReader(bytes)
        while p + 512 <= bytes.count {
            let header = bytes[p..<(p + 512)]
            if header.allSatisfy({ $0 == 0 }) { break }
            let name = r.ascii(p, 100) ?? ""
            let size = octal(r.ascii(p + 124, 12) ?? "0")
            let mtime = octal(r.ascii(p + 136, 12) ?? "0")
            let mode = octal(r.ascii(p + 100, 8) ?? "644")
            let type = bytes[p + 156]
            let prefix = r.ascii(p + 345, 155) ?? ""
            let dataStart = p + 512
            guard dataStart + size <= bytes.count else { throw ArchiveError.truncated }
            let payload = Array(bytes[dataStart..<(dataStart + size)])
            p = dataStart + (size + 511) / 512 * 512
            switch type {
            case UInt8(ascii: "L"):
                longName = String(decoding: payload.prefix { $0 != 0 }, as: UTF8.self)
                continue
            case UInt8(ascii: "x"):
                let text = String(decoding: payload, as: UTF8.self)
                for line in text.split(separator: "\n") {
                    if let range = line.range(of: " path=") { paxPath = String(line[range.upperBound...]) }
                }
                continue
            case UInt8(ascii: "g"):
                continue
            default:
                break
            }
            var path = longName ?? paxPath ?? (prefix.isEmpty ? name : prefix + "/" + name)
            longName = nil
            paxPath = nil
            let isDir = type == UInt8(ascii: "5") || path.hasSuffix("/")
            guard type == 0 || type == UInt8(ascii: "0") || type == UInt8(ascii: "7") || isDir else { continue }
            if isDir && !path.hasSuffix("/") { path += "/" }
            out.append(Entry(path: path, data: isDir ? [] : payload, isDirectory: isDir, mode: mode,
                             modified: Date(timeIntervalSince1970: TimeInterval(mtime))))
        }
        return out
    }

    static func build(_ entries: [Entry]) -> [UInt8] {
        var out: [UInt8] = []
        for e in entries {
            var path = e.path
            if e.isDirectory && !path.hasSuffix("/") { path += "/" }
            var nameBytes = Array(path.utf8)
            if nameBytes.count > 99 {
                // GNU long name record.
                out.append(contentsOf: header(name: "././@LongLink", size: nameBytes.count + 1, mode: 0, mtime: 0, type: UInt8(ascii: "L")))
                out.append(contentsOf: nameBytes + [0])
                out.append(contentsOf: [UInt8](repeating: 0, count: (512 - (nameBytes.count + 1) % 512) % 512))
                nameBytes = Array(nameBytes.prefix(99))
            }
            let size = e.isDirectory ? 0 : e.data.count
            out.append(contentsOf: header(name: String(decoding: nameBytes, as: UTF8.self), size: size, mode: e.mode,
                                          mtime: Int(e.modified.timeIntervalSince1970), type: e.isDirectory ? UInt8(ascii: "5") : UInt8(ascii: "0")))
            if size > 0 {
                out.append(contentsOf: e.data)
                out.append(contentsOf: [UInt8](repeating: 0, count: (512 - size % 512) % 512))
            }
        }
        out.append(contentsOf: [UInt8](repeating: 0, count: 1024))
        return out
    }

    private static func header(name: String, size: Int, mode: Int, mtime: Int, type: UInt8) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 512)
        func put(_ s: String, _ offset: Int, _ width: Int) {
            for (i, b) in Array(s.utf8).prefix(width).enumerated() { h[offset + i] = b }
        }
        func putOctal(_ v: Int, _ offset: Int, _ width: Int) {
            let digits = String(v, radix: 8)
            let padded = String(repeating: "0", count: Swift.max(0, width - 1 - digits.count)) + digits
            put(padded, offset, width - 1)
        }
        put(name, 0, 100)
        putOctal(mode, 100, 8)
        putOctal(0, 108, 8)
        putOctal(0, 116, 8)
        putOctal(size, 124, 12)
        putOctal(mtime, 136, 12)
        h[156] = type
        put("ustar", 257, 6)
        put("00", 263, 2)
        put("jarvis", 265, 32)
        put("jarvis", 297, 32)
        for i in 148..<156 { h[i] = 0x20 }
        let sum = h.reduce(0) { $0 + Int($1) }
        putOctal(sum, 148, 7)
        h[155] = 0x20
        return h
    }

    private static func octal(_ s: String) -> Int {
        Int(s.trimmingCharacters(in: CharacterSet(charactersIn: " \0")), radix: 8) ?? 0
    }
}

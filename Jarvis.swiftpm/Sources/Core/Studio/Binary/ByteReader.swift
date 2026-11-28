import Foundation

/// Bounds-checked little/big-endian reads from a byte array (returns nil past the end).
struct ByteReader {
    let bytes: [UInt8]

    init(_ bytes: [UInt8]) { self.bytes = bytes }
    init(_ data: Data) { bytes = [UInt8](data) }

    var count: Int { bytes.count }

    func u8(_ o: Int) -> UInt8? { o >= 0 && o < bytes.count ? bytes[o] : nil }

    func u16(_ o: Int) -> UInt16? {
        guard o >= 0, o + 2 <= bytes.count else { return nil }
        return UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8
    }

    func u32(_ o: Int) -> UInt32? {
        guard o >= 0, o + 4 <= bytes.count else { return nil }
        let b0 = UInt32(bytes[o]), b1 = UInt32(bytes[o + 1]) << 8
        let b2 = UInt32(bytes[o + 2]) << 16, b3 = UInt32(bytes[o + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    func u64(_ o: Int) -> UInt64? {
        guard let lo = u32(o), let hi = u32(o + 4) else { return nil }
        return UInt64(lo) | UInt64(hi) << 32
    }

    func u16be(_ o: Int) -> UInt16? {
        guard o >= 0, o + 2 <= bytes.count else { return nil }
        return UInt16(bytes[o]) << 8 | UInt16(bytes[o + 1])
    }

    func u32be(_ o: Int) -> UInt32? {
        guard o >= 0, o + 4 <= bytes.count else { return nil }
        let b0 = UInt32(bytes[o]) << 24, b1 = UInt32(bytes[o + 1]) << 16
        let b2 = UInt32(bytes[o + 2]) << 8, b3 = UInt32(bytes[o + 3])
        return b0 | b1 | b2 | b3
    }

    func u64be(_ o: Int) -> UInt64? {
        guard let hi = u32be(o), let lo = u32be(o + 4) else { return nil }
        return UInt64(hi) << 32 | UInt64(lo)
    }

    func slice(_ o: Int, _ n: Int) -> ArraySlice<UInt8>? {
        guard o >= 0, n >= 0, o + n <= bytes.count else { return nil }
        return bytes[o..<(o + n)]
    }

    /// NUL-terminated (or fixed-width) ASCII/UTF-8 text.
    func cString(_ o: Int, max: Int = 4096) -> String? {
        guard o >= 0, o < bytes.count else { return nil }
        var end = o
        let limit = Swift.min(bytes.count, o + max)
        while end < limit && bytes[end] != 0 { end += 1 }
        return String(decoding: bytes[o..<end], as: UTF8.self)
    }

    func ascii(_ o: Int, _ n: Int) -> String? {
        guard let s = slice(o, n) else { return nil }
        let trimmed = s.prefix { $0 != 0 }
        return String(decoding: trimmed, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    func hasPrefix(_ magic: [UInt8], at o: Int = 0) -> Bool {
        guard o >= 0, o + magic.count <= bytes.count else { return false }
        for (i, b) in magic.enumerated() where bytes[o + i] != b { return false }
        return true
    }

    /// First offset of `needle` at or after `from`.
    func find(_ needle: [UInt8], from: Int = 0) -> Int? {
        guard !needle.isEmpty, needle.count <= bytes.count else { return nil }
        let first = needle[0]
        var i = Swift.max(0, from)
        let last = bytes.count - needle.count
        while i <= last {
            if bytes[i] == first {
                var j = 1
                while j < needle.count && bytes[i + j] == needle[j] { j += 1 }
                if j == needle.count { return i }
            }
            i += 1
        }
        return nil
    }
}

/// Appends little-endian integers to a byte array.
struct ByteWriter {
    var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func u16(_ v: UInt16) { bytes.append(UInt8(v & 0xFF)); bytes.append(UInt8(v >> 8)) }
    mutating func u32(_ v: UInt32) { for s in [0, 8, 16, 24] { bytes.append(UInt8(truncatingIfNeeded: v >> UInt32(s))) } }
    mutating func u64(_ v: UInt64) { for s in stride(from: 0, to: 64, by: 8) { bytes.append(UInt8(truncatingIfNeeded: v >> UInt64(s))) } }
    mutating func append(_ b: [UInt8]) { bytes.append(contentsOf: b) }
    mutating func append(_ b: ArraySlice<UInt8>) { bytes.append(contentsOf: b) }
    mutating func append(_ s: String) { bytes.append(contentsOf: Array(s.utf8)) }
}

extension Array where Element == UInt8 {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    init?(hex: String) {
        let clean = hex.filter { !$0.isWhitespace && $0 != ":" && $0 != "-" }.lowercased()
        let s = clean.hasPrefix("0x") ? String(clean.dropFirst(2)) : clean
        guard s.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(s.count / 2)
        var it = s.makeIterator()
        while let a = it.next(), let b = it.next() {
            guard let v = UInt8(String([a, b]), radix: 16) else { return nil }
            out.append(v)
        }
        self = out
    }
}

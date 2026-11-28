import Foundation
#if canImport(Compression)
import Compression
#endif

enum ArchiveError: Error, CustomStringConvertible {
    case truncated
    case corrupt(String)
    case unsupported(String)
    case checksumMismatch(String)

    var description: String {
        switch self {
        case .truncated: return "the data ends too early"
        case .corrupt(let s): return "corrupt data (\(s))"
        case .unsupported(let s): return "unsupported: \(s)"
        case .checksumMismatch(let s): return "checksum mismatch (\(s))"
        }
    }
}

// MARK: - Inflate (RFC 1951)

/// DEFLATE decoder in plain Swift (raw deflate, as inside ZIP and gzip).
/// On Apple platforms the system decoder is tried first when the output size is known.
enum Inflate {
    static func inflate(_ input: [UInt8], expectedSize: Int? = nil) throws -> [UInt8] {
        #if canImport(Compression)
        if let size = expectedSize, size > 0, let fast = systemInflate(input, size: size) { return fast }
        #endif
        return try inflatePortable(input, expectedSize: expectedSize).output
    }

    #if canImport(Compression)
    private static func systemInflate(_ input: [UInt8], size: Int) -> [UInt8]? {
        guard !input.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: size)
        let written: Int = out.withUnsafeMutableBufferPointer { (dst: inout UnsafeMutableBufferPointer<UInt8>) -> Int in
            input.withUnsafeBufferPointer { (src: UnsafeBufferPointer<UInt8>) -> Int in
                compression_decode_buffer(dst.baseAddress!, size, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? out : nil
    }
    #endif

    /// Decode one deflate stream; returns the output and how many input bytes it used.
    static func inflatePortable(_ input: [UInt8], start: Int = 0, expectedSize: Int? = nil) throws -> (output: [UInt8], consumed: Int) {
        var state = InflateState(input: input, position: start)
        if let n = expectedSize { state.out.reserveCapacity(n) }
        try state.run()
        return (state.out, state.position - start)
    }
}

private struct HuffmanTable {
    /// Entry = symbol << 4 | length (length 0 = invalid code).
    var table: [UInt32]
    var maxLength: Int

    init(lengths: [UInt8]) throws {
        var count = [Int](repeating: 0, count: 16)
        for l in lengths { count[Int(l)] += 1 }
        count[0] = 0
        var maxLen = 0
        for l in 1..<16 where count[l] > 0 { maxLen = l }
        // Over-subscribed check.
        var left = 1
        for l in 1..<16 {
            left <<= 1
            left -= count[l]
            if left < 0 { throw ArchiveError.corrupt("over-subscribed Huffman code") }
        }
        maxLength = Swift.max(maxLen, 1)
        var next = [Int](repeating: 0, count: 16)
        var code = 0
        for l in 1..<16 {
            code = (code + count[l - 1]) << 1
            next[l] = code
        }
        let size = 1 << maxLength
        var t = [UInt32](repeating: 0, count: size)
        for (symbol, lenByte) in lengths.enumerated() where lenByte > 0 {
            let len = Int(lenByte)
            let c = next[len]
            next[len] += 1
            // Codes are stored MSB-first in the stream but read LSB-first: reverse them.
            var reversed = 0
            var v = c
            for _ in 0..<len { reversed = (reversed << 1) | (v & 1); v >>= 1 }
            let entry = UInt32(symbol) << 4 | UInt32(len)
            var i = reversed
            while i < size {
                t[i] = entry
                i += 1 << len
            }
        }
        table = t
    }
}

private struct InflateState {
    let input: [UInt8]
    var position: Int
    var bitBuffer: UInt64 = 0
    var bitCount = 0
    var out: [UInt8] = []

    static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                                  4097, 6145, 8193, 12289, 16385, 24577]
    static let distExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    static let codeLengthOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    init(input: [UInt8], position: Int) {
        self.input = input
        self.position = position
    }

    @inline(__always) mutating func fill(_ n: Int) {
        while bitCount < n && position < input.count {
            bitBuffer |= UInt64(input[position]) << UInt64(bitCount)
            position += 1
            bitCount += 8
        }
    }

    @inline(__always) mutating func bits(_ n: Int) throws -> Int {
        if n == 0 { return 0 }
        fill(n)
        guard bitCount >= n else { throw ArchiveError.truncated }
        let v = Int(bitBuffer & ((1 << UInt64(n)) - 1))
        bitBuffer >>= UInt64(n)
        bitCount -= n
        return v
    }

    @inline(__always) mutating func decode(_ h: HuffmanTable) throws -> Int {
        fill(h.maxLength)
        let entry = h.table[Int(bitBuffer & ((1 << UInt64(h.maxLength)) - 1))]
        let len = Int(entry & 15)
        guard len > 0 else { throw ArchiveError.corrupt("invalid Huffman code") }
        guard len <= bitCount else { throw ArchiveError.truncated }
        bitBuffer >>= UInt64(len)
        bitCount -= len
        return Int(entry >> 4)
    }

    mutating func run() throws {
        var last = false
        while !last {
            last = try bits(1) == 1
            switch try bits(2) {
            case 0: try stored()
            case 1: try codes(Self.fixedLiteral, Self.fixedDistance)
            case 2:
                let (lit, dist) = try dynamicTables()
                try codes(lit, dist)
            default: throw ArchiveError.corrupt("invalid block type")
            }
        }
        // Give back whole unused bytes still sitting in the bit buffer.
        position -= bitCount / 8
        bitCount = 0
        bitBuffer = 0
    }

    mutating func stored() throws {
        // Skip to the byte boundary.
        let drop = bitCount % 8
        bitBuffer >>= UInt64(drop)
        bitCount -= drop
        let len = try bits(16)
        let nlen = try bits(16)
        guard len == (~nlen & 0xFFFF) else { throw ArchiveError.corrupt("stored block length") }
        // Bytes may already be buffered.
        var remaining = len
        while remaining > 0 && bitCount >= 8 {
            out.append(UInt8(truncatingIfNeeded: try bits(8)))
            remaining -= 1
        }
        guard position + remaining <= input.count else { throw ArchiveError.truncated }
        out.append(contentsOf: input[position..<(position + remaining)])
        position += remaining
    }

    static let fixedLiteral: HuffmanTable = {
        var lengths = [UInt8](repeating: 8, count: 288)
        for i in 144..<256 { lengths[i] = 9 }
        for i in 256..<280 { lengths[i] = 7 }
        return try! HuffmanTable(lengths: lengths)
    }()
    static let fixedDistance: HuffmanTable = try! HuffmanTable(lengths: [UInt8](repeating: 5, count: 30))

    mutating func dynamicTables() throws -> (HuffmanTable, HuffmanTable) {
        let nlen = try bits(5) + 257
        let ndist = try bits(5) + 1
        let ncode = try bits(4) + 4
        guard nlen <= 286, ndist <= 30 else { throw ArchiveError.corrupt("bad code counts") }
        var codeLengths = [UInt8](repeating: 0, count: 19)
        for i in 0..<ncode { codeLengths[Self.codeLengthOrder[i]] = UInt8(try bits(3)) }
        let lencode = try HuffmanTable(lengths: codeLengths)
        var lengths = [UInt8](repeating: 0, count: nlen + ndist)
        var index = 0
        while index < nlen + ndist {
            let symbol = try decode(lencode)
            if symbol < 16 {
                lengths[index] = UInt8(symbol)
                index += 1
                continue
            }
            var repeatValue: UInt8 = 0
            var times = 0
            switch symbol {
            case 16:
                guard index > 0 else { throw ArchiveError.corrupt("repeat with no previous length") }
                repeatValue = lengths[index - 1]
                times = 3 + (try bits(2))
            case 17: times = 3 + (try bits(3))
            default: times = 11 + (try bits(7))
            }
            guard index + times <= nlen + ndist else { throw ArchiveError.corrupt("too many lengths") }
            for _ in 0..<times {
                lengths[index] = repeatValue
                index += 1
            }
        }
        guard lengths[256] > 0 else { throw ArchiveError.corrupt("no end-of-block code") }
        let lit = try HuffmanTable(lengths: Array(lengths[0..<nlen]))
        let dist = try HuffmanTable(lengths: Array(lengths[nlen...]))
        return (lit, dist)
    }

    mutating func codes(_ lit: HuffmanTable, _ dist: HuffmanTable) throws {
        while true {
            let symbol = try decode(lit)
            if symbol < 256 {
                out.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let li = symbol - 257
                guard li < 29 else { throw ArchiveError.corrupt("bad length symbol") }
                let length = Self.lengthBase[li] + (try bits(Self.lengthExtra[li]))
                let di = try decode(dist)
                guard di < 30 else { throw ArchiveError.corrupt("bad distance symbol") }
                let distance = Self.distBase[di] + (try bits(Self.distExtra[di]))
                guard distance <= out.count else { throw ArchiveError.corrupt("distance too far back") }
                let from = out.count - distance
                if distance >= length {
                    out.append(contentsOf: out[from..<(from + length)])
                } else {
                    for i in 0..<length { out.append(out[from + i]) }
                }
            }
        }
    }
}

// MARK: - Deflate

/// DEFLATE encoder: the system encoder on Apple platforms, else LZ77 with fixed Huffman codes.
enum Deflate {
    static func compress(_ input: [UInt8]) -> [UInt8] {
        #if canImport(Compression)
        if let fast = systemDeflate(input) { return fast }
        #endif
        return compressPortable(input)
    }

    #if canImport(Compression)
    private static func systemDeflate(_ input: [UInt8]) -> [UInt8]? {
        guard !input.isEmpty else { return nil }
        let capacity = input.count + input.count / 8 + 1024
        var out = [UInt8](repeating: 0, count: capacity)
        let written: Int = out.withUnsafeMutableBufferPointer { (dst: inout UnsafeMutableBufferPointer<UInt8>) -> Int in
            input.withUnsafeBufferPointer { (src: UnsafeBufferPointer<UInt8>) -> Int in
                compression_encode_buffer(dst.baseAddress!, capacity, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return Array(out[0..<written])
    }
    #endif

    static func compressPortable(_ input: [UInt8]) -> [UInt8] {
        var w = BitWriter()
        w.write(1, 1)   // final block
        w.write(1, 2)   // fixed Huffman
        let n = input.count
        let windowMask = 0x7FFF
        let hashSize = 1 << 15
        var head = [Int32](repeating: -1, count: hashSize)
        var prev = [Int32](repeating: -1, count: windowMask + 1)
        @inline(__always) func hash(_ i: Int) -> Int {
            let h0: Int = Int(input[i]) << 10
            let h1: Int = Int(input[i + 1]) << 5
            return (h0 ^ h1 ^ Int(input[i + 2])) & (hashSize - 1)
        }
        var i = 0
        while i < n {
            var bestLength = 0
            var bestDistance = 0
            if i + 2 < n {
                let h = hash(i)
                var candidate = Int(head[h])
                var chain = 0
                let maxLength = Swift.min(258, n - i)
                while candidate >= 0 && i - candidate <= 32768 && chain < 48 {
                    if input[candidate + bestLength] == input[i + bestLength] || bestLength == 0 {
                        var l = 0
                        while l < maxLength && input[candidate + l] == input[i + l] { l += 1 }
                        if l > bestLength {
                            bestLength = l
                            bestDistance = i - candidate
                            if l == maxLength { break }
                        }
                    }
                    candidate = Int(prev[candidate & windowMask])
                    chain += 1
                }
                prev[i & windowMask] = head[h]
                head[h] = Int32(i)
            }
            if bestLength >= 3 {
                w.writeLength(bestLength)
                w.writeDistance(bestDistance)
                // Index the skipped positions too.
                var k = i + 1
                let end = i + bestLength
                while k < end {
                    if k + 2 < n {
                        let h = hash(k)
                        prev[k & windowMask] = head[h]
                        head[h] = Int32(k)
                    }
                    k += 1
                }
                i = end
            } else {
                w.writeLiteral(Int(input[i]))
                i += 1
            }
        }
        w.writeLiteral(256)
        return w.finish()
    }
}

private struct BitWriter {
    var bytes: [UInt8] = []
    var buffer: UInt64 = 0
    var count = 0

    mutating func write(_ value: Int, _ n: Int) {
        buffer |= UInt64(value) << UInt64(count)
        count += n
        while count >= 8 {
            bytes.append(UInt8(truncatingIfNeeded: buffer))
            buffer >>= 8
            count -= 8
        }
    }

    /// Huffman codes go MSB-first.
    mutating func writeCode(_ code: Int, _ length: Int) {
        var reversed = 0
        var v = code
        for _ in 0..<length { reversed = (reversed << 1) | (v & 1); v >>= 1 }
        write(reversed, length)
    }

    mutating func writeLiteral(_ symbol: Int) {
        switch symbol {
        case 0..<144: writeCode(0x30 + symbol, 8)
        case 144..<256: writeCode(0x190 + symbol - 144, 9)
        case 256..<280: writeCode(symbol - 256, 7)
        default: writeCode(0xC0 + symbol - 280, 8)
        }
    }

    mutating func writeLength(_ length: Int) {
        let base = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
        let extra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
        var index = 28
        if length < 258 {
            index = 0
            while index + 1 < 28 && base[index + 1] <= length { index += 1 }
        }
        writeLiteral(257 + index)
        if extra[index] > 0 { write(length - base[index], extra[index]) }
    }

    mutating func writeDistance(_ distance: Int) {
        let base = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                    4097, 6145, 8193, 12289, 16385, 24577]
        let extra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
        var index = 0
        while index + 1 < 30 && base[index + 1] <= distance { index += 1 }
        writeCode(index, 5)
        if extra[index] > 0 { write(distance - base[index], extra[index]) }
    }

    mutating func finish() -> [UInt8] {
        if count > 0 { bytes.append(UInt8(truncatingIfNeeded: buffer)) }
        buffer = 0
        count = 0
        return bytes
    }
}

// MARK: - gzip (RFC 1952)

enum Gzip {
    static func isGzip(_ bytes: [UInt8]) -> Bool { bytes.count >= 3 && bytes[0] == 0x1F && bytes[1] == 0x8B && bytes[2] == 8 }

    /// Decompress all members of a gzip file; returns the data and the stored file name, if any.
    static func decompress(_ bytes: [UInt8]) throws -> (data: [UInt8], name: String?) {
        var out: [UInt8] = []
        var name: String?
        var p = 0
        while p + 18 <= bytes.count && bytes[p] == 0x1F && bytes[p + 1] == 0x8B {
            guard bytes[p + 2] == 8 else { throw ArchiveError.unsupported("gzip compression method \(bytes[p + 2])") }
            let flags = bytes[p + 3]
            p += 10
            if flags & 4 != 0 {
                guard p + 2 <= bytes.count else { throw ArchiveError.truncated }
                let xlen = Int(bytes[p]) | Int(bytes[p + 1]) << 8
                p += 2 + xlen
            }
            if flags & 8 != 0 {
                let start = p
                while p < bytes.count && bytes[p] != 0 { p += 1 }
                if name == nil { name = String(decoding: bytes[start..<p], as: UTF8.self) }
                p += 1
            }
            if flags & 16 != 0 {
                while p < bytes.count && bytes[p] != 0 { p += 1 }
                p += 1
            }
            if flags & 2 != 0 { p += 2 }
            guard p <= bytes.count else { throw ArchiveError.truncated }
            let (member, used) = try Inflate.inflatePortable(bytes, start: p)
            p += used
            guard p + 8 <= bytes.count else { throw ArchiveError.truncated }
            let crc = UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8 | UInt32(bytes[p + 2]) << 16 | UInt32(bytes[p + 3]) << 24
            guard crc == CRC32.checksum(member) else { throw ArchiveError.checksumMismatch("gzip CRC") }
            p += 8
            out.append(contentsOf: member)
        }
        guard !out.isEmpty || bytes.count >= 18 else { throw ArchiveError.corrupt("not a gzip file") }
        return (out, name)
    }

    static func compress(_ data: [UInt8], name: String? = nil) -> [UInt8] {
        var out: [UInt8] = [0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 255]
        if let name {
            out[3] = 8
            out.append(contentsOf: Array(name.utf8))
            out.append(0)
        }
        out.append(contentsOf: Deflate.compress(data))
        let crc = CRC32.checksum(data)
        let size = UInt32(truncatingIfNeeded: data.count)
        for v in [crc, size] { for s in [0, 8, 16, 24] { out.append(UInt8(truncatingIfNeeded: v >> UInt32(s))) } }
        return out
    }
}

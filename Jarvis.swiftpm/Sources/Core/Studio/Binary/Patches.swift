import Foundation

enum PatchError: Error, CustomStringConvertible {
    case badFormat(String)
    case wrongSource(String)

    var description: String {
        switch self {
        case .badFormat(let s): return "not a valid patch (\(s))"
        case .wrongSource(let s): return "this patch is for a different file (\(s))"
        }
    }
}

/// IPS patches (the classic ROM-hack format; offsets up to 16 MiB).
enum IPSPatch {
    static func apply(_ patch: [UInt8], to source: [UInt8]) throws -> [UInt8] {
        let r = ByteReader(patch)
        guard r.hasPrefix(Array("PATCH".utf8)) else { throw PatchError.badFormat("missing PATCH header") }
        var out = source
        var p = 5
        while true {
            guard p + 3 <= patch.count else { throw PatchError.badFormat("missing EOF marker") }
            if patch[p] == 0x45 && patch[p + 1] == 0x4F && patch[p + 2] == 0x46 {
                p += 3
                if p + 3 <= patch.count {
                    let truncate = Int(patch[p]) << 16 | Int(patch[p + 1]) << 8 | Int(patch[p + 2])
                    if truncate < out.count { out.removeLast(out.count - truncate) }
                }
                return out
            }
            let offset = Int(patch[p]) << 16 | Int(patch[p + 1]) << 8 | Int(patch[p + 2])
            guard let size16 = r.u16be(p + 3) else { throw PatchError.badFormat("truncated record") }
            p += 5
            var size = Int(size16)
            var data: [UInt8]
            if size == 0 {
                guard let rle = r.u16be(p), let value = r.u8(p + 2) else { throw PatchError.badFormat("truncated RLE record") }
                size = Int(rle)
                data = [UInt8](repeating: value, count: size)
                p += 3
            } else {
                guard let chunk = r.slice(p, size) else { throw PatchError.badFormat("truncated data") }
                data = Array(chunk)
                p += size
            }
            if offset + size > out.count { out.append(contentsOf: [UInt8](repeating: 0, count: offset + size - out.count)) }
            out.replaceSubrange(offset..<(offset + size), with: data)
        }
    }

    static func create(original: [UInt8], modified: [UInt8]) throws -> [UInt8] {
        guard modified.count <= 0x100_0000 else { throw PatchError.badFormat("IPS can't address past 16 MiB; use BPS") }
        var out = Array("PATCH".utf8)
        var i = 0
        while i < modified.count {
            if i < original.count && original[i] == modified[i] { i += 1; continue }
            var start = i
            if start == 0x454F46 { start -= 1 }   // an offset spelling "EOF" would end the patch early
            var end = i + 1
            var gap = 0
            var j = i
            // Extend the record over short unchanged gaps (a new record costs 5 bytes).
            while j < modified.count && j - start < 0xFFFF {
                let differs = j >= original.count || original[j] != modified[j]
                if differs {
                    end = j + 1
                    gap = 0
                } else {
                    gap += 1
                    if gap > 5 { break }
                }
                j += 1
            }
            let length = end - start
            out += [UInt8(start >> 16 & 0xFF), UInt8(start >> 8 & 0xFF), UInt8(start & 0xFF), UInt8(length >> 8), UInt8(length & 0xFF)]
            out += modified[start..<end]
            i = end
        }
        out += Array("EOF".utf8)
        if modified.count < original.count {
            let n = modified.count
            out += [UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]
        }
        return out
    }
}

/// Variable-length numbers shared by BPS and UPS.
enum PatchNumber {
    static func encode(_ value: Int, into out: inout [UInt8]) {
        var n = value
        while true {
            let x = UInt8(n & 0x7F)
            n >>= 7
            if n == 0 { out.append(0x80 | x); return }
            out.append(x)
            n -= 1
        }
    }

    static func decode(_ bytes: [UInt8], _ p: inout Int) throws -> Int {
        var data = 0, shift = 1
        while true {
            guard p < bytes.count else { throw PatchError.badFormat("truncated number") }
            let x = Int(bytes[p])
            p += 1
            data += (x & 0x7F) * shift
            if x & 0x80 != 0 { return data }
            shift <<= 7
            data += shift
            guard shift < 1 << 56 else { throw PatchError.badFormat("number too large") }
        }
    }
}

/// BPS patches (byuu's format: any size, CRC-checked, supports moved data).
enum BPSPatch {
    static func apply(_ patch: [UInt8], to source: [UInt8]) throws -> [UInt8] {
        guard patch.count >= 19, ByteReader(patch).hasPrefix(Array("BPS1".utf8)) else { throw PatchError.badFormat("missing BPS1 header") }
        let r = ByteReader(patch)
        let footer = patch.count - 12
        guard let sourceCRC = r.u32(footer), let targetCRC = r.u32(footer + 4), let patchCRC = r.u32(footer + 8) else { throw PatchError.badFormat("footer") }
        guard CRC32.checksum(Array(patch[0..<(patch.count - 4)])) == patchCRC else { throw PatchError.badFormat("patch is damaged (CRC)") }
        guard CRC32.checksum(source) == sourceCRC else { throw PatchError.wrongSource("source CRC differs") }
        var p = 4
        let sourceSize = try PatchNumber.decode(patch, &p)
        let targetSize = try PatchNumber.decode(patch, &p)
        let metadataSize = try PatchNumber.decode(patch, &p)
        p += metadataSize
        guard sourceSize == source.count else { throw PatchError.wrongSource("source size differs") }
        var target = [UInt8](repeating: 0, count: targetSize)
        var out = 0, sourceRelative = 0, targetRelative = 0
        while p < footer {
            let data = try PatchNumber.decode(patch, &p)
            let command = data & 3
            let length = (data >> 2) + 1
            guard out + length <= targetSize else { throw PatchError.badFormat("writes past the end") }
            switch command {
            case 0:
                guard out + length <= source.count else { throw PatchError.badFormat("source read past the end") }
                for k in 0..<length { target[out + k] = source[out + k] }
            case 1:
                guard p + length <= footer else { throw PatchError.badFormat("truncated data") }
                for k in 0..<length { target[out + k] = patch[p + k] }
                p += length
            case 2:
                let d = try PatchNumber.decode(patch, &p)
                sourceRelative += (d & 1 != 0 ? -1 : 1) * (d >> 1)
                guard sourceRelative >= 0, sourceRelative + length <= source.count else { throw PatchError.badFormat("source copy out of range") }
                for k in 0..<length { target[out + k] = source[sourceRelative + k] }
                sourceRelative += length
            default:
                let d = try PatchNumber.decode(patch, &p)
                targetRelative += (d & 1 != 0 ? -1 : 1) * (d >> 1)
                guard targetRelative >= 0 else { throw PatchError.badFormat("target copy out of range") }
                for k in 0..<length {
                    guard targetRelative < out + k else { throw PatchError.badFormat("target copy reads ahead") }
                    target[out + k] = target[targetRelative]
                    targetRelative += 1
                }
            }
            out += length
        }
        guard CRC32.checksum(target) == targetCRC else { throw PatchError.badFormat("result CRC differs") }
        return target
    }

    /// A straightforward BPS: unchanged runs read from the source, changed bytes stored.
    static func create(original: [UInt8], modified: [UInt8], metadata: String = "") -> [UInt8] {
        var out = Array("BPS1".utf8)
        PatchNumber.encode(original.count, into: &out)
        PatchNumber.encode(modified.count, into: &out)
        let meta = Array(metadata.utf8)
        PatchNumber.encode(meta.count, into: &out)
        out += meta
        var i = 0
        while i < modified.count {
            var j = i
            while j < modified.count && j < original.count && original[j] == modified[j] { j += 1 }
            if j - i >= 4 || (j > i && j == modified.count) {
                PatchNumber.encode(((j - i - 1) << 2) | 0, into: &out)   // SourceRead
                i = j
                continue
            }
            // Changed bytes (and short unchanged gaps) up to the next run of 4 unchanged bytes.
            var end = modified.count
            var equalRun = 0
            j = i
            while j < modified.count {
                let same = j < original.count && original[j] == modified[j]
                if same {
                    equalRun += 1
                    if equalRun == 4 { end = j - 3; break }
                } else {
                    equalRun = 0
                }
                j += 1
            }
            PatchNumber.encode(((end - i - 1) << 2) | 1, into: &out)     // TargetRead
            out += modified[i..<end]
            i = end
        }
        var w = ByteWriter()
        w.u32(CRC32.checksum(original))
        w.u32(CRC32.checksum(modified))
        out += w.bytes
        var crc = ByteWriter()
        crc.u32(CRC32.checksum(out))
        return out + crc.bytes
    }
}

/// UPS patches (XOR-based; works in both directions).
enum UPSPatch {
    static func apply(_ patch: [UInt8], to source: [UInt8]) throws -> [UInt8] {
        guard patch.count >= 18, ByteReader(patch).hasPrefix(Array("UPS1".utf8)) else { throw PatchError.badFormat("missing UPS1 header") }
        let r = ByteReader(patch)
        let footer = patch.count - 12
        guard let inCRC = r.u32(footer), let outCRC = r.u32(footer + 4), let patchCRC = r.u32(footer + 8) else { throw PatchError.badFormat("footer") }
        guard CRC32.checksum(Array(patch[0..<(patch.count - 4)])) == patchCRC else { throw PatchError.badFormat("patch is damaged (CRC)") }
        var p = 4
        let inputSize = try PatchNumber.decode(patch, &p)
        let outputSize = try PatchNumber.decode(patch, &p)
        let sourceCRC = CRC32.checksum(source)
        let reverse = sourceCRC == outCRC && sourceCRC != inCRC
        guard sourceCRC == inCRC || reverse else { throw PatchError.wrongSource("source CRC differs") }
        let size = reverse ? inputSize : outputSize
        var out = [UInt8](repeating: 0, count: size)
        for k in 0..<Swift.min(size, source.count) { out[k] = source[k] }
        var offset = 0
        while p < footer {
            offset += try PatchNumber.decode(patch, &p)
            while p < footer {
                let x = patch[p]
                p += 1
                if offset < size { out[offset] = (offset < source.count ? source[offset] : 0) ^ x }
                offset += 1
                if x == 0 { break }
            }
        }
        guard CRC32.checksum(out) == (reverse ? inCRC : outCRC) else { throw PatchError.badFormat("result CRC differs") }
        return out
    }

    static func create(original: [UInt8], modified: [UInt8]) -> [UInt8] {
        var out = Array("UPS1".utf8)
        PatchNumber.encode(original.count, into: &out)
        PatchNumber.encode(modified.count, into: &out)
        let n = Swift.max(original.count, modified.count)
        func a(_ i: Int) -> UInt8 { i < original.count ? original[i] : 0 }
        func b(_ i: Int) -> UInt8 { i < modified.count ? modified[i] : 0 }
        var last = 0
        var i = 0
        while i < n {
            if a(i) == b(i) { i += 1; continue }
            PatchNumber.encode(i - last, into: &out)
            while i < n && a(i) != b(i) {
                out.append(a(i) ^ b(i))
                i += 1
            }
            out.append(0)
            i += 1
            last = i
        }
        var w = ByteWriter()
        w.u32(CRC32.checksum(original))
        w.u32(CRC32.checksum(modified))
        out += w.bytes
        var crc = ByteWriter()
        crc.u32(CRC32.checksum(out))
        return out + crc.bytes
    }
}

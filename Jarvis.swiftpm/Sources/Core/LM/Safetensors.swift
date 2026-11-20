import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Read-only memory-mapped file (weights are never copied into RAM wholesale).
final class MappedFile: @unchecked Sendable {
    let url: URL
    let size: Int
    let mappedLength: Int
    let base: UnsafeRawPointer

    init(url: URL) throws {
        self.url = url
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw LMError.io("cannot open \(url.lastPathComponent)") }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw LMError.io("cannot stat \(url.lastPathComponent)") }
        size = Int(st.st_size)
        let page = Int(sysconf(Int32(_SC_PAGESIZE)))
        mappedLength = max(page, (size + page - 1) / page * page)
        guard let p = mmap(nil, mappedLength, PROT_READ, MAP_PRIVATE, fd, 0), p != MAP_FAILED else {
            throw LMError.io("mmap failed for \(url.lastPathComponent)")
        }
        base = UnsafeRawPointer(p)
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: base), mappedLength) }
}

enum LMError: LocalizedError {
    case io(String), format(String), missing(String), unsupported(String)
    var errorDescription: String? {
        switch self {
        case .io(let s): return "I/O: \(s)"
        case .format(let s): return "Format: \(s)"
        case .missing(let s): return "Missing tensor: \(s)"
        case .unsupported(let s): return "Unsupported: \(s)"
        }
    }
}

enum TensorDType: String {
    case f32 = "F32", f16 = "F16", bf16 = "BF16", u32 = "U32", i32 = "I32", u8 = "U8", i64 = "I64"
    var size: Int {
        switch self {
        case .f32, .u32, .i32: return 4
        case .f16, .bf16: return 2
        case .u8: return 1
        case .i64: return 8
        }
    }
}

struct TensorInfo {
    let name: String
    let dtype: TensorDType
    let shape: [Int]
    /// Absolute byte offset in the file.
    let offset: Int
    let byteCount: Int
    let file: MappedFile

    var elementCount: Int { shape.reduce(1, *) }
    var pointer: UnsafeRawPointer { file.base + offset }

    /// Convert any float tensor to [Float].
    func floats() throws -> [Float] {
        let n = elementCount
        var out = [Float](repeating: 0, count: n)
        switch dtype {
        case .f32:
            let p = pointer.assumingMemoryBound(to: Float.self)
            for i in 0..<n { out[i] = p[i] }
        case .bf16:
            let p = pointer.assumingMemoryBound(to: UInt16.self)
            for i in 0..<n { out[i] = HalfConversion.bf16(p[i]) }
        case .f16:
            let p = pointer.assumingMemoryBound(to: UInt16.self)
            for i in 0..<n { out[i] = HalfConversion.f16(p[i]) }
        default:
            throw LMError.unsupported("dtype \(dtype.rawValue) for \(name)")
        }
        return out
    }
}

/// Parser for the safetensors format (single file or sharded with an index).
final class SafetensorsStore {
    private(set) var tensors: [String: TensorInfo] = [:]
    private var files: [MappedFile] = []

    init(directory: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".safetensors") }.sorted()
        guard !names.isEmpty else { throw LMError.missing("*.safetensors") }
        for n in names { try load(directory.appendingPathComponent(n)) }
    }

    init(file: URL) throws { try load(file) }

    private func load(_ url: URL) throws {
        let f = try MappedFile(url: url)
        files.append(f)
        guard f.size >= 8 else { throw LMError.format("file too small") }
        let headerLength = Int(f.base.loadUnaligned(as: UInt64.self).littleEndian)
        guard headerLength > 0, 8 + headerLength <= f.size else { throw LMError.format("bad header length") }
        let headerData = Data(bytes: f.base + 8, count: headerLength)
        guard let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] else { throw LMError.format("bad header JSON") }
        let dataStart = 8 + headerLength
        for (name, value) in header where name != "__metadata__" {
            guard let entry = value as? [String: Any], let dt = entry["dtype"] as? String, let dtype = TensorDType(rawValue: dt),
                  let shape = entry["shape"] as? [Int], let offsets = entry["data_offsets"] as? [Int], offsets.count == 2 else {
                throw LMError.format("bad entry \(name)")
            }
            tensors[name] = TensorInfo(name: name, dtype: dtype, shape: shape, offset: dataStart + offsets[0],
                                       byteCount: offsets[1] - offsets[0], file: f)
        }
    }

    func tensor(_ name: String) throws -> TensorInfo {
        guard let t = tensors[name] else { throw LMError.missing(name) }
        return t
    }

    func has(_ name: String) -> Bool { tensors[name] != nil }
}

/// Half-precision conversions without relying on `Float16` (unavailable on some targets).
enum HalfConversion {
    @inline(__always)
    static func bf16(_ bits: UInt16) -> Float { Float(bitPattern: UInt32(bits) << 16) }

    @inline(__always)
    static func f16(_ h: UInt16) -> Float {
        let sign = UInt32(h & 0x8000) << 16
        let exp = Int((h >> 10) & 0x1F)
        let mant = UInt32(h & 0x3FF)
        if exp == 0 {
            if mant == 0 { return Float(bitPattern: sign) }
            // Subnormal.
            var m = mant
            var e = -14
            while m & 0x400 == 0 { m <<= 1; e -= 1 }
            m &= 0x3FF
            return Float(bitPattern: sign | UInt32(e + 127) << 23 | m << 13)
        }
        if exp == 31 { return Float(bitPattern: sign | 0x7F80_0000 | mant << 13) }
        return Float(bitPattern: sign | UInt32(exp - 15 + 127) << 23 | mant << 13)
    }

    @inline(__always)
    static func toF16(_ f: Float) -> UInt16 {
        let x = f.bitPattern
        let sign = UInt16((x >> 16) & 0x8000)
        var exp = Int((x >> 23) & 0xFF) - 127 + 15
        var mant = x & 0x7F_FFFF
        if exp >= 31 { return sign | 0x7C00 }
        if exp <= 0 {
            if exp < -10 { return sign }
            mant |= 0x80_0000
            let shift = UInt32(14 - exp)
            return sign | UInt16(mant >> shift)
        }
        // Round to nearest.
        if mant & 0x1000 != 0 { mant += 0x2000; if mant & 0x80_0000 != 0 { mant = 0; exp += 1 } }
        if exp >= 31 { return sign | 0x7C00 }
        return sign | UInt16(exp) << 10 | UInt16(mant >> 13)
    }
}

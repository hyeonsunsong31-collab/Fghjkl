import Foundation

/// Minimal little-endian binary archive used to persist large neural state
/// (JSON would be far too slow/large for millions of synapses).
struct BinaryWriter {
    private(set) var data = Data()

    mutating func write<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    mutating func write(_ value: Float) { write(value.bitPattern) }
    mutating func write(_ value: Bool) { write(UInt8(value ? 1 : 0)) }

    mutating func write(_ string: String) {
        let bytes = Array(string.utf8)
        write(UInt32(bytes.count))
        data.append(contentsOf: bytes)
    }

    mutating func write(_ array: [Float]) {
        write(UInt32(array.count))
        array.withUnsafeBufferPointer { buf in
            for v in buf { write(v.bitPattern) }
        }
    }

    mutating func write(_ array: [Int32]) {
        write(UInt32(array.count))
        for v in array { write(v) }
    }

    mutating func write(_ array: [Int8]) {
        write(UInt32(array.count))
        for v in array { write(v) }
    }

    mutating func write(_ array: [UInt64]) {
        write(UInt32(array.count))
        for v in array { write(v) }
    }
}

enum BinaryArchiveError: Error {
    case truncated
    case badMagic
    case versionMismatch
}

struct BinaryReader {
    private let data: Data
    private(set) var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    var isAtEnd: Bool { offset >= data.endIndex }

    mutating func read<T: FixedWidthInteger>(_: T.Type = T.self) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.endIndex else { throw BinaryArchiveError.truncated }
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { dst in
            data.copyBytes(to: dst.bindMemory(to: UInt8.self), from: offset..<(offset + size))
        }
        offset += size
        return T(littleEndian: value)
    }

    mutating func readFloat() throws -> Float { Float(bitPattern: try read(UInt32.self)) }
    mutating func readBool() throws -> Bool { try read(UInt8.self) != 0 }

    mutating func readString() throws -> String {
        let count = Int(try read(UInt32.self))
        guard offset + count <= data.endIndex else { throw BinaryArchiveError.truncated }
        let s = String(decoding: data[offset..<(offset + count)], as: UTF8.self)
        offset += count
        return s
    }

    mutating func readFloats() throws -> [Float] {
        let count = Int(try read(UInt32.self))
        guard offset + count * 4 <= data.endIndex else { throw BinaryArchiveError.truncated }
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count { out[i] = try readFloat() }
        return out
    }

    mutating func readInt32s() throws -> [Int32] {
        let count = Int(try read(UInt32.self))
        guard offset + count * 4 <= data.endIndex else { throw BinaryArchiveError.truncated }
        var out = [Int32](repeating: 0, count: count)
        for i in 0..<count { out[i] = try read(Int32.self) }
        return out
    }

    mutating func readInt8s() throws -> [Int8] {
        let count = Int(try read(UInt32.self))
        guard offset + count <= data.endIndex else { throw BinaryArchiveError.truncated }
        var out = [Int8](repeating: 0, count: count)
        for i in 0..<count { out[i] = try read(Int8.self) }
        return out
    }

    mutating func readUInt64s() throws -> [UInt64] {
        let count = Int(try read(UInt32.self))
        guard offset + count * 8 <= data.endIndex else { throw BinaryArchiveError.truncated }
        var out = [UInt64](repeating: 0, count: count)
        for i in 0..<count { out[i] = try read(UInt64.self) }
        return out
    }
}

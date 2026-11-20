import Foundation

/// Sparse store of learned weight changes Δw for the procedural connectome.
///
/// The ~10¹⁴ logical synapses have procedurally generated base weights; only
/// synapses that actually learned something are stored here (open addressing,
/// linear probing, 64-bit keys → Float deltas). Persisted as a compact binary file.
final class PlasticityStore {
    private var keys: [UInt64]
    private var values: [Float]
    private(set) var count = 0
    private static let empty: UInt64 = 0

    init(capacity: Int = 1 << 14) {
        let cap = Self.powerOfTwo(atLeast: max(16, capacity))
        keys = [UInt64](repeating: Self.empty, count: cap)
        values = [Float](repeating: 0, count: cap)
    }

    var capacity: Int { keys.count }

    private static func powerOfTwo(atLeast n: Int) -> Int {
        var c = 1
        while c < n { c <<= 1 }
        return c
    }

    @inline(__always)
    private static func normalise(_ key: UInt64) -> UInt64 { key == empty ? 1 : key }

    @inline(__always)
    private func slot(for key: UInt64) -> Int {
        let mask = keys.count - 1
        var i = Int(truncatingIfNeeded: NeuroMath.mix64(key)) & mask
        while keys[i] != Self.empty && keys[i] != key {
            i = (i + 1) & mask
        }
        return i
    }

    func delta(for key: UInt64) -> Float {
        let k = Self.normalise(key)
        let i = slot(for: k)
        return keys[i] == k ? values[i] : 0
    }

    func add(_ delta: Float, for key: UInt64) {
        let k = Self.normalise(key)
        if (count + 1) * 10 > keys.count * 7 { grow() }
        let i = slot(for: k)
        if keys[i] == k {
            values[i] += delta
        } else {
            keys[i] = k
            values[i] = delta
            count += 1
        }
    }

    private func grow() {
        let oldKeys = keys, oldValues = values
        keys = [UInt64](repeating: Self.empty, count: oldKeys.count * 2)
        values = [Float](repeating: 0, count: oldKeys.count * 2)
        count = 0
        for (i, k) in oldKeys.enumerated() where k != Self.empty {
            let s = slot(for: k)
            keys[s] = k
            values[s] = oldValues[i]
            count += 1
        }
    }

    /// Multiply every delta by `factor` and drop those that became negligible
    /// (slow forgetting / consolidation housekeeping).
    func decay(factor: Float, prune threshold: Float = 1e-4) {
        var survivors: [(UInt64, Float)] = []
        survivors.reserveCapacity(count)
        for (i, k) in keys.enumerated() where k != Self.empty {
            let v = values[i] * factor
            if abs(v) >= threshold { survivors.append((k, v)) }
        }
        let cap = max(16, Self.powerOfTwo(atLeast: survivors.count * 2))
        keys = [UInt64](repeating: Self.empty, count: cap)
        values = [Float](repeating: 0, count: cap)
        count = 0
        for (k, v) in survivors {
            let s = slot(for: k)
            keys[s] = k
            values[s] = v
            count += 1
        }
    }

    /// Replace the contents with another store's (used when loading from disk).
    func replace(with other: PlasticityStore) {
        keys = other.keys
        values = other.values
        count = other.count
    }

    func serialized() -> Data {
        var w = BinaryWriter()
        w.write(UInt32(0x504C_5354)) // "PLST"
        w.write(UInt32(count))
        for (i, k) in keys.enumerated() where k != Self.empty {
            w.write(k)
            w.write(values[i])
        }
        return w.data
    }

    static func deserialize(_ data: Data) throws -> PlasticityStore {
        var r = BinaryReader(data)
        guard try r.read(UInt32.self) == 0x504C_5354 else { throw BinaryArchiveError.badMagic }
        let n = Int(try r.read(UInt32.self))
        let store = PlasticityStore(capacity: n * 2)
        for _ in 0..<n {
            let k = try r.read(UInt64.self)
            let v = try r.readFloat()
            store.add(v, for: k)
        }
        return store
    }
}

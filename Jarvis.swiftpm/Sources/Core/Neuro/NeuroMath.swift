import Foundation

/// Deterministic math helpers shared by the neural core.
///
/// Every procedural quantity in the 206-billion-neuron lattice (connections,
/// base weights, delays) is derived from these integer-only hash functions so
/// the CPU (Swift) and GPU (runtime-compiled Metal) paths produce bit-identical
/// connectomes.
enum NeuroMath {
    /// SplitMix64 finaliser — a strong 64-bit mixer.
    @inline(__always)
    static func mix64(_ input: UInt64) -> UInt64 {
        var z = input &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Hash of two 64-bit values (order-sensitive).
    @inline(__always)
    static func hash(_ a: UInt64, _ b: UInt64) -> UInt64 {
        mix64(a ^ mix64(b &+ 0x632B_E59B_D9B4_E019))
    }

    /// Hash of three 64-bit values.
    @inline(__always)
    static func hash(_ a: UInt64, _ b: UInt64, _ c: UInt64) -> UInt64 {
        hash(hash(a, b), c)
    }

    /// Uniform float in [0, 1) from the top 24 bits (exact in Float32 on every backend).
    @inline(__always)
    static func unit(_ h: UInt64) -> Float {
        Float(h >> 40) * (1.0 / 16_777_216.0)
    }

    /// Integer-only approximately-Gaussian offset with standard deviation `sigma`
    /// (Irwin–Hall sum of four bytes). Mirrors the Metal implementation exactly.
    @inline(__always)
    static func gaussianOffset(_ h: UInt64, sigma: Int64) -> Int64 {
        let a = Int64(h & 0xFF), b = Int64((h >> 8) & 0xFF)
        let c = Int64((h >> 16) & 0xFF), d = Int64((h >> 24) & 0xFF)
        // Var of one byte = (256^2 - 1)/12 ≈ 5461.25; four bytes → sd ≈ 147.8
        return ((a + b + c + d) - 510) * sigma / 148
    }

    /// Box–Muller Gaussian (CPU only — used for initialisation, not procedural topology).
    static func gaussian(_ h: UInt64) -> Float {
        let u1 = max(unit(h), 1e-7)
        let u2 = unit(mix64(h))
        return Float((-2 * log(Double(u1))).squareRoot() * cos(2 * Double.pi * Double(u2)))
    }

    @inline(__always)
    static func sigmoid(_ x: Float) -> Float { 1 / (1 + Float(exp(Double(-x)))) }

    @inline(__always)
    static func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T { min(max(x, lo), hi) }

    @inline(__always)
    static func softplus(_ x: Float) -> Float {
        x > 20 ? x : Float(log1p(exp(Double(x))))
    }
}

/// Small, fast, seedable RNG (SplitMix64) for reproducible network initialisation.
struct SplitMix64: RandomNumberGenerator {
    private(set) var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Float { NeuroMath.unit(next()) }
    mutating func nextGaussian() -> Float { NeuroMath.gaussian(next()) }
}

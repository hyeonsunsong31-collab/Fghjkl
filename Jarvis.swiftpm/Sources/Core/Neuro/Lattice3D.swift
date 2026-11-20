import Foundation

/// Linear index of a neuron inside the 3D lattice: `x + X·(y + Y·z)`.
/// Range: 0 ..< 206,158,430,208.
typealias NeuronID = UInt64

struct LatticeCoordinate: Hashable, Codable {
    var x: Int32
    var y: Int32
    var z: Int32

    init(_ x: Int32, _ y: Int32, _ z: Int32) {
        self.x = x; self.y = y; self.z = z
    }

    func distance(to other: LatticeCoordinate) -> Float {
        let dx = Float(x - other.x), dy = Float(y - other.y), dz = Float(z - other.z)
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}

/// Major brain systems (the three core components + supporting structures).
enum BrainSystem: String, CaseIterable, Codable {
    case cerebellum, cortex, thalamus, basalGanglia, hippocampus, amygdala, hypothalamus, brainstem

    var koreanName: String {
        switch self {
        case .cerebellum: return "소뇌"
        case .cortex: return "대뇌 피질"
        case .thalamus: return "시상"
        case .basalGanglia: return "기저핵"
        case .hippocampus: return "해마"
        case .amygdala: return "편도체"
        case .hypothalamus: return "시상하부"
        case .brainstem: return "뇌간"
        }
    }
}

/// Every anatomical region of the lattice.
enum BrainRegion: UInt8, CaseIterable, Codable {
    // Cerebellum
    case cerebellumGranule, cerebellumPurkinje, cerebellumMolecular, deepCerebellarNuclei
    // Cerebral cortex (6 layers; L2 and L3 merged)
    case cortexL1, cortexL23, cortexL4, cortexL5, cortexL6
    // Thalamus
    case thalamusSensoryRelay, thalamusMotorRelay, thalamusPulvinar, thalamusMediodorsal, thalamicReticular
    // Basal ganglia
    case striatum, globusPallidusExternal, globusPallidusInternal, subthalamicNucleus, substantiaNigraCompacta
    // Hippocampus
    case dentateGyrus, ca3, ca1
    // Limbic / hypothalamic
    case amygdala, hypothalamus, basalForebrain
    // Brainstem
    case pons, inferiorOlive, ventralTegmentalArea, locusCoeruleus, raphe, reticularFormation

    var system: BrainSystem {
        switch self {
        case .cerebellumGranule, .cerebellumPurkinje, .cerebellumMolecular, .deepCerebellarNuclei: return .cerebellum
        case .cortexL1, .cortexL23, .cortexL4, .cortexL5, .cortexL6: return .cortex
        case .thalamusSensoryRelay, .thalamusMotorRelay, .thalamusPulvinar, .thalamusMediodorsal, .thalamicReticular: return .thalamus
        case .striatum, .globusPallidusExternal, .globusPallidusInternal, .subthalamicNucleus, .substantiaNigraCompacta: return .basalGanglia
        case .dentateGyrus, .ca3, .ca1: return .hippocampus
        case .amygdala: return .amygdala
        case .hypothalamus: return .hypothalamus
        case .basalForebrain, .pons, .inferiorOlive, .ventralTegmentalArea, .locusCoeruleus, .raphe, .reticularFormation: return .brainstem
        }
    }
}

/// Integer box [x0,x1) × [y0,y1) × [z0,z1).
struct LatticeBox: Equatable {
    var x0: Int32, x1: Int32, y0: Int32, y1: Int32, z0: Int32, z1: Int32

    func contains(_ c: LatticeCoordinate) -> Bool {
        c.x >= x0 && c.x < x1 && c.y >= y0 && c.y < y1 && c.z >= z0 && c.z < z1
    }

    var volume: UInt64 { UInt64(x1 - x0) * UInt64(y1 - y0) * UInt64(z1 - z0) }
}

/// The 3D lattice that hosts **206,158,430,208** synaptic perceptrons.
///
/// The lattice is a mesh in *neural index space*. Because neuron counts (not
/// volumes) follow human proportions, the cerebellum — whose granule cells are
/// tiny and densely folded — occupies most of the lattice (78.1 %), the cerebral
/// cortex 18.75 %, and the subcortical core 3.1 %. Every site is a neuron and
/// every neuron is connected (see `ProceduralConnectome`).
enum Lattice3D {
    static let dimX: Int32 = 8192
    static let dimY: Int32 = 6144
    static let dimZ: Int32 = 4096
    static let totalNeurons: UInt64 = UInt64(dimX) * UInt64(dimY) * UInt64(dimZ) // 206,158,430,208

    // MARK: Layout constants
    static let cerebrumStartX: Int32 = 6400
    static let core = LatticeBox(x0: 6400, x1: 7424, y0: 1536, y1: 4608, z0: 1024, z1: 3072)
    static let dcn = LatticeBox(x0: 6144, x1: 6400, y0: 2560, y1: 3584, z0: 1536, z1: 2560)
    static let foliumPeriod: Int32 = 384      // 16 cerebellar folia
    static let purkinjeRow: Int32 = 376       // granule rows [0,376), Purkinje [376,378), molecular [378,384)
    static let cortexSheet: Int32 = 256       // 7 folded cortical sheets
    static let thalamusBox = LatticeBox(x0: 6400, x1: 7424, y0: 3840, y1: 4608, z0: 1024, z1: 3072)
    static let trnThickness: Int32 = 64
    static let trnTop: Int32 = 48

    // MARK: Indexing

    @inline(__always)
    static func id(_ c: LatticeCoordinate) -> NeuronID {
        UInt64(c.x) + UInt64(dimX) * (UInt64(c.y) + UInt64(dimY) * UInt64(c.z))
    }

    @inline(__always)
    static func coordinate(_ id: NeuronID) -> LatticeCoordinate {
        let x = id % UInt64(dimX)
        let rest = id / UInt64(dimX)
        let y = rest % UInt64(dimY)
        let z = rest / UInt64(dimY)
        return LatticeCoordinate(Int32(x), Int32(y), Int32(z))
    }

    static func isValid(_ c: LatticeCoordinate) -> Bool {
        c.x >= 0 && c.x < dimX && c.y >= 0 && c.y < dimY && c.z >= 0 && c.z < dimZ
    }

    static func clamped(_ c: LatticeCoordinate) -> LatticeCoordinate {
        LatticeCoordinate(NeuroMath.clamp(c.x, 0, dimX - 1),
                          NeuroMath.clamp(c.y, 0, dimY - 1),
                          NeuroMath.clamp(c.z, 0, dimZ - 1))
    }

    // MARK: Region map

    static func region(of id: NeuronID) -> BrainRegion { region(at: coordinate(id)) }

    static func region(at c: LatticeCoordinate) -> BrainRegion {
        if c.x < cerebrumStartX {
            if dcn.contains(c) { return .deepCerebellarNuclei }
            let row = c.y % foliumPeriod
            if row < purkinjeRow { return .cerebellumGranule }
            if row < purkinjeRow + 2 { return .cerebellumPurkinje }
            return .cerebellumMolecular
        }
        if core.contains(c) {
            let x = c.x, y = c.y
            switch y {
            case 1536..<2048:
                switch x {
                case ..<6656: return .pons
                case ..<6784: return .inferiorOlive
                case ..<6912: return .ventralTegmentalArea
                case ..<7040: return .locusCoeruleus
                case ..<7168: return .raphe
                default: return .reticularFormation
                }
            case 2048..<2304:
                return x < 6912 ? .hypothalamus : .basalForebrain
            case 2304..<2560:
                return .amygdala
            case 2560..<3072:
                if x < 6741 { return .dentateGyrus }
                if x < 7083 { return .ca3 }
                return .ca1
            case 3072..<3840:
                switch x {
                case ..<6912: return .striatum
                case ..<7040: return .globusPallidusExternal
                case ..<7168: return .globusPallidusInternal
                case ..<7296: return .subthalamicNucleus
                default: return .substantiaNigraCompacta
                }
            default: // 3840..<4608 thalamus
                if c.z < core.z0 + trnThickness || c.z >= core.z1 - trnThickness || c.y >= core.y1 - trnTop {
                    return .thalamicReticular
                }
                switch x {
                case ..<6656: return .thalamusSensoryRelay
                case ..<6912: return .thalamusMotorRelay
                case ..<7168: return .thalamusPulvinar
                default: return .thalamusMediodorsal
                }
            }
        }
        let layer = (c.x - cerebrumStartX) % cortexSheet
        switch layer {
        case ..<16: return .cortexL1
        case ..<96: return .cortexL23
        case ..<136: return .cortexL4
        case ..<200: return .cortexL5
        default: return .cortexL6
        }
    }

    // MARK: Geometry (sampling a coordinate inside a region)

    /// Base box of each region (before band/exclusion rules).
    static func baseBox(of region: BrainRegion) -> LatticeBox {
        switch region {
        case .cerebellumGranule, .cerebellumPurkinje, .cerebellumMolecular:
            return LatticeBox(x0: 0, x1: cerebrumStartX, y0: 0, y1: dimY, z0: 0, z1: dimZ)
        case .deepCerebellarNuclei: return dcn
        case .cortexL1, .cortexL23, .cortexL4, .cortexL5, .cortexL6:
            return LatticeBox(x0: cerebrumStartX, x1: dimX, y0: 0, y1: dimY, z0: 0, z1: dimZ)
        case .pons: return LatticeBox(x0: 6400, x1: 6656, y0: 1536, y1: 2048, z0: 1024, z1: 3072)
        case .inferiorOlive: return LatticeBox(x0: 6656, x1: 6784, y0: 1536, y1: 2048, z0: 1024, z1: 3072)
        case .ventralTegmentalArea: return LatticeBox(x0: 6784, x1: 6912, y0: 1536, y1: 2048, z0: 1024, z1: 3072)
        case .locusCoeruleus: return LatticeBox(x0: 6912, x1: 7040, y0: 1536, y1: 2048, z0: 1024, z1: 3072)
        case .raphe: return LatticeBox(x0: 7040, x1: 7168, y0: 1536, y1: 2048, z0: 1024, z1: 3072)
        case .reticularFormation: return LatticeBox(x0: 7168, x1: 7424, y0: 1536, y1: 2048, z0: 1024, z1: 3072)
        case .hypothalamus: return LatticeBox(x0: 6400, x1: 6912, y0: 2048, y1: 2304, z0: 1024, z1: 3072)
        case .basalForebrain: return LatticeBox(x0: 6912, x1: 7424, y0: 2048, y1: 2304, z0: 1024, z1: 3072)
        case .amygdala: return LatticeBox(x0: 6400, x1: 7424, y0: 2304, y1: 2560, z0: 1024, z1: 3072)
        case .dentateGyrus: return LatticeBox(x0: 6400, x1: 6741, y0: 2560, y1: 3072, z0: 1024, z1: 3072)
        case .ca3: return LatticeBox(x0: 6741, x1: 7083, y0: 2560, y1: 3072, z0: 1024, z1: 3072)
        case .ca1: return LatticeBox(x0: 7083, x1: 7424, y0: 2560, y1: 3072, z0: 1024, z1: 3072)
        case .striatum: return LatticeBox(x0: 6400, x1: 6912, y0: 3072, y1: 3840, z0: 1024, z1: 3072)
        case .globusPallidusExternal: return LatticeBox(x0: 6912, x1: 7040, y0: 3072, y1: 3840, z0: 1024, z1: 3072)
        case .globusPallidusInternal: return LatticeBox(x0: 7040, x1: 7168, y0: 3072, y1: 3840, z0: 1024, z1: 3072)
        case .subthalamicNucleus: return LatticeBox(x0: 7168, x1: 7296, y0: 3072, y1: 3840, z0: 1024, z1: 3072)
        case .substantiaNigraCompacta: return LatticeBox(x0: 7296, x1: 7424, y0: 3072, y1: 3840, z0: 1024, z1: 3072)
        case .thalamicReticular: return thalamusBox
        case .thalamusSensoryRelay: return LatticeBox(x0: 6400, x1: 6656, y0: 3840, y1: 4608 - trnTop, z0: 1024 + trnThickness, z1: 3072 - trnThickness)
        case .thalamusMotorRelay: return LatticeBox(x0: 6656, x1: 6912, y0: 3840, y1: 4608 - trnTop, z0: 1024 + trnThickness, z1: 3072 - trnThickness)
        case .thalamusPulvinar: return LatticeBox(x0: 6912, x1: 7168, y0: 3840, y1: 4608 - trnTop, z0: 1024 + trnThickness, z1: 3072 - trnThickness)
        case .thalamusMediodorsal: return LatticeBox(x0: 7168, x1: 7424, y0: 3840, y1: 4608 - trnTop, z0: 1024 + trnThickness, z1: 3072 - trnThickness)
        }
    }

    /// Band of a layered region along its laminar axis: (period, start, end) relative to origin.
    static func band(of region: BrainRegion) -> (period: Int32, start: Int32, end: Int32)? {
        switch region {
        case .cerebellumGranule: return (foliumPeriod, 0, purkinjeRow)
        case .cerebellumPurkinje: return (foliumPeriod, purkinjeRow, purkinjeRow + 2)
        case .cerebellumMolecular: return (foliumPeriod, purkinjeRow + 2, foliumPeriod)
        case .cortexL1: return (cortexSheet, 0, 16)
        case .cortexL23: return (cortexSheet, 16, 96)
        case .cortexL4: return (cortexSheet, 96, 136)
        case .cortexL5: return (cortexSheet, 136, 200)
        case .cortexL6: return (cortexSheet, 200, 256)
        default: return nil
        }
    }

    /// Deterministically pick a coordinate inside `region` near the normalised
    /// position (u, v, w) ∈ [0,1)³ of its base box. `h` supplies jitter and choices.
    static func sample(in region: BrainRegion, u: Float, v: Float, w: Float, hash h: UInt64) -> LatticeCoordinate {
        let box = baseBox(of: region)
        func lerp(_ a: Int32, _ b: Int32, _ t: Float) -> Int32 {
            let span = b - a
            let off = Int32(min(Float(span - 1), max(0, (t * Float(span)).rounded(.down))))
            return a + off
        }
        var c = LatticeCoordinate(lerp(box.x0, box.x1, u), lerp(box.y0, box.y1, v), lerp(box.z0, box.z1, w))

        if let band = band(of: region) {
            let width = band.end - band.start
            let jitter = Int32(truncatingIfNeeded: (h >> 32) % UInt64(width))
            if region.system == .cerebellum {
                let folium = c.y / band.period
                c.y = folium * band.period + band.start + jitter
                if dcn.contains(c) { c.x = dcn.x0 - 1 - Int32(truncatingIfNeeded: (h >> 12) % 256) }
            } else {
                let sheet = (c.x - cerebrumStartX) / band.period
                c.x = cerebrumStartX + sheet * band.period + band.start + jitter
                if core.contains(c) {
                    // Cortex wraps around the subcortical core: reflect out along y.
                    if c.y < 3072 {
                        c.y = (c.y - core.y0) % core.y0          // → [0, 1536)
                    } else {
                        c.y = core.y1 + (c.y - 3072) % (dimY - core.y1) // → [4608, 6144)
                    }
                }
            }
        }

        if region == .thalamicReticular {
            switch h % 3 {
            case 0: c.z = core.z0 + (c.z - core.z0) % trnThickness
            case 1: c.z = core.z1 - trnThickness + (c.z - core.z0) % trnThickness
            default: c.y = core.y1 - trnTop + (c.y - box.y0) % trnTop
            }
        }
        return c
    }

    /// Normalised position of a coordinate inside the base box of its region.
    static func normalisedPosition(_ c: LatticeCoordinate, in region: BrainRegion) -> (Float, Float, Float) {
        let b = baseBox(of: region)
        func n(_ v: Int32, _ a: Int32, _ e: Int32) -> Float {
            NeuroMath.clamp((Float(v - a) + 0.5) / Float(max(1, e - a)), 0, 0.9999)
        }
        return (n(c.x, b.x0, b.x1), n(c.y, b.y0, b.y1), n(c.z, b.z0, b.z1))
    }

    // MARK: Exact census

    /// Exact neuron count per region, computed by breakpoint compression over the
    /// piecewise-constant region map (≈ 20k cells instead of 2·10¹¹ sites).
    static func census() -> [BrainRegion: UInt64] {
        var xs: Set<Int32> = [0, dimX, cerebrumStartX, dcn.x0, dcn.x1, core.x0, core.x1,
                              6656, 6741, 6784, 6912, 7040, 7083, 7168, 7296, 7424]
        for s in 0..<7 {
            let base = cerebrumStartX + Int32(s) * cortexSheet
            for off: Int32 in [0, 16, 96, 136, 200, 256] { xs.insert(base + off) }
        }
        var ys: Set<Int32> = [0, dimY, core.y0, core.y1, dcn.y0, dcn.y1, 2048, 2304, 2560, 3072, 3840, core.y1 - trnTop]
        for f in 0...16 {
            let base = Int32(f) * foliumPeriod
            for off: Int32 in [0, purkinjeRow, purkinjeRow + 2] where base + off <= dimY { ys.insert(base + off) }
        }
        let zs: Set<Int32> = [0, dimZ, core.z0, core.z1, core.z0 + trnThickness, core.z1 - trnThickness, dcn.z0, dcn.z1]

        let sx = xs.filter { $0 >= 0 && $0 <= dimX }.sorted()
        let sy = ys.filter { $0 >= 0 && $0 <= dimY }.sorted()
        let sz = zs.sorted()
        var counts: [BrainRegion: UInt64] = [:]
        for i in 0..<(sx.count - 1) {
            for j in 0..<(sy.count - 1) {
                for k in 0..<(sz.count - 1) {
                    let c = LatticeCoordinate(sx[i], sy[j], sz[k])
                    let r = region(at: c)
                    let vol = UInt64(sx[i + 1] - sx[i]) * UInt64(sy[j + 1] - sy[j]) * UInt64(sz[k + 1] - sz[k])
                    counts[r, default: 0] += vol
                }
            }
        }
        return counts
    }

    static func systemCensus() -> [BrainSystem: UInt64] {
        var out: [BrainSystem: UInt64] = [:]
        for (r, n) in census() { out[r.system, default: 0] += n }
        return out
    }
}

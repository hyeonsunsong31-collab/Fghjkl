import Foundation

/// Raw triangle mesh (shared by RealityKit rendering and ModelIO export).
struct MeshData: Equatable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    var triangleCount: Int { indices.count / 3 }

    mutating func append(_ other: MeshData) {
        let base = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        uvs += other.uvs
        indices += other.indices.map { $0 + base }
    }

    /// Axis-aligned bounds.
    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard var lo = positions.first else { return (.zero, .zero) }
        var hi = lo
        for p in positions {
            lo = SIMD3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = SIMD3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        return (lo, hi)
    }

    /// Non-uniform scale with correctly transformed normals (n / s, renormalised).
    func scaled(_ s: SIMD3<Float>) -> MeshData {
        var m = self
        m.positions = positions.map { $0 * s }
        m.normals = normals.map { simdNormalize($0 / s) }
        return m
    }

    /// Stretched and centred to fill the unit box exactly (so `size` means the visible extent).
    func fitted() -> MeshData {
        let (lo, hi) = bounds
        let span = SIMD3<Float>(Swift.max(hi.x - lo.x, 1e-6), Swift.max(hi.y - lo.y, 1e-6), Swift.max(hi.z - lo.z, 1e-6))
        return translated(-(lo + hi) / 2).scaled(SIMD3(1, 1, 1) / span)
    }

    func translated(_ t: SIMD3<Float>) -> MeshData {
        var m = self
        m.positions = positions.map { $0 + t }
        return m
    }

    /// Make every triangle wind counter-clockwise seen from outside (agreeing with its
    /// vertex normals), so back-face culling never hides a face.
    func outwardWound() -> MeshData {
        var m = self
        var i = 0
        while i + 2 < m.indices.count {
            let a = Int(m.indices[i]), b = Int(m.indices[i + 1]), c = Int(m.indices[i + 2])
            let g = simdCross(m.positions[b] - m.positions[a], m.positions[c] - m.positions[a])
            let n = m.normals[a] + m.normals[b] + m.normals[c]
            if simdLength(g) > 1e-12 && simdDot(g, n) < 0 {
                m.indices.swapAt(i + 1, i + 2)
            }
            i += 3
        }
        return m
    }
}

/// Procedural primitives for the 3D project space. All shapes are centred at the
/// origin and fill their box: `size` = full width (x), height (y), depth (z) in metres.
enum MeshGenerator {
    /// Every shape the renderer understands (designs may use all of them).
    static let shapes: [String] = ["cube", "roundedCube", "sphere", "hemisphere", "cylinder", "halfCylinder", "tube",
                                   "cone", "frustum", "torus", "capsule", "pyramid", "wedge", "prism", "plane",
                                   "cup", "bowl", "bottle", "vase", "ogive"]

    /// `param` is shape specific (0 = default): roundedCube corner radius (fraction of the
    /// smallest half-extent), frustum top/bottom radius ratio, tube and cup wall thickness
    /// (fraction of the radius), prism number of sides.
    static func mesh(for shape: String, size: SIMD3<Float>, param: Float = 0, segments: Int = 32) -> MeshData {
        let s = SIMD3(Swift.max(size.x, 0.001), Swift.max(size.y, 0.001), Swift.max(size.z, 0.001))
        let n = Swift.max(8, segments)
        switch shape {
        case "cube":
            return box(s)
        case "roundedCube":
            return roundedBox(s, radiusRatio: param > 0 ? Swift.min(param, 1) : 0.3)
        case "sphere":
            return sphere(radius: 0.5, segments: n).scaled(s)
        case "hemisphere":
            return lathe(domeProfile(), segments: n).scaled(s)
        case "cylinder":
            return lathe(frustumProfile(topRatio: 1), segments: n).scaled(s)
        case "cone":
            return lathe(frustumProfile(topRatio: 0), segments: n).scaled(s)
        case "frustum":
            return lathe(frustumProfile(topRatio: param > 0 ? Swift.min(param, 3) : 0.6), segments: n).scaled(s)
        case "tube":
            return lathe(tubeProfile(wall: param > 0 ? Swift.min(param, 0.95) : 0.2), segments: n).scaled(s)
        case "halfCylinder":
            return halfCylinderUnit(segments: n).scaled(s)
        case "torus":
            return torusFitted(s, segments: n)
        case "capsule":
            return capsuleFitted(s, segments: n)
        case "pyramid":
            return pyramidUnit().scaled(s)
        case "wedge":
            return wedgeUnit().scaled(s)
        case "prism":
            return prismUnit(sides: param >= 3 ? Int(param) : 6).scaled(s)
        case "plane":
            return box(SIMD3(s.x, Swift.min(Swift.max(s.y, 0.004), 0.02), s.z))
        case "cup":
            return lathe(cupProfile(wall: param > 0 ? Swift.min(param, 0.6) : 0.12), segments: n).scaled(s)
        case "bowl":
            return lathe(bowlProfile(), segments: n).scaled(s)
        case "bottle":
            return lathe(bottleProfile(), segments: n).scaled(s)
        case "vase":
            return lathe(vaseProfile(), segments: n).scaled(s)
        case "ogive":
            return lathe(ogiveProfile(), segments: n).scaled(s)
        default:
            return box(s)
        }
    }

    static func defaultSize(for shape: String) -> SIMD3<Float> {
        switch shape {
        case "plane": return SIMD3(0.6, 0.02, 0.6)
        case "capsule", "cylinder", "cone", "frustum", "tube", "prism", "ogive": return SIMD3(0.2, 0.3, 0.2)
        case "torus": return SIMD3(0.3, 0.06, 0.3)
        case "hemisphere": return SIMD3(0.26, 0.13, 0.26)
        case "halfCylinder": return SIMD3(0.3, 0.13, 0.26)
        case "wedge": return SIMD3(0.24, 0.16, 0.3)
        case "cup", "bowl": return SIMD3(0.18, 0.16, 0.18)
        case "bottle", "vase": return SIMD3(0.14, 0.32, 0.14)
        default: return SIMD3(0.22, 0.22, 0.22)
        }
    }

    // MARK: Boxes

    static func box(_ s: SIMD3<Float>) -> MeshData {
        let h = s / 2
        var m = MeshData()
        for (n, up, right) in boxFaces {
            let base = UInt32(m.positions.count)
            let corners: [(Float, Float)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            for (u, v) in corners {
                let p = (n + right * u + up * v) * h
                m.positions.append(p)
                m.normals.append(n)
                m.uvs.append(SIMD2((u + 1) / 2, (v + 1) / 2))
            }
            m.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return m
    }

    private static let boxFaces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
        (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, -1)),
        (SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)),
        (SIMD3(0, 1, 0), SIMD3(0, 0, -1), SIMD3(1, 0, 0)),
        (SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 0)),
        (SIMD3(0, 0, 1), SIMD3(0, 1, 0), SIMD3(1, 0, 0)),
        (SIMD3(0, 0, -1), SIMD3(0, 1, 0), SIMD3(-1, 0, 0)),
    ]

    /// Box with rounded edges and corners: each face is a grid whose border cells wrap
    /// around the edges (evenly spaced in angle), giving smooth highlights.
    static func roundedBox(_ s: SIMD3<Float>, radiusRatio: Float) -> MeshData {
        let h = s / 2
        let r = Swift.max(0.0005, radiusRatio * Swift.min(h.x, h.y, h.z))
        let inner = h - SIMD3(repeating: r)
        let steps = 4
        // Grid coordinates (-1…1 across the face) that place `steps` cells on each rounded border.
        func axis(_ half: Float) -> [Float] {
            let core = Swift.max(half - r, 0)
            var lo: [Float] = []
            for k in stride(from: steps, through: 1, by: -1) {
                let a = Float(k) / Float(steps) * (.pi / 4)
                lo.append(-(core + r * tan(a)))
            }
            let mid: [Float] = core > 0 ? [-core, 0, core] : [0]
            let hi = lo.reversed().map { -$0 }
            return (lo + mid + hi).map { $0 / Swift.max(half, 1e-6) }
        }
        var m = MeshData()
        for (n, up, right) in boxFaces {
            let hu = simdDot(simdAbs(right), h), hv = simdDot(simdAbs(up), h)
            let us = axis(hu), vs = axis(hv)
            let base = UInt32(m.positions.count)
            for v in vs {
                for u in us {
                    let p = n * simdDot(simdAbs(n), h) + right * (u * hu) + up * (v * hv)
                    let q = SIMD3(Swift.min(Swift.max(p.x, -inner.x), inner.x),
                                  Swift.min(Swift.max(p.y, -inner.y), inner.y),
                                  Swift.min(Swift.max(p.z, -inner.z), inner.z))
                    let dir = simdNormalize(p - q)
                    m.positions.append(q + dir * r)
                    m.normals.append(dir)
                    m.uvs.append(SIMD2((u + 1) / 2, (v + 1) / 2))
                }
            }
            let cols = UInt32(us.count)
            for j in 0..<UInt32(vs.count - 1) {
                for i in 0..<UInt32(us.count - 1) {
                    let a = base + j * cols + i, b = a + 1, c = a + cols + 1, d = a + cols
                    m.indices += [a, b, c, a, c, d]
                }
            }
        }
        return m.outwardWound()
    }

    // MARK: Surfaces of revolution

    /// Surface of revolution about the y axis. Each path is a list of (radius, y) points
    /// with smooth normals within the path (paths meet at hard edges). Paths run with the
    /// outside on their right-hand side, i.e. counter-clockwise around the solid in the
    /// (radius, y) half-plane.
    static func lathe(_ paths: [[SIMD2<Float>]], segments: Int) -> MeshData {
        var m = MeshData()
        for path in paths where path.count >= 2 {
            let base = UInt32(m.positions.count)
            var lengths: [Float] = [0]
            for k in 1..<path.count {
                let d = path[k] - path[k - 1]
                lengths.append(lengths[k - 1] + (d * d).sum().squareRoot())
            }
            let total = Swift.max(lengths[path.count - 1], 1e-6)
            for k in path.indices {
                let t = path[Swift.min(path.count - 1, k + 1)] - path[Swift.max(0, k - 1)]
                var n2 = SIMD2<Float>(t.y, -t.x)
                let len = (n2 * n2).sum().squareRoot()
                n2 = len > 0 ? n2 / len : SIMD2(1, 0)
                let p = path[k]
                for j in 0...segments {
                    let a = Float(j) / Float(segments) * 2 * .pi
                    let c = cos(a), s = sin(a)
                    m.positions.append(SIMD3(p.x * c, p.y, p.x * s))
                    m.normals.append(SIMD3(n2.x * c, n2.y, n2.x * s))
                    m.uvs.append(SIMD2(Float(j) / Float(segments), lengths[k] / total))
                }
            }
            let stride = UInt32(segments + 1)
            for k in 0..<UInt32(path.count - 1) {
                for j in 0..<UInt32(segments) {
                    let a = base + k * stride + j, b = a + stride
                    m.indices += [a, b, a + 1, a + 1, b, b + 1]
                }
            }
        }
        return m.outwardWound()
    }

    /// Unit profiles (radius ≤ 0.5, y from -0.5 to 0.5).
    static func frustumProfile(topRatio: Float) -> [[SIMD2<Float>]] {
        let top = 0.5 * topRatio
        var paths: [[SIMD2<Float>]] = [[SIMD2(0, -0.5), SIMD2(0.5, -0.5)], [SIMD2(0.5, -0.5), SIMD2(top, 0.5)]]
        if top > 0.0001 { paths.append([SIMD2(top, 0.5), SIMD2(0, 0.5)]) }
        return paths
    }

    static func domeProfile(steps: Int = 12) -> [[SIMD2<Float>]] {
        let arc = (0...steps).map { k -> SIMD2<Float> in
            let a = Float(k) / Float(steps) * (.pi / 2)
            return SIMD2(0.5 * cos(a), -0.5 + sin(a))
        }
        return [[SIMD2(0, -0.5), SIMD2(0.5, -0.5)], arc]
    }

    static func tubeProfile(wall: Float) -> [[SIMD2<Float>]] {
        let ri = 0.5 * (1 - wall)
        return [[SIMD2(ri, -0.5), SIMD2(0.5, -0.5)], [SIMD2(0.5, -0.5), SIMD2(0.5, 0.5)],
                [SIMD2(0.5, 0.5), SIMD2(ri, 0.5)], [SIMD2(ri, 0.5), SIMD2(ri, -0.5)]]
    }

    /// Open-topped vessel with a floor (mug, cup, pot, bucket).
    static func cupProfile(wall: Float) -> [[SIMD2<Float>]] {
        let ri = 0.5 * (1 - wall)
        let floor: Float = -0.5 + 0.08
        return [[SIMD2(0, -0.5), SIMD2(0.5, -0.5)], [SIMD2(0.5, -0.5), SIMD2(0.5, 0.5)],
                [SIMD2(0.5, 0.5), SIMD2(ri, 0.5)], [SIMD2(ri, 0.5), SIMD2(ri, floor)], [SIMD2(ri, floor), SIMD2(0, floor)]]
    }

    static func bowlProfile(steps: Int = 12) -> [[SIMD2<Float>]] {
        let outer = (0...steps).map { k -> SIMD2<Float> in
            let a = -Float.pi / 2 + Float(k) / Float(steps) * (.pi / 2)
            return SIMD2(0.5 * cos(a), 0.5 + sin(a))
        }
        let ri: Float = 0.45, depth: Float = 0.9
        let inner = (0...steps).map { k -> SIMD2<Float> in
            let a = -Float(k) / Float(steps) * (.pi / 2)
            return SIMD2(ri * cos(a), 0.5 + depth * sin(a))
        }
        return [outer, [SIMD2(0.5, 0.5), SIMD2(ri, 0.5)], inner]
    }

    static func bottleProfile() -> [[SIMD2<Float>]] {
        let body: [SIMD2<Float>] = [SIMD2(0.45, -0.5), SIMD2(0.5, -0.45), SIMD2(0.5, 0.08), SIMD2(0.47, 0.17),
                                    SIMD2(0.38, 0.25), SIMD2(0.26, 0.3), SIMD2(0.18, 0.34), SIMD2(0.16, 0.39), SIMD2(0.16, 0.44)]
        return [[SIMD2(0, -0.5), SIMD2(0.45, -0.5)], body,
                [SIMD2(0.16, 0.44), SIMD2(0.19, 0.45), SIMD2(0.19, 0.5)], [SIMD2(0.19, 0.5), SIMD2(0, 0.5)]]
    }

    static func vaseProfile() -> [[SIMD2<Float>]] {
        let body: [SIMD2<Float>] = [SIMD2(0.3, -0.5), SIMD2(0.42, -0.36), SIMD2(0.5, -0.15), SIMD2(0.47, 0.05),
                                    SIMD2(0.36, 0.22), SIMD2(0.25, 0.34), SIMD2(0.23, 0.42), SIMD2(0.28, 0.5)]
        return [[SIMD2(0, -0.5), SIMD2(0.3, -0.5)], body, [SIMD2(0.28, 0.5), SIMD2(0, 0.5)]]
    }

    /// Rounded nose cone (rocket nose, bullet, missile tip).
    static func ogiveProfile(steps: Int = 14) -> [[SIMD2<Float>]] {
        let side = (0...steps).map { k -> SIMD2<Float> in
            let u = Float(k) / Float(steps)
            return SIMD2(0.5 * pow(Swift.max(0, 1 - pow(u, 2.2)), 0.55), -0.5 + u)
        }
        return [[SIMD2(0, -0.5), SIMD2(0.5, -0.5)], side]
    }

    static func sphere(radius r: Float, segments: Int) -> MeshData {
        var m = MeshData()
        let rings = Swift.max(8, segments / 2)
        for i in 0...rings {
            let v = Float(i) / Float(rings)
            let phi = v * .pi
            for j in 0...segments {
                let u = Float(j) / Float(segments)
                let theta = u * 2 * .pi
                let n = SIMD3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                m.positions.append(n * r)
                m.normals.append(n)
                m.uvs.append(SIMD2(u, 1 - v))
            }
        }
        let stride = UInt32(segments + 1)
        for i in 0..<UInt32(rings) {
            for j in 0..<UInt32(segments) {
                let a = i * stride + j, b = a + stride
                m.indices += [a, a + 1, b, a + 1, b + 1, b]
            }
        }
        return m
    }

    static func cylinder(radius r: Float, height h: Float, segments: Int) -> MeshData {
        lathe(frustumProfile(topRatio: 1), segments: segments).scaled(SIMD3(2 * r, h, 2 * r))
    }

    static func cone(radius r: Float, height h: Float, segments: Int) -> MeshData {
        lathe(frustumProfile(topRatio: 0), segments: segments).scaled(SIMD3(2 * r, h, 2 * r))
    }

    static func torus(majorRadius R: Float, minorRadius r: Float, segments: Int, sides: Int) -> MeshData {
        var m = MeshData()
        for i in 0...segments {
            let u = Float(i) / Float(segments) * 2 * .pi
            let center = SIMD3(R * cos(u), 0, R * sin(u))
            for j in 0...sides {
                let v = Float(j) / Float(sides) * 2 * .pi
                let n = SIMD3(cos(v) * cos(u), sin(v), cos(v) * sin(u))
                m.positions.append(center + n * r)
                m.normals.append(n)
                m.uvs.append(SIMD2(Float(i) / Float(segments), Float(j) / Float(sides)))
            }
        }
        let s = UInt32(sides + 1)
        for i in 0..<UInt32(segments) {
            for j in 0..<UInt32(sides) {
                let a = i * s + j, b = a + s
                m.indices += [a, a + 1, b, a + 1, b + 1, b]
            }
        }
        return m
    }

    /// Ring lying flat: outer diameter = width (x; depth z may differ), tube thickness = height.
    static func torusFitted(_ s: SIMD3<Float>, segments: Int) -> MeshData {
        let outer = s.x / 2
        let r = Swift.min(s.y / 2, outer * 0.48)
        let ring = torus(majorRadius: outer - r, minorRadius: r, segments: segments, sides: Swift.max(12, segments / 2))
        return ring.scaled(SIMD3(1, s.y / Swift.max(2 * r, 1e-6), s.z / Swift.max(s.x, 1e-6)))
    }

    static func capsule(radius r: Float, height h: Float, segments: Int) -> MeshData {
        let body = Swift.max(0, h - 2 * r) / 2
        let steps = Swift.max(4, segments / 4)
        var path: [SIMD2<Float>] = []
        for k in 0...steps {
            let a = -Float.pi / 2 + Float(k) / Float(steps) * (.pi / 2)
            path.append(SIMD2(r * cos(a), -body + r * sin(a)))
        }
        for k in 0...steps {
            let a = Float(k) / Float(steps) * (.pi / 2)
            path.append(SIMD2(r * cos(a), body + r * sin(a)))
        }
        return lathe([path], segments: segments)
    }

    static func capsuleFitted(_ s: SIMD3<Float>, segments: Int) -> MeshData {
        let r = Swift.min(s.x, s.z) / 2
        let height = Swift.max(s.y, 2 * r)
        return capsule(radius: r, height: height, segments: segments)
            .scaled(SIMD3(s.x / (2 * r), s.y / height, s.z / (2 * r)))
    }

    // MARK: Faceted solids

    /// Flat polygon (convex, any winding) facing `normal`.
    private static func addPolygon(_ m: inout MeshData, _ points: [SIMD3<Float>], normal: SIMD3<Float>) {
        let base = UInt32(m.positions.count)
        for (k, p) in points.enumerated() {
            m.positions.append(p)
            m.normals.append(normal)
            let a = Float(k) / Float(points.count) * 2 * .pi
            m.uvs.append(SIMD2(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)))
        }
        for k in 1..<UInt32(points.count - 1) { m.indices += [base, base + k, base + k + 1] }
    }

    static func pyramid(base b: Float, height h: Float) -> MeshData {
        pyramidUnit().scaled(SIMD3(b, h, b))
    }

    static func pyramidUnit() -> MeshData {
        var m = MeshData()
        let apex = SIMD3<Float>(0, 0.5, 0)
        let c: [SIMD3<Float>] = [SIMD3(-0.5, -0.5, -0.5), SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, -0.5, 0.5), SIMD3(-0.5, -0.5, 0.5)]
        for k in 0..<4 {
            let a = c[k], b = c[(k + 1) % 4]
            var n = simdNormalize(simdCross(b - a, apex - a))
            if simdDot(n, (a + b) / 2) < 0 { n = -n }
            addPolygon(&m, [a, b, apex], normal: n)
        }
        addPolygon(&m, c, normal: SIMD3(0, -1, 0))
        return m.outwardWound()
    }

    /// Ramp: full height at the back (-z), sloping down to the front (+z) edge.
    static func wedgeUnit() -> MeshData {
        var m = MeshData()
        let b0 = SIMD3<Float>(-0.5, -0.5, -0.5), b1 = SIMD3<Float>(0.5, -0.5, -0.5)
        let f0 = SIMD3<Float>(-0.5, -0.5, 0.5), f1 = SIMD3<Float>(0.5, -0.5, 0.5)
        let t0 = SIMD3<Float>(-0.5, 0.5, -0.5), t1 = SIMD3<Float>(0.5, 0.5, -0.5)
        addPolygon(&m, [b0, b1, f1, f0], normal: SIMD3(0, -1, 0))
        addPolygon(&m, [b0, t0, t1, b1], normal: SIMD3(0, 0, -1))
        addPolygon(&m, [t0, f0, f1, t1], normal: simdNormalize(SIMD3(0, 1, 1)))
        addPolygon(&m, [b0, f0, t0], normal: SIMD3(-1, 0, 0))
        addPolygon(&m, [b1, t1, f1], normal: SIMD3(1, 0, 0))
        return m.outwardWound()
    }

    /// Regular n-sided prism (hexagonal by default), flat side facing the front.
    static func prismUnit(sides: Int) -> MeshData {
        let n = Swift.min(Swift.max(sides, 3), 24)
        var m = MeshData()
        let ring = (0..<n).map { k -> SIMD2<Float> in
            let a = (Float(k) + 0.5) / Float(n) * 2 * .pi + .pi / 2
            return SIMD2(0.5 * cos(a), 0.5 * sin(a))
        }
        addPolygon(&m, ring.map { SIMD3($0.x, 0.5, $0.y) }, normal: SIMD3(0, 1, 0))
        addPolygon(&m, ring.map { SIMD3($0.x, -0.5, $0.y) }, normal: SIMD3(0, -1, 0))
        for k in 0..<n {
            let a = ring[k], b = ring[(k + 1) % n]
            let mid = (a + b) / 2
            let normal = simdNormalize(SIMD3(mid.x, 0, mid.y))
            addPolygon(&m, [SIMD3(a.x, -0.5, a.y), SIMD3(b.x, -0.5, b.y), SIMD3(b.x, 0.5, b.y), SIMD3(a.x, 0.5, a.y)], normal: normal)
        }
        return m.outwardWound().fitted()
    }

    /// Half cylinder lying along x with its flat face down (arched roof, tunnel, fender).
    static func halfCylinderUnit(segments: Int) -> MeshData {
        var m = MeshData()
        let steps = Swift.max(8, segments / 2)
        let base = UInt32(m.positions.count)
        for k in 0...steps {
            let a = Float(k) / Float(steps) * .pi
            let n = SIMD3<Float>(0, sin(a), cos(a))
            for x in [Float(-0.5), Float(0.5)] {
                m.positions.append(SIMD3(x, sin(a), cos(a)))
                m.normals.append(n)
                m.uvs.append(SIMD2(x + 0.5, Float(k) / Float(steps)))
            }
        }
        for k in 0..<UInt32(steps) {
            let a = base + 2 * k
            m.indices += [a, a + 1, a + 3, a, a + 3, a + 2]
        }
        let arc = (0...steps).map { k -> (Float, Float) in
            let a = Float(k) / Float(steps) * .pi
            return (cos(a), sin(a))
        }
        for x in [Float(-0.5), Float(0.5)] {
            addPolygon(&m, [SIMD3(x, 0, 0)] + arc.map { SIMD3(x, $0.1, $0.0) }, normal: SIMD3(x > 0 ? 1 : -1, 0, 0))
        }
        addPolygon(&m, [SIMD3(-0.5, 0, -1), SIMD3(0.5, 0, -1), SIMD3(0.5, 0, 1), SIMD3(-0.5, 0, 1)], normal: SIMD3(0, -1, 0))
        // Fit to the unit box: z from -1…1 → -0.5…0.5, y from 0…1 → -0.5…0.5.
        return m.outwardWound().scaled(SIMD3(1, 1, 0.5)).translated(SIMD3(0, -0.5, 0))
    }

    /// Wavefront OBJ text (universal export format, also an artefact type).
    static func obj(_ meshes: [(name: String, mesh: MeshData, transform: (SIMD3<Float>) -> SIMD3<Float>)]) -> String {
        var out = "# Exported by Jarvis\n"
        var offset = 1
        for (name, mesh, transform) in meshes {
            out += "o \(name)\n"
            for p in mesh.positions {
                let t = transform(p)
                out += "v \(t.x) \(t.y) \(t.z)\n"
            }
            for n in mesh.normals { out += "vn \(n.x) \(n.y) \(n.z)\n" }
            for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = Int(mesh.indices[i]) + offset, b = Int(mesh.indices[i + 1]) + offset, c = Int(mesh.indices[i + 2]) + offset
                out += "f \(a)//\(a) \(b)//\(b) \(c)//\(c)\n"
            }
            offset += mesh.positions.count
        }
        return out
    }
}

@inline(__always) func simdLength(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }
@inline(__always) func simdNormalize(_ v: SIMD3<Float>) -> SIMD3<Float> { let l = simdLength(v); return l > 0 ? v / l : v }
@inline(__always) func simdCross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}
@inline(__always) func simdDot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { (a * b).sum() }
@inline(__always) func simdAbs(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(abs(v.x), abs(v.y), abs(v.z)) }

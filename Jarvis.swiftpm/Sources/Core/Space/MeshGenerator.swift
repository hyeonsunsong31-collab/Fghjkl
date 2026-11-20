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
}

/// Procedural primitives for the 3D project space. All shapes are centred at
/// the origin and sized in metres (`size` = full width, height, depth).
enum MeshGenerator {
    static func mesh(for shape: String, size: SIMD3<Float>, segments: Int = 32) -> MeshData {
        switch shape {
        case "cube": return box(size)
        case "sphere": return sphere(radius: size.x / 2, segments: segments)
        case "cylinder": return cylinder(radius: size.x / 2, height: size.y, segments: segments)
        case "cone": return cone(radius: size.x / 2, height: size.y, segments: segments)
        case "torus": return torus(majorRadius: size.x / 2 * 0.72, minorRadius: size.x / 2 * 0.28, segments: segments, sides: max(12, segments / 2))
        case "capsule": return capsule(radius: size.x / 2, height: size.y, segments: segments)
        case "pyramid": return pyramid(base: size.x, height: size.y)
        case "plane": return box(SIMD3(size.x, max(0.004, size.y * 0.02), size.z))
        default: return box(size)
        }
    }

    static func defaultSize(for shape: String) -> SIMD3<Float> {
        switch shape {
        case "plane": return SIMD3(0.6, 0.6, 0.6)
        case "capsule", "cylinder", "cone": return SIMD3(0.2, 0.3, 0.2)
        case "torus": return SIMD3(0.3, 0.1, 0.3)
        default: return SIMD3(0.22, 0.22, 0.22)
        }
    }

    static func box(_ s: SIMD3<Float>) -> MeshData {
        let h = s / 2
        var m = MeshData()
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, -1)),
            (SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)),
            (SIMD3(0, 1, 0), SIMD3(0, 0, -1), SIMD3(1, 0, 0)),
            (SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 0)),
            (SIMD3(0, 0, 1), SIMD3(0, 1, 0), SIMD3(1, 0, 0)),
            (SIMD3(0, 0, -1), SIMD3(0, 1, 0), SIMD3(-1, 0, 0)),
        ]
        for (n, up, right) in faces {
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

    static func sphere(radius r: Float, segments: Int) -> MeshData {
        var m = MeshData()
        let rings = max(8, segments / 2)
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

    private static func ring(radius: Float, y: Float, segments: Int, normal: (Float) -> SIMD3<Float>) -> [(SIMD3<Float>, SIMD3<Float>)] {
        (0...segments).map { j in
            let t = Float(j) / Float(segments) * 2 * .pi
            return (SIMD3(radius * cos(t), y, radius * sin(t)), normal(t))
        }
    }

    private static func disc(radius: Float, y: Float, up: Bool, segments: Int) -> MeshData {
        var m = MeshData()
        let n: SIMD3<Float> = up ? SIMD3(0, 1, 0) : SIMD3(0, -1, 0)
        m.positions.append(SIMD3(0, y, 0)); m.normals.append(n); m.uvs.append(SIMD2(0.5, 0.5))
        for j in 0...segments {
            let t = Float(j) / Float(segments) * 2 * .pi
            m.positions.append(SIMD3(radius * cos(t), y, radius * sin(t)))
            m.normals.append(n)
            m.uvs.append(SIMD2(0.5 + 0.5 * cos(t), 0.5 + 0.5 * sin(t)))
        }
        for j in 1...UInt32(segments) {
            m.indices += up ? [0, j + 1, j] : [0, j, j + 1]
        }
        return m
    }

    static func cylinder(radius r: Float, height h: Float, segments: Int) -> MeshData {
        var m = MeshData()
        let bottom = ring(radius: r, y: -h / 2, segments: segments) { SIMD3(cos($0), 0, sin($0)) }
        let top = ring(radius: r, y: h / 2, segments: segments) { SIMD3(cos($0), 0, sin($0)) }
        for (k, (p, n)) in bottom.enumerated() { m.positions.append(p); m.normals.append(n); m.uvs.append(SIMD2(Float(k) / Float(segments), 0)) }
        for (k, (p, n)) in top.enumerated() { m.positions.append(p); m.normals.append(n); m.uvs.append(SIMD2(Float(k) / Float(segments), 1)) }
        let s = UInt32(segments + 1)
        for j in 0..<UInt32(segments) { m.indices += [j, j + s, j + 1, j + 1, j + s, j + s + 1] }
        m.append(disc(radius: r, y: h / 2, up: true, segments: segments))
        m.append(disc(radius: r, y: -h / 2, up: false, segments: segments))
        return m
    }

    static func cone(radius r: Float, height h: Float, segments: Int) -> MeshData {
        var m = MeshData()
        let slope = r / h
        for j in 0...segments {
            let t = Float(j) / Float(segments) * 2 * .pi
            let n = simdNormalize(SIMD3(cos(t), slope, sin(t)))
            m.positions.append(SIMD3(r * cos(t), -h / 2, r * sin(t))); m.normals.append(n); m.uvs.append(SIMD2(Float(j) / Float(segments), 0))
            m.positions.append(SIMD3(0, h / 2, 0)); m.normals.append(n); m.uvs.append(SIMD2(Float(j) / Float(segments), 1))
        }
        for j in 0..<UInt32(segments) {
            let a = j * 2
            m.indices += [a, a + 1, a + 2]
        }
        m.append(disc(radius: r, y: -h / 2, up: false, segments: segments))
        return m
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

    static func capsule(radius r: Float, height h: Float, segments: Int) -> MeshData {
        let body = max(0, h - 2 * r)
        var m = cylinderSide(radius: r, height: body, segments: segments)
        var top = hemisphere(radius: r, segments: segments, up: true)
        var bottom = hemisphere(radius: r, segments: segments, up: false)
        top.positions = top.positions.map { $0 + SIMD3(0, body / 2, 0) }
        bottom.positions = bottom.positions.map { $0 - SIMD3(0, body / 2, 0) }
        m.append(top)
        m.append(bottom)
        return m
    }

    private static func cylinderSide(radius r: Float, height h: Float, segments: Int) -> MeshData {
        var m = cylinder(radius: r, height: h, segments: segments)
        // Keep only the side (first 2·(segments+1) vertices, 6·segments indices).
        let sideVerts = 2 * (segments + 1)
        m.positions = Array(m.positions.prefix(sideVerts))
        m.normals = Array(m.normals.prefix(sideVerts))
        m.uvs = Array(m.uvs.prefix(sideVerts))
        m.indices = Array(m.indices.prefix(6 * segments))
        return m
    }

    private static func hemisphere(radius r: Float, segments: Int, up: Bool) -> MeshData {
        var m = MeshData()
        let rings = max(4, segments / 4)
        for i in 0...rings {
            let phi = Float(i) / Float(rings) * (.pi / 2)
            for j in 0...segments {
                let theta = Float(j) / Float(segments) * 2 * .pi
                let y = up ? cos(phi) : -cos(phi)
                let n = SIMD3(sin(phi) * cos(theta), y, sin(phi) * sin(theta))
                m.positions.append(n * r)
                m.normals.append(n)
                m.uvs.append(SIMD2(Float(j) / Float(segments), Float(i) / Float(rings)))
            }
        }
        let s = UInt32(segments + 1)
        for i in 0..<UInt32(rings) {
            for j in 0..<UInt32(segments) {
                let a = i * s + j, b = a + s
                m.indices += up ? [a, a + 1, b, a + 1, b + 1, b] : [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        return m
    }

    static func pyramid(base b: Float, height h: Float) -> MeshData {
        var m = MeshData()
        let hb = b / 2
        let apex = SIMD3<Float>(0, h / 2, 0)
        let corners: [SIMD3<Float>] = [SIMD3(-hb, -h / 2, -hb), SIMD3(hb, -h / 2, -hb), SIMD3(hb, -h / 2, hb), SIMD3(-hb, -h / 2, hb)]
        for k in 0..<4 {
            let a = corners[k], c = corners[(k + 1) % 4]
            let n = simdNormalize(simdCross(c - apex, a - apex))
            let base = UInt32(m.positions.count)
            m.positions += [a, c, apex]
            m.normals += [n, n, n]
            m.uvs += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0.5, 1)]
            m.indices += [base, base + 2, base + 1]
        }
        let base = UInt32(m.positions.count)
        let down = SIMD3<Float>(0, -1, 0)
        m.positions += corners
        m.normals += [down, down, down, down]
        m.uvs += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        m.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        return m
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

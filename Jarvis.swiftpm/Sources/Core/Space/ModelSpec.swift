import Foundation

/// Rotation by Euler angles in degrees, applied about z, then x, then y: the same
/// order as the renderer's quaternion (qY · qX · qZ), so geometry computed here
/// matches what RealityKit draws.
struct EulerRotation {
    private let row0: SIMD3<Float>
    private let row1: SIMD3<Float>
    private let row2: SIMD3<Float>

    init(degrees d: SIMD3<Float>) {
        let a = d * (Float.pi / 180)
        let (sx, cx) = (sin(a.x), cos(a.x))
        let (sy, cy) = (sin(a.y), cos(a.y))
        let (sz, cz) = (sin(a.z), cos(a.z))
        let rx = Mat3(SIMD3(1, 0, 0), SIMD3(0, cx, -sx), SIMD3(0, sx, cx))
        let ry = Mat3(SIMD3(cy, 0, sy), SIMD3(0, 1, 0), SIMD3(-sy, 0, cy))
        let rz = Mat3(SIMD3(cz, -sz, 0), SIMD3(sz, cz, 0), SIMD3(0, 0, 1))
        let m = ry * rx * rz
        row0 = m.row0
        row1 = m.row1
        row2 = m.row2
    }

    func apply(_ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(simdDot(row0, v), simdDot(row1, v), simdDot(row2, v))
    }

    private struct Mat3 {
        let row0: SIMD3<Float>, row1: SIMD3<Float>, row2: SIMD3<Float>
        init(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) { row0 = a; row1 = b; row2 = c }
        static func * (l: Mat3, r: Mat3) -> Mat3 {
            let c0 = SIMD3(r.row0.x, r.row1.x, r.row2.x)
            let c1 = SIMD3(r.row0.y, r.row1.y, r.row2.y)
            let c2 = SIMD3(r.row0.z, r.row1.z, r.row2.z)
            func row(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(simdDot(v, c0), simdDot(v, c1), simdDot(v, c2)) }
            return Mat3(row(l.row0), row(l.row1), row(l.row2))
        }
    }
}

/// A composite 3D model made of primitive parts: designed from the user's request by
/// the parametric design library or by the language model with guided generation.
struct ModelSpec: Equatable {
    struct Part: Equatable {
        /// What the part is ("body", "wheel", "window", …); used for detail checks and edits.
        var name: String
        var shape: String
        /// Centre in metres; y = 0 is the floor, the model's front faces +z.
        var position: SIMD3<Float>
        /// Full extents before rotation (width x, height y, depth z), metres.
        var size: SIMD3<Float>
        /// Euler angles in degrees (applied z, x, then y).
        var rotation: SIMD3<Float>
        var color: String
        var material: String
        /// Shape-specific detail (see `MeshGenerator.mesh(for:size:param:segments:)`); 0 = default.
        var param: Float

        init(name: String = "", shape: String, position: SIMD3<Float>, size: SIMD3<Float>, rotation: SIMD3<Float> = .zero,
             color: String, material: String = "plastic", param: Float = 0) {
            self.name = name
            self.shape = shape
            self.position = position
            self.size = size
            self.rotation = rotation
            self.color = color
            self.material = material
            self.param = param
        }

        /// Legacy form: rotation about the vertical axis only.
        init(shape: String, position: SIMD3<Float>, size: SIMD3<Float>, rotationY: Float, color: String) {
            self.init(name: shape, shape: shape, position: position, size: size, rotation: SIMD3(0, rotationY, 0), color: color)
        }

        /// World-space axis-aligned bounds of the part's (rotated) box.
        var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
            let h = size / 2
            let rotation = EulerRotation(degrees: self.rotation)
            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            for sx in [Float(-1), 1] {
                for sy in [Float(-1), 1] {
                    for sz in [Float(-1), 1] {
                        let p = rotation.apply(SIMD3(sx * h.x, sy * h.y, sz * h.z)) + position
                        lo = SIMD3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
                        hi = SIMD3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
                    }
                }
            }
            return (lo, hi)
        }

        /// The same part reflected to the other side (x → -x).
        func mirroredX() -> Part {
            var p = self
            p.position.x = -position.x
            p.rotation = SIMD3(rotation.x, -rotation.y, -rotation.z)
            return p
        }

        /// The part turned about the vertical axis through the origin.
        func rotatedAboutY(_ degrees: Float) -> Part {
            var p = self
            p.position = EulerRotation(degrees: SIMD3(0, degrees, 0)).apply(position)
            p.rotation.y += degrees
            return p
        }

        /// Matches a component name ("wheel" matches "wheel", "front wheel", "wheel_fl", "wheels").
        func isComponent(_ component: String) -> Bool {
            DesignVocabulary.nameMatches(name, component: component)
        }
    }

    var name: String
    var parts: [Part]

    static var supportedShapes: Set<String> { Set(MeshGenerator.shapes) }
    static let materials: [String] = ["plastic", "paint", "metal", "chrome", "glass", "rubber", "wood", "stone", "fabric", "emissive"]

    private static let shapeAliases: [String: String] = [
        "cube": "cube", "box": "cube", "cuboid": "cube", "block": "cube", "rectangle": "cube", "slab": "cube", "board": "cube", "brick": "cube",
        "roundedcube": "roundedCube", "roundedbox": "roundedCube", "roundbox": "roundedCube", "roundcube": "roundedCube",
        "bevelbox": "roundedCube", "bevelledbox": "roundedCube", "beveledbox": "roundedCube", "softbox": "roundedCube",
        "sphere": "sphere", "ball": "sphere", "ellipsoid": "sphere", "orb": "sphere", "globe": "sphere",
        "hemisphere": "hemisphere", "dome": "hemisphere", "halfsphere": "hemisphere", "semisphere": "hemisphere",
        "cylinder": "cylinder", "disc": "cylinder", "disk": "cylinder", "rod": "cylinder", "pillar": "cylinder", "column": "cylinder",
        "halfcylinder": "halfCylinder", "semicylinder": "halfCylinder", "arch": "halfCylinder", "vault": "halfCylinder",
        "tube": "tube", "pipe": "tube", "hollowcylinder": "tube",
        "cone": "cone",
        "frustum": "frustum", "truncatedcone": "frustum", "taperedcylinder": "frustum", "lampshade": "frustum",
        "torus": "torus", "ring": "torus", "donut": "torus", "doughnut": "torus", "hoop": "torus",
        "capsule": "capsule", "pill": "capsule",
        "pyramid": "pyramid", "squarepyramid": "pyramid",
        "wedge": "wedge", "ramp": "wedge", "triangularprism": "wedge", "slope": "wedge",
        "prism": "prism", "hexprism": "prism", "hexagonalprism": "prism", "hexagon": "prism", "octagon": "prism",
        "plane": "plane", "panel": "plane", "plate": "plane", "sheet": "plane", "flat": "plane",
        "cup": "cup", "mug": "cup", "pot": "cup", "bucket": "cup",
        "bowl": "bowl", "dish": "bowl",
        "bottle": "bottle",
        "vase": "vase", "urn": "vase",
        "ogive": "ogive", "nosecone": "ogive", "nose": "ogive", "bullet": "ogive",
    ]

    private static let materialAliases: [String: String] = [
        "plastic": "plastic", "matte": "plastic", "ceramic": "plastic", "porcelain": "plastic",
        "paint": "paint", "painted": "paint", "glossy": "paint", "gloss": "paint", "lacquer": "paint", "carpaint": "paint",
        "metal": "metal", "metallic": "metal", "steel": "metal", "iron": "metal", "aluminium": "metal", "aluminum": "metal", "copper": "metal", "brass": "metal", "bronze": "metal", "gold": "metal",
        "chrome": "chrome", "chromium": "chrome", "mirror": "chrome", "silver": "chrome", "polished": "chrome",
        "glass": "glass", "transparent": "glass", "crystal": "glass", "window": "glass", "ice": "glass",
        "rubber": "rubber", "tire": "rubber", "tyre": "rubber",
        "wood": "wood", "wooden": "wood", "timber": "wood", "oak": "wood", "bamboo": "wood",
        "stone": "stone", "rock": "stone", "concrete": "stone", "marble": "stone", "granite": "stone",
        "fabric": "fabric", "cloth": "fabric", "cushion": "fabric", "leather": "fabric", "textile": "fabric", "velvet": "fabric", "wool": "fabric",
        "emissive": "emissive", "glow": "emissive", "glowing": "emissive", "neon": "emissive", "light": "emissive", "led": "emissive", "luminous": "emissive",
    ]

    private static func key(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter }
    }

    static func canonicalShape(_ raw: String) -> String {
        shapeAliases[key(raw)] ?? "cube"
    }

    static func canonicalMaterial(_ raw: String) -> String {
        materialAliases[key(raw)] ?? "plastic"
    }

    /// Clamp to sane values, canonical shape and material names, no NaNs.
    func sanitized(maxParts: Int = 96) -> ModelSpec {
        var out = self
        out.parts = parts.prefix(maxParts).compactMap { p -> Part? in
            let finite = [p.position.x, p.position.y, p.position.z, p.size.x, p.size.y, p.size.z, p.rotation.x, p.rotation.y, p.rotation.z]
                .allSatisfy { $0.isFinite }
            guard finite else { return nil }
            var q = p
            q.shape = Self.canonicalShape(p.shape)
            q.material = Self.canonicalMaterial(p.material)
            q.size = SIMD3(Swift.min(Swift.max(abs(p.size.x), 0.004), 12), Swift.min(Swift.max(abs(p.size.y), 0.004), 12),
                           Swift.min(Swift.max(abs(p.size.z), 0.004), 12))
            if q.shape == "plane" { q.size.y = Swift.min(Swift.max(q.size.y, 0.004), 0.02) }
            q.position = SIMD3(Swift.min(Swift.max(p.position.x, -12), 12), Swift.min(Swift.max(p.position.y, -2), 20),
                               Swift.min(Swift.max(p.position.z, -12), 12))
            q.rotation = SIMD3(p.rotation.x.truncatingRemainder(dividingBy: 360), p.rotation.y.truncatingRemainder(dividingBy: 360),
                               p.rotation.z.truncatingRemainder(dividingBy: 360))
            if q.color.trimmingCharacters(in: .whitespaces).isEmpty { q.color = "gray" }
            if q.name.trimmingCharacters(in: .whitespaces).isEmpty { q.name = q.shape }
            return q
        }
        return out
    }

    /// Axis-aligned bounds of the whole model.
    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard !parts.isEmpty else { return (.zero, .zero) }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in parts {
            let b = p.bounds
            lo = SIMD3(Swift.min(lo.x, b.min.x), Swift.min(lo.y, b.min.y), Swift.min(lo.z, b.min.z))
            hi = SIMD3(Swift.max(hi.x, b.max.x), Swift.max(hi.y, b.max.y), Swift.max(hi.z, b.max.z))
        }
        return (lo, hi)
    }

    var extent: SIMD3<Float> { let b = bounds; return b.max - b.min }

    func translated(by t: SIMD3<Float>) -> ModelSpec {
        var out = self
        out.parts = parts.map { var p = $0; p.position += t; return p }
        return out
    }

    /// Uniform scale about the origin.
    func scaled(by f: Float) -> ModelSpec {
        var out = self
        out.parts = parts.map { var p = $0; p.position *= f; p.size *= f; return p }
        return out
    }

    /// Standing on the floor (lowest point at y = 0) and centred on the vertical axis.
    func grounded() -> ModelSpec {
        guard !parts.isEmpty else { return self }
        let b = bounds
        return translated(by: SIMD3(-(b.min.x + b.max.x) / 2, -b.min.y, -(b.min.z + b.max.z) / 2))
    }

    /// Parts that represent a component ("wheel" → every wheel).
    func parts(of component: String) -> [Part] {
        parts.filter { $0.isComponent(component) }
    }

    /// Built-in design for a short description (kept for older callers and tests).
    static func template(for description: String) -> ModelSpec {
        DesignLibrary.build(DesignBrief.parse(description)) ?? DesignLibrary.abstractSculpture(DesignBrief.parse(description))
    }
}

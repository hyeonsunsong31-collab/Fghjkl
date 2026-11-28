import Foundation

@inline(__always) func v3(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x, y, z) }

/// Builder toolkit for the parametric design library: adds parts and reads the
/// brief (colours, materials, counts, requested and excluded features).
struct DesignKit {
    let brief: DesignBrief
    private(set) var parts: [ModelSpec.Part] = []
    /// Requested components this design has realised.
    private(set) var handled: Set<String> = []
    /// What the builder read from the brief (so the library can apply the rest generically).
    final class Usage {
        var colored = Set<String>()
        var materials = Set<String>()
        var counts: [String: Int] = [:]
    }
    let usage = Usage()

    init(_ brief: DesignBrief) { self.brief = brief }

    // MARK: Reading the brief

    /// Colour for a component: the user's choice, else the design's default.
    func color(_ component: String, _ fallback: String) -> String {
        usage.colored.insert(component)
        return brief.colors[component] ?? fallback
    }
    /// Overall colour ("a red car" → red), also accepting the body colour.
    func mainColor(_ fallback: String) -> String {
        usage.colored.insert("body")
        return brief.colors["main"] ?? brief.colors["body"] ?? fallback
    }
    /// Second colour ("red and gold", "gold trim").
    func accentColor(_ fallback: String) -> String {
        usage.colored.formUnion(["trim", "stripe"])
        return brief.colors["accent"] ?? brief.colors["trim"] ?? brief.colors["stripe"] ?? fallback
    }
    func material(_ component: String, _ fallback: String) -> String {
        usage.materials.insert(component)
        return brief.materials[component] ?? fallback
    }
    func mainMaterial(_ fallback: String) -> String {
        usage.materials.insert("body")
        return brief.materials["main"] ?? brief.materials["body"] ?? fallback
    }
    func count(_ component: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
        let n = Swift.min(Swift.max(brief.counts[component] ?? fallback, range.lowerBound), range.upperBound)
        usage.counts[component] = n
        return n
    }
    func wants(_ component: String) -> Bool { brief.wants(component) }
    func excludes(_ component: String) -> Bool { brief.excludes(component) }
    /// Include a part unless the user ruled it out.
    func keeps(_ component: String) -> Bool { !brief.excludes(component) }
    func style(_ s: String) -> Bool { brief.hasStyle(s) }
    var variant: String? { brief.variant }
    var futuristic: Bool { style("futuristic") }

    mutating func handle(_ components: String...) { for c in components { handled.insert(c) } }

    // MARK: Adding parts

    mutating func add(_ name: String, _ shape: String, at p: SIMD3<Float>, size s: SIMD3<Float>, rot r: SIMD3<Float> = .zero,
                      color: String, material: String = "plastic", param: Float = 0) {
        parts.append(ModelSpec.Part(name: name, shape: shape, position: p, size: s, rotation: r, color: color, material: material, param: param))
        if DesignVocabulary.components.contains(where: { $0.key == name }) { handled.insert(name) }
    }

    /// A part and its mirror image on the other side (x → -x).
    mutating func pair(_ name: String, _ shape: String, at p: SIMD3<Float>, size s: SIMD3<Float>, rot r: SIMD3<Float> = .zero,
                       color: String, material: String = "plastic", param: Float = 0) {
        add(name, shape, at: p, size: s, rot: r, color: color, material: material, param: param)
        if let last = parts.last { parts.append(last.mirroredX()) }
    }

    /// `count` copies around a vertical axis through `center`, starting from the part at `center + p`.
    mutating func ring(_ name: String, _ shape: String, count: Int, at p: SIMD3<Float>, size s: SIMD3<Float>, rot r: SIMD3<Float> = .zero,
                       color: String, material: String = "plastic", param: Float = 0, phase: Float = 0, center: SIMD3<Float> = .zero) {
        guard count > 0 else { return }
        let base = ModelSpec.Part(name: name, shape: shape, position: p, size: s, rotation: r, color: color, material: material, param: param)
        for k in 0..<count {
            var copy = base.rotatedAboutY(phase + 360 * Float(k) / Float(count))
            copy.position += center
            parts.append(copy)
        }
        if DesignVocabulary.components.contains(where: { $0.key == name }) { handled.insert(name) }
    }

    /// A box joining two points on the floor plan (walls, rails, beams); `a`/`b` give x and z, `y` the centre height.
    mutating func beam(_ name: String, from a: SIMD3<Float>, to b: SIMD3<Float>, y: Float, height h: Float, thickness t: Float,
                       color: String, material: String = "plastic", trim: Float = 0) {
        let d = SIMD3<Float>(b.x - a.x, 0, b.z - a.z)
        let length = simdLength(d) - 2 * trim
        guard length > 0.001 else { return }
        let angle = atan2(-d.z, d.x) * 180 / Float.pi
        let mid = SIMD3<Float>((a.x + b.x) / 2, y, (a.z + b.z) / 2)
        add(name, "cube", at: mid, size: v3(length, h, t), rot: v3(0, angle, 0), color: color, material: material)
    }

    /// A road wheel facing sideways (axle along x): tyre ring, rim and hub.
    mutating func wheel(at p: SIMD3<Float>, diameter d: Float, width w: Float, tire: String, rim: String) {
        add("wheel", "torus", at: p, size: v3(d, w, d), rot: v3(0, 0, 90), color: tire, material: "rubber")
        add("wheel rim", "cylinder", at: p, size: v3(d * 0.64, w * 0.82, d * 0.64), rot: v3(0, 0, 90), color: rim, material: "chrome")
        let side: Float = p.x >= 0 ? 1 : -1
        add("wheel hub", "cylinder", at: p + v3(side * w * 0.42, 0, 0), size: v3(d * 0.2, w * 0.12, d * 0.2), rot: v3(0, 0, 90), color: "darkgray", material: "metal")
    }

    /// Thin glass pane facing +z (front) or -z, or ±x with `sideways`.
    mutating func pane(_ name: String = "window", at p: SIMD3<Float>, width: Float, height: Float, sideways: Bool = false, color c: String) {
        let s: SIMD3<Float> = sideways ? v3(0.006, height, width) : v3(width, height, 0.006)
        add(name, "cube", at: p, size: s, color: c, material: "glass")
    }

    var spec: ModelSpec { ModelSpec(name: "", parts: parts) }
}

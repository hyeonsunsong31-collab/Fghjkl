import Foundation

/// A composite 3D model made of primitive parts (designed by the language
/// model with guided generation, or by built-in procedural templates).
struct ModelSpec: Equatable {
    struct Part: Equatable {
        var shape: String
        var position: SIMD3<Float>
        var size: SIMD3<Float>
        var rotationY: Float
        var color: String
    }

    var name: String
    var parts: [Part]

    static let supportedShapes: Set<String> = ["cube", "sphere", "cylinder", "cone", "torus", "capsule", "pyramid", "plane"]

    /// Clamp to sane values and drop unsupported shapes.
    func sanitized() -> ModelSpec {
        var out = self
        out.parts = parts.prefix(32).compactMap { p in
            var q = p
            q.shape = Self.supportedShapes.contains(p.shape.lowercased()) ? p.shape.lowercased() : "cube"
            q.size = SIMD3(min(max(p.size.x, 0.01), 2), min(max(p.size.y, 0.01), 2), min(max(p.size.z, 0.01), 2))
            q.position = SIMD3(min(max(p.position.x, -2), 2), min(max(p.position.y, -0.5), 3), min(max(p.position.z, -2), 2))
            return q
        }
        return out
    }

    /// Built-in procedural designs (used when no language model is available,
    /// and as reliable results for common requests).
    static func template(for description: String) -> ModelSpec {
        let d = description.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { d.contains($0) } }
        func part(_ s: String, _ p: (Float, Float, Float), _ z: (Float, Float, Float), _ c: String, _ r: Float = 0) -> Part {
            Part(shape: s, position: SIMD3(p.0, p.1, p.2), size: SIMD3(z.0, z.1, z.2), rotationY: r, color: c)
        }
        if has(["helmet", "헬멧", "투구", "mask", "마스크"]) {
            return ModelSpec(name: "Helmet", parts: [
                part("sphere", (0, 0.35, 0), (0.36, 0.4, 0.38), "red"),
                part("cube", (0, 0.36, 0.17), (0.26, 0.1, 0.06), "gold"),
                part("cube", (0, 0.24, 0.17), (0.2, 0.12, 0.05), "gold"),
                part("cube", (-0.07, 0.37, 0.205), (0.08, 0.025, 0.01), "cyan"),
                part("cube", (0.07, 0.37, 0.205), (0.08, 0.025, 0.01), "cyan"),
                part("cylinder", (0, 0.13, 0), (0.22, 0.08, 0.22), "red"),
            ])
        }
        if has(["robot", "로봇", "android", "suit", "슈트", "armor", "armour", "갑옷"]) {
            return ModelSpec(name: "Robot", parts: [
                part("cube", (0, 0.62, 0), (0.3, 0.34, 0.18), "red"),
                part("cylinder", (0, 0.66, 0.095), (0.08, 0.01, 0.08), "cyan"),
                part("cube", (0, 0.9, 0), (0.18, 0.18, 0.16), "gold"),
                part("cube", (-0.04, 0.92, 0.082), (0.05, 0.02, 0.01), "cyan"),
                part("cube", (0.04, 0.92, 0.082), (0.05, 0.02, 0.01), "cyan"),
                part("capsule", (-0.21, 0.6, 0), (0.08, 0.36, 0.08), "red"),
                part("capsule", (0.21, 0.6, 0), (0.08, 0.36, 0.08), "red"),
                part("capsule", (-0.08, 0.22, 0), (0.1, 0.44, 0.1), "gold"),
                part("capsule", (0.08, 0.22, 0), (0.1, 0.44, 0.1), "gold"),
            ])
        }
        if has(["car", "자동차", "차", "vehicle"]) {
            return ModelSpec(name: "Car", parts: [
                part("cube", (0, 0.16, 0), (0.7, 0.14, 0.32), "blue"),
                part("cube", (-0.04, 0.28, 0), (0.38, 0.12, 0.28), "cyan"),
                part("cylinder", (-0.22, 0.08, 0.17), (0.14, 0.05, 0.14), "black", 0),
                part("cylinder", (0.22, 0.08, 0.17), (0.14, 0.05, 0.14), "black", 0),
                part("cylinder", (-0.22, 0.08, -0.17), (0.14, 0.05, 0.14), "black", 0),
                part("cylinder", (0.22, 0.08, -0.17), (0.14, 0.05, 0.14), "black", 0),
            ])
        }
        if has(["house", "집", "home", "building", "건물"]) {
            return ModelSpec(name: "House", parts: [
                part("cube", (0, 0.2, 0), (0.5, 0.4, 0.4), "white"),
                part("pyramid", (0, 0.52, 0), (0.6, 0.24, 0.5), "red"),
                part("cube", (0, 0.1, 0.201), (0.1, 0.2, 0.01), "gold"),
                part("cube", (-0.15, 0.26, 0.201), (0.08, 0.08, 0.01), "cyan"),
                part("cube", (0.15, 0.26, 0.201), (0.08, 0.08, 0.01), "cyan"),
            ])
        }
        if has(["tree", "나무", "forest"]) {
            return ModelSpec(name: "Tree", parts: [
                part("cylinder", (0, 0.15, 0), (0.07, 0.3, 0.07), "orange"),
                part("cone", (0, 0.4, 0), (0.4, 0.3, 0.4), "green"),
                part("cone", (0, 0.58, 0), (0.3, 0.24, 0.3), "green"),
                part("cone", (0, 0.72, 0), (0.2, 0.18, 0.2), "green"),
            ])
        }
        if has(["rocket", "로켓", "spaceship", "우주선"]) {
            return ModelSpec(name: "Rocket", parts: [
                part("cylinder", (0, 0.45, 0), (0.16, 0.6, 0.16), "white"),
                part("cone", (0, 0.85, 0), (0.16, 0.2, 0.16), "red"),
                part("cylinder", (0, 0.55, 0.075), (0.06, 0.01, 0.06), "cyan"),
                part("pyramid", (-0.11, 0.2, 0), (0.08, 0.16, 0.02), "red"),
                part("pyramid", (0.11, 0.2, 0), (0.08, 0.16, 0.02), "red"),
                part("cone", (0, 0.1, 0), (0.12, 0.1, 0.12), "gray"),
            ])
        }
        if has(["snowman", "눈사람"]) {
            return ModelSpec(name: "Snowman", parts: [
                part("sphere", (0, 0.18, 0), (0.36, 0.36, 0.36), "white"),
                part("sphere", (0, 0.46, 0), (0.26, 0.26, 0.26), "white"),
                part("sphere", (0, 0.66, 0), (0.18, 0.18, 0.18), "white"),
                part("cone", (0, 0.66, 0.11), (0.04, 0.08, 0.04), "orange"),
                part("cylinder", (0, 0.8, 0), (0.16, 0.12, 0.16), "black"),
            ])
        }
        if has(["table", "책상", "테이블", "desk"]) {
            return ModelSpec(name: "Table", parts: [
                part("cube", (0, 0.5, 0), (0.8, 0.04, 0.5), "orange"),
                part("cube", (-0.36, 0.24, -0.21), (0.04, 0.48, 0.04), "orange"),
                part("cube", (0.36, 0.24, -0.21), (0.04, 0.48, 0.04), "orange"),
                part("cube", (-0.36, 0.24, 0.21), (0.04, 0.48, 0.04), "orange"),
                part("cube", (0.36, 0.24, 0.21), (0.04, 0.48, 0.04), "orange"),
            ])
        }
        if has(["chair", "의자"]) {
            return ModelSpec(name: "Chair", parts: [
                part("cube", (0, 0.3, 0), (0.4, 0.04, 0.4), "orange"),
                part("cube", (0, 0.55, -0.18), (0.4, 0.46, 0.04), "orange"),
                part("cube", (-0.17, 0.14, -0.17), (0.04, 0.28, 0.04), "orange"),
                part("cube", (0.17, 0.14, -0.17), (0.04, 0.28, 0.04), "orange"),
                part("cube", (-0.17, 0.14, 0.17), (0.04, 0.28, 0.04), "orange"),
                part("cube", (0.17, 0.14, 0.17), (0.04, 0.28, 0.04), "orange"),
            ])
        }
        if has(["reactor", "리액터", "core", "코어", "engine", "엔진"]) {
            return ModelSpec(name: "Arc core", parts: [
                part("cylinder", (0, 0.3, 0), (0.3, 0.06, 0.3), "gray"),
                part("torus", (0, 0.34, 0), (0.28, 0.06, 0.28), "cyan"),
                part("torus", (0, 0.35, 0), (0.18, 0.04, 0.18), "white"),
                part("sphere", (0, 0.35, 0), (0.08, 0.08, 0.08), "cyan"),
            ])
        }
        // Abstract composition for anything else.
        return ModelSpec(name: description.isEmpty ? "Sculpture" : description.capitalized, parts: [
            part("cylinder", (0, 0.05, 0), (0.4, 0.1, 0.4), "gray"),
            part("torus", (0, 0.35, 0), (0.3, 0.06, 0.3), "cyan"),
            part("sphere", (0, 0.35, 0), (0.16, 0.16, 0.16), "gold"),
            part("cone", (0, 0.6, 0), (0.1, 0.2, 0.1), "cyan"),
        ])
    }
}

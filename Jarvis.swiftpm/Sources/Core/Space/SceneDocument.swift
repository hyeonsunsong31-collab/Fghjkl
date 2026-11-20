import Foundation

/// One object in the 3D project space.
struct SceneObject: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var shape: String
    var name: String
    var color: String
    var position: SIMD3<Float>
    /// Euler angles in degrees (x, y, z).
    var rotation: SIMD3<Float> = .zero
    var scale: SIMD3<Float> = SIMD3(1, 1, 1)
    /// Base size in metres (before scale).
    var size: SIMD3<Float>
    var text: String?
    /// Composite models (designed objects) keep their primitive parts here (positions relative to the object).
    var parts: [SceneObject]?
    var createdAt: Date = Date()

    var isComposite: Bool { !(parts ?? []).isEmpty }

    /// Widest horizontal extent (metres, after scale), used for spacing.
    var footprint: Float { max(size.x * scale.x, size.z * scale.z, 0.1) }
    /// Radius of the floor circle the object occupies.
    var clearance: Float { footprint / 2 }
}

/// The complete, persistable project (the 3D workspace that replaces the wallpaper).
struct SceneDocument: Codable, Equatable {
    var name: String = "Project"
    var objects: [SceneObject] = []
    var selectedID: String?
    var updatedAt: Date = Date()

    var selected: SceneObject? { objects.first { $0.id == selectedID } }

    func index(of id: String) -> Int? { objects.firstIndex { $0.id == id } }

    /// Gap kept between neighbouring objects on the floor.
    static let spacingGap: Float = 0.05

    /// True when a floor circle of radius `clearance` at `p` touches no existing object.
    func isFree(_ p: SIMD3<Float>, clearance: Float, ignoring: Set<String> = []) -> Bool {
        for o in objects where !ignoring.contains(o.id) {
            let dx = p.x - o.position.x, dz = p.z - o.position.z
            let minimum = clearance + o.clearance + Self.spacingGap
            if dx * dx + dz * dz < minimum * minimum { return false }
        }
        return true
    }

    /// Next free spot on the floor: rows across the workspace (front row first), filled
    /// from the centre outwards (centre, right, left, …), spaced so nothing overlaps.
    func nextPosition(for size: SIMD3<Float>) -> SIMD3<Float> {
        let r = max(size.x, size.z, 0.1) / 2
        let pitch = 2 * r + Self.spacingGap * 1.6
        let rowPitch = max(0.3, pitch)
        let slots = max(1, Int((1.0 / pitch).rounded(.down)))
        for row in 0..<16 {
            let z = -0.1 - Float(row) * rowPitch
            for k in 0...(slots * 2) {
                let index = Float((k + 1) / 2) * (k % 2 == 0 ? -1 : 1) // 0, +1, -1, +2, -2 …
                let p = SIMD3(index * pitch, size.y / 2, z)
                if isFree(p, clearance: r) { return p }
            }
        }
        return SIMD3(0, size.y / 2, -0.1 - 16 * rowPitch - 0.3 * Float(objects.count))
    }

    /// Nearest free spot to `origin`, trying the preferred direction first, then right,
    /// left, behind and in front, at growing multiples of `step`.
    func freeSpot(near origin: SIMD3<Float>, clearance: Float, step: Float, preferred: SIMD3<Float>? = nil) -> SIMD3<Float> {
        var directions: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, 0, 1)]
        if let d = preferred, d.x * d.x + d.z * d.z > 1e-6 {
            let n = (d.x * d.x + d.z * d.z).squareRoot()
            directions.insert(SIMD3(d.x / n, 0, d.z / n), at: 0)
        }
        for multiple in 1...16 {
            for d in directions {
                let p = origin + d * step * Float(multiple)
                if isFree(p, clearance: clearance) { return p }
            }
        }
        return origin + SIMD3(step * 17, 0, 0)
    }

    // MARK: Mutations

    @discardableResult
    mutating func add(shape: String, color: String, size: SIMD3<Float>, text: String? = nil, name: String? = nil) -> SceneObject {
        let obj = SceneObject(shape: shape, name: name ?? shape.capitalized, color: color,
                              position: nextPosition(for: size), size: size, text: text)
        objects.append(obj)
        selectedID = obj.id
        updatedAt = Date()
        return obj
    }

    @discardableResult
    mutating func addComposite(_ spec: ModelSpec, color override: String? = nil) -> SceneObject {
        let s = spec.sanitized()
        let parts = s.parts.map { p in
            SceneObject(shape: p.shape, name: p.shape, color: override ?? p.color, position: p.position,
                        rotation: SIMD3(0, p.rotationY, 0), size: p.size)
        }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in parts {
            lo = SIMD3(min(lo.x, p.position.x - p.size.x / 2), min(lo.y, p.position.y - p.size.y / 2), min(lo.z, p.position.z - p.size.z / 2))
            hi = SIMD3(max(hi.x, p.position.x + p.size.x / 2), max(hi.y, p.position.y + p.size.y / 2), max(hi.z, p.position.z + p.size.z / 2))
        }
        let extent = parts.isEmpty ? SIMD3<Float>(0.3, 0.3, 0.3) : hi - lo
        var obj = SceneObject(shape: "group", name: s.name, color: override ?? "cyan", position: .zero, size: extent, parts: parts)
        let spot = nextPosition(for: extent)
        obj.position = SIMD3(spot.x, 0, spot.z)
        objects.append(obj)
        selectedID = obj.id
        updatedAt = Date()
        return obj
    }

    /// Duplicate objects `count` times, each placed in the nearest free spot beside the previous copy.
    mutating func clone(_ ids: [String], count: Int) -> [SceneObject] {
        var created: [SceneObject] = []
        for id in ids {
            guard let original = objects.first(where: { $0.id == id }) else { continue }
            var previous = original
            for _ in 0..<max(1, min(count, 50)) {
                var copy = previous
                copy.id = UUID().uuidString
                copy.createdAt = Date()
                // Keep going in the direction of the previous copy; never overlap anything.
                let heading = previous.id == original.id ? nil : previous.position - original.position
                copy.position = freeSpot(near: previous.position, clearance: previous.clearance,
                                         step: previous.footprint + Self.spacingGap * 1.6, preferred: heading)
                copy.parts = copy.parts?.map { var p = $0; p.id = UUID().uuidString; return p }
                objects.append(copy)
                created.append(copy)
                previous = copy
            }
        }
        if let last = created.last { selectedID = last.id }
        updatedAt = Date()
        return created
    }

    mutating func delete(_ ids: [String]) {
        objects.removeAll { ids.contains($0.id) }
        if let s = selectedID, ids.contains(s) { selectedID = objects.last?.id }
        updatedAt = Date()
    }

    mutating func update(_ id: String, _ change: (inout SceneObject) -> Void) {
        guard let i = index(of: id) else { return }
        change(&objects[i])
        updatedAt = Date()
    }

    mutating func clear() {
        objects.removeAll()
        selectedID = nil
        updatedAt = Date()
    }

    // MARK: Reference resolution ("it", "the red cube", "the second sphere", "all cubes")

    func resolve(_ params: [String: String]) -> [String] {
        var candidates = objects
        if let shape = params["targetShape"] {
            candidates = candidates.filter { $0.shape == shape || ($0.parts?.contains { $0.shape == shape } ?? false) && $0.shape == "group" }
        }
        if let color = params["targetColor"] { candidates = candidates.filter { $0.color == color } }
        let hasDescriptor = params["targetShape"] != nil || params["targetColor"] != nil
        if params["scope"] == "all" { return candidates.map(\.id) }
        if let ordinal = params["ordinal"] {
            let pool = hasDescriptor ? candidates : objects
            if ordinal == "last" { return pool.last.map { [$0.id] } ?? [] }
            if let n = Int(ordinal), n >= 1, n <= pool.count { return [pool[n - 1].id] }
            return []
        }
        if hasDescriptor {
            // Prefer the selected object if it matches, otherwise the most recent match.
            if let sel = selectedID, candidates.contains(where: { $0.id == sel }) { return [sel] }
            return candidates.last.map { [$0.id] } ?? []
        }
        if let sel = selectedID, objects.contains(where: { $0.id == sel }) { return [sel] }
        return objects.last.map { [$0.id] } ?? []
    }

    /// Short textual description of the scene for the language model's context.
    func summary(limit: Int = 12) -> String {
        guard !objects.isEmpty else { return "The 3D workspace is empty." }
        let items = objects.suffix(limit).enumerated().map { (i, o) -> String in
            let sel = o.id == selectedID ? " (selected)" : ""
            return "\(i + 1). \(o.color) \(o.shape == "group" ? o.name : o.shape)\(sel)"
        }
        return "3D workspace objects: " + items.joined(separator: "; ")
    }
}

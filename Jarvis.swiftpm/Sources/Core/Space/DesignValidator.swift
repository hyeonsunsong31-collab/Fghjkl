import Foundation

/// Final quality pass for every design (library or language model): clean geometry,
/// nothing floating, exact compliance with the request where it can be enforced
/// (colours, excluded parts, part sizes, overall size), standing on the floor.
enum DesignValidator {
    /// Words that mark a sub-part (a wheel's rim is not another wheel).
    static let subpartWords: Set<String> = ["rim", "hub", "cap", "frame", "post", "tip", "mount", "arch", "trim", "knob", "pole", "strut",
                                            "intake", "glow", "band", "stand", "holder", "bracket", "joint", "pylon", "cover", "lens", "rail"]

    /// Parts that count as one `component` each (sub-parts excluded).
    static func countParts(_ spec: ModelSpec, _ component: String) -> Int {
        spec.parts.filter { p in
            p.isComponent(component) && DesignVocabulary.nameTokens(p.name).allSatisfy { !subpartWords.contains($0) }
        }.count
    }

    /// What the design still gets wrong (for a retry by the language model).
    static func compliance(_ spec: ModelSpec, brief: DesignBrief) -> [String] {
        var issues: [String] = []
        if spec.parts.count < 3 { issues.append("too few parts (\(spec.parts.count)); build a recognisable model with 15 to 40 parts") }
        for feature in brief.features where !DesignLibrary.generic.contains(feature) {
            if spec.parts(of: feature).isEmpty { issues.append("missing \(feature) (name the part \"\(feature)\")") }
        }
        for (component, n) in brief.counts.sorted(by: { $0.key < $1.key }) where component != "floor" {
            let have = countParts(spec, component)
            if have != n && have > 0 { issues.append("needs exactly \(n) \(component) parts, has \(have)") }
        }
        for gone in brief.excluded where !spec.parts(of: gone).isEmpty {
            issues.append("must not have any \(gone)")
        }
        return issues
    }

    /// Clean up and enforce the request. Language-model designs also get their named parts
    /// recoloured as requested and floating parts snapped on (library designs handle both themselves).
    static func finish(_ input: ModelSpec, brief: DesignBrief, fromLanguageModel connect: Bool) -> ModelSpec {
        var spec = input.sanitized()
        spec.parts = dedupe(spec.parts)
        // Excluded components never appear.
        if !brief.excluded.isEmpty {
            let kept = spec.parts.filter { p in !brief.excluded.contains { p.isComponent($0) } }
            if !kept.isEmpty { spec.parts = kept }
        }
        // Requested colours and materials of named parts.
        if connect {
            for (component, color) in brief.colors where component != "main" && component != "accent" {
                for i in spec.parts.indices where spec.parts[i].isComponent(component) { spec.parts[i].color = color }
            }
            for (component, material) in brief.materials where component != "main" {
                for i in spec.parts.indices where spec.parts[i].isComponent(component) { spec.parts[i].material = material }
            }
        }
        if connect, let main = brief.colors["main"], !spec.parts.contains(where: { $0.color == main }) {
            // The language model ignored the overall colour: paint the body (or the largest part).
            let target = spec.parts.indices.first { spec.parts[$0].isComponent("body") }
                ?? spec.parts.indices.max { volume(spec.parts[$0]) < volume(spec.parts[$1]) }
            if let t = target { spec.parts[t].color = main }
        }
        // Part sizes ("bigger wheels"), scaled about each part's own centre.
        for (component, factor) in brief.scales where factor != 1 {
            for i in spec.parts.indices where spec.parts[i].isComponent(component) { spec.parts[i].size *= factor }
        }
        if connect { spec = connected(spec) }
        spec = fitted(spec, brief: brief, normalise: connect)
        return spec.grounded()
    }

    // MARK: Geometry

    static func volume(_ p: ModelSpec.Part) -> Float { p.size.x * p.size.y * p.size.z }

    /// Drop exact duplicates (same shape, place and size) that language models sometimes repeat.
    static func dedupe(_ parts: [ModelSpec.Part]) -> [ModelSpec.Part] {
        var out: [ModelSpec.Part] = []
        for p in parts {
            let duplicate = out.contains { q in
                q.shape == p.shape && simdLength(q.position - p.position) < 0.002 && simdLength(q.size - p.size) < 0.002 && simdLength(q.rotation - p.rotation) < 0.5
            }
            if !duplicate { out.append(p) }
        }
        return out
    }

    /// Requested dimensions win; otherwise "big"/"tiny"; language-model designs are also kept to a sensible size.
    static func fitted(_ spec: ModelSpec, brief: DesignBrief, normalise: Bool) -> ModelSpec {
        guard !spec.parts.isEmpty else { return spec }
        let e = spec.extent
        var factor: Float = 1
        if let h = brief.height, e.y > 0 {
            factor = h / e.y
        } else if let l = brief.length, Swift.max(e.x, e.z) > 0 {
            factor = l / Swift.max(e.x, e.z)
        } else if let w = brief.width, Swift.min(e.x, e.z) > 0 {
            factor = w / Swift.min(e.x, e.z)
        } else if let o = brief.overall, Swift.max(e.x, e.y, e.z) > 0 {
            factor = o / Swift.max(e.x, e.y, e.z)
        } else {
            factor = brief.sizeFactor
            let largest = Swift.max(e.x, e.y, e.z) * factor
            if normalise && (largest > 3 || largest < 0.15) { factor *= 0.9 / Swift.max(largest, 0.001) }
        }
        let largest = Swift.max(e.x, e.y, e.z) * factor
        if largest > 30 { factor *= 30 / largest }
        if largest < 0.03 { factor *= 0.03 / Swift.max(largest, 1e-4) }
        return abs(factor - 1) < 0.001 ? spec : spec.scaled(by: factor)
    }

    /// Snap floating groups of parts onto the main body so nothing hangs in the air.
    static func connected(_ input: ModelSpec) -> ModelSpec {
        var spec = input
        let n = spec.parts.count
        guard n > 1 else { return spec }
        let size = Swift.max(spec.extent.x, spec.extent.y, spec.extent.z)
        let tolerance = Swift.max(0.004, size * 0.012)
        for _ in 0..<4 {
            let boxes = spec.parts.map { $0.bounds }
            var parent = Array(0..<n)
            func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
            for i in 0..<n {
                for j in (i + 1)..<n where gap(boxes[i], boxes[j]) <= tolerance {
                    parent[find(i)] = find(j)
                }
            }
            var groups: [Int: [Int]] = [:]
            for i in 0..<n { groups[find(i), default: []].append(i) }
            guard groups.count > 1 else { break }
            // Fixed: the heaviest group, plus every group standing on the same floor (a castle's
            // towers around its keep, a keyboard beside a monitor). Everything else is floating.
            func weight(_ members: [Int]) -> Float { members.reduce(0) { $0 + volume(spec.parts[$1]) } }
            let mainRoot = groups.max { weight($0.value) < weight($1.value) }?.key ?? find(0)
            let floorY = (groups[mainRoot] ?? []).map { boxes[$0].min.y }.min() ?? 0
            var fixedRoots: Set<Int> = [mainRoot]
            for (root, members) in groups where members.contains(where: { boxes[$0].min.y <= floorY + tolerance }) { fixedRoots.insert(root) }
            let main = groups.filter { fixedRoots.contains($0.key) }.flatMap { $0.value }
            var movedAny = false
            for (root, members) in groups where !fixedRoots.contains(root) {
                movedAny = true
                // Smallest move that brings this group into contact with the main group.
                var best: SIMD3<Float>?
                for a in members {
                    for b in main {
                        let t = contactMove(boxes[a], toward: boxes[b], overlap: tolerance * 0.5)
                        if best == nil || simdLength(t) < simdLength(best!) { best = t }
                    }
                }
                if let t = best { for i in members { spec.parts[i].position += t } }
            }
            if !movedAny { break }
        }
        return spec
    }

    /// Distance between two boxes (0 when they touch or overlap).
    static func gap(_ a: (min: SIMD3<Float>, max: SIMD3<Float>), _ b: (min: SIMD3<Float>, max: SIMD3<Float>)) -> Float {
        let dx = Swift.max(0, Swift.max(b.min.x - a.max.x, a.min.x - b.max.x))
        let dy = Swift.max(0, Swift.max(b.min.y - a.max.y, a.min.y - b.max.y))
        let dz = Swift.max(0, Swift.max(b.min.z - a.max.z, a.min.z - b.max.z))
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// Translation of box `a` that makes it just overlap box `b`.
    static func contactMove(_ a: (min: SIMD3<Float>, max: SIMD3<Float>), toward b: (min: SIMD3<Float>, max: SIMD3<Float>), overlap: Float) -> SIMD3<Float> {
        func axis(_ aMin: Float, _ aMax: Float, _ bMin: Float, _ bMax: Float) -> Float {
            if aMax < bMin { return bMin - aMax + overlap }
            if aMin > bMax { return bMax - aMin - overlap }
            return 0
        }
        return SIMD3(axis(a.min.x, a.max.x, b.min.x, b.max.x), axis(a.min.y, a.max.y, b.min.y, b.max.y), axis(a.min.z, a.max.z, b.min.z, b.max.z))
    }
}

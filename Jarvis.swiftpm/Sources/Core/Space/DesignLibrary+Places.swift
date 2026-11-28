import Foundation

/// Buildings, structures and plants.
extension DesignLibrary {
    // MARK: - Buildings

    static func house(_ k: inout DesignKit) -> String {
        let cottage = k.variant == "cottage", mansion = k.variant == "mansion"
        let modern = k.style("modern") || k.style("futuristic")
        let floors = k.count("floor", mansion ? 2 : 1, 1...6)
        let W: Float = mansion ? 0.95 : 0.72, D: Float = mansion ? 0.62 : 0.56
        let floorH: Float = 0.28
        let base: Float = 0.04
        let H = Float(floors) * floorH
        let top = base + H
        let wallColor = k.color("wall", k.mainColor(cottage ? "brown" : (mansion ? "white" : "beige")))
        let wallMat = k.material("wall", k.mainMaterial(cottage ? "wood" : (k.style("medieval") ? "stone" : "plastic")))
        let trim = k.accentColor("white")
        k.add("base", "cube", at: v3(0, base / 2, 0), size: v3(W + 0.04, base, D + 0.04), color: "gray", material: "stone")
        k.add("wall", "cube", at: v3(0, base + H / 2, 0), size: v3(W, H, D), color: wallColor, material: wallMat)
        for f in 1..<floors {
            k.add("trim", "cube", at: v3(0, base + Float(f) * floorH, 0), size: v3(W + 0.012, 0.016, D + 0.012), color: trim, material: "plastic")
        }

        // Roof: gable by default, flat for modern houses.
        var roofTop = top
        if k.keeps("roof") {
            let roofColor = k.color("roof", cottage ? "brown" : (mansion ? "darkgray" : "red"))
            if modern {
                k.add("roof", "cube", at: v3(0, top + 0.02, 0), size: v3(W + 0.06, 0.04, D + 0.06), color: k.color("roof", "darkgray"), material: "stone")
                roofTop = top + 0.04
            } else {
                let roofH: Float = cottage ? 0.34 : 0.25
                let half = D / 2 + 0.05
                k.add("roof", "wedge", at: v3(0, top + roofH / 2, half / 2), size: v3(W + 0.1, roofH, half), color: roofColor, material: k.material("roof", "plastic"))
                k.add("roof", "wedge", at: v3(0, top + roofH / 2, -half / 2), size: v3(W + 0.1, roofH, half), rot: v3(0, 180, 0), color: roofColor,
                      material: k.material("roof", "plastic"))
                roofTop = top + roofH
            }
        }

        // Door, windows, chimney and extras.
        let garage = k.wants("garage")
        let doorX: Float = garage ? -W * 0.22 : 0
        let doorColor = k.color("door", "brown")
        k.add("door frame", "cube", at: v3(doorX, base + 0.115, D / 2 + 0.004), size: v3(0.15, 0.23, 0.008), color: trim, material: "plastic")
        k.add("door", "cube", at: v3(doorX, base + 0.11, D / 2 + 0.009), size: v3(0.125, 0.215, 0.01), color: doorColor, material: "wood")
        k.add("door knob", "sphere", at: v3(doorX + 0.04, base + 0.1, D / 2 + 0.017), size: v3(0.016, 0.016, 0.016), color: "gold", material: "metal")
        let glass = k.color("window", "cyan")
        let requested = k.brief.counts["window"]
        let perFloor = requested.map { Swift.max(1, ($0 + floors - 1) / floors) } ?? (floors == 1 ? 2 : 3)
        for f in 0..<floors {
            let y = base + Float(f) * floorH + floorH * 0.58
            for i in 0..<perFloor {
                var x = -W / 2 + W * (Float(i) + 0.5) / Float(perFloor)
                if f == 0 && abs(x - doorX) < 0.13 { x += x >= doorX ? 0.12 : -0.12 }
                guard abs(x) < W / 2 - 0.07 else { continue }
                k.add("window frame", "cube", at: v3(x, y, D / 2 + 0.004), size: v3(0.145, 0.145, 0.008), color: trim, material: "plastic")
                k.pane(at: v3(x, y, D / 2 + 0.009), width: 0.12, height: 0.12, color: glass)
            }
            k.pair("window frame", "cube", at: v3(W / 2 + 0.004, y, 0), size: v3(0.008, 0.145, 0.145), color: trim, material: "plastic")
            k.pair("window", "cube", at: v3(W / 2 + 0.009, y, 0), size: v3(0.006, 0.12, 0.12), color: glass, material: "glass")
        }
        if k.wants("chimney") || (cottage && k.keeps("chimney")) {
            let c = k.color("chimney", "maroon")
            k.add("chimney", "cube", at: v3(W * 0.28, top + (roofTop - top) * 0.55 + 0.04, -D * 0.18), size: v3(0.09, (roofTop - top) * 0.8 + 0.12, 0.09),
                  color: c, material: "stone")
            k.add("chimney cap", "cube", at: v3(W * 0.28, top + (roofTop - top) * 0.95 + 0.105, -D * 0.18), size: v3(0.11, 0.02, 0.11), color: "darkgray", material: "stone")
        }
        if garage {
            let gx = W / 2 + 0.19
            k.add("garage", "cube", at: v3(gx, base + 0.14, 0.02), size: v3(0.36, 0.28, D * 0.9), color: wallColor, material: wallMat)
            k.add("garage roof", "cube", at: v3(gx, base + 0.29, 0.02), size: v3(0.4, 0.025, D * 0.94), color: k.color("roof", "darkgray"), material: "stone")
            k.add("garage door", "cube", at: v3(gx, base + 0.11, D * 0.47 + 0.02), size: v3(0.28, 0.2, 0.01), color: k.color("garage", "gray"), material: "metal")
        }
        if k.wants("stairs") || mansion {
            k.add("stairs", "cube", at: v3(doorX, 0.015, D / 2 + 0.06), size: v3(0.22, 0.03, 0.08), color: "gray", material: "stone")
        }
        if k.wants("balcony") && floors >= 2 {
            k.add("balcony", "cube", at: v3(0, base + floorH, D / 2 + 0.06), size: v3(W * 0.5, 0.02, 0.12), color: trim, material: "stone")
            k.add("balcony rail", "cube", at: v3(0, base + floorH + 0.05, D / 2 + 0.115), size: v3(W * 0.5, 0.08, 0.008), color: trim, material: "metal")
        }
        if k.wants("fence") {
            let fz = D / 2 + 0.28
            let posts = 9
            for i in 0..<posts {
                let x = -W / 2 - 0.1 + (W + 0.2) * Float(i) / Float(posts - 1)
                if abs(x - doorX) < 0.09 { continue }
                k.add("fence", "cube", at: v3(x, 0.07, fz), size: v3(0.02, 0.14, 0.02), color: k.color("fence", "white"), material: "wood")
            }
            k.add("fence rail", "cube", at: v3(-W / 4 - 0.075, 0.1, fz), size: v3(W / 2 + 0.05, 0.015, 0.012), color: k.color("fence", "white"), material: "wood")
            k.add("fence rail", "cube", at: v3(W / 4 + 0.075, 0.1, fz), size: v3(W / 2 + 0.05, 0.015, 0.012), color: k.color("fence", "white"), material: "wood")
        }
        if k.wants("light") {
            k.add("light", "sphere", at: v3(doorX + 0.11, base + 0.19, D / 2 + 0.02), size: v3(0.03, 0.03, 0.03), color: k.color("light", "yellow"), material: "emissive")
        }
        k.handle("floor")
        let story = floors > 1 ? (k.brief.korean ? "\(floors)층 " : "\(floors)-storey ") : ""
        return story + (cottage ? "Cottage" : (mansion ? "Mansion" : "House"))
    }

    static func building(_ k: inout DesignKit) -> String {
        let tall = k.variant == "skyscraper"
        let floors = k.count("floor", tall ? 24 : 8, 2...80)
        let floorH: Float = tall ? 0.045 : 0.06
        let W: Float = tall ? 0.3 : 0.42, D: Float = tall ? 0.28 : 0.36
        let concrete = k.mainColor(tall ? "silver" : "white")
        let glass = k.color("window", tall ? "navy" : "cyan")
        let plinth: Float = 0.03
        k.add("base", "cube", at: v3(0, plinth / 2, 0), size: v3(W + 0.08, plinth, D + 0.08), color: "gray", material: "stone")
        let tiers = tall && floors > 14 ? 2 : 1
        let lowerFloors = tiers == 2 ? Int(Float(floors) * 0.62) : floors
        var y0 = plinth
        var w = W, d = D
        var remaining = floors
        for tier in 0..<tiers {
            let n = tier == 0 ? lowerFloors : remaining
            let h = Float(n) * floorH
            k.add("window", "cube", at: v3(0, y0 + h / 2, 0), size: v3(w - 0.01, h, d - 0.01), color: glass, material: "glass")
            let step = Swift.max(1, n / 24)
            var f = 0
            while f <= n {
                k.add("floor slab", "cube", at: v3(0, y0 + Float(f) * floorH, 0), size: v3(w, 0.008, d), color: concrete, material: "stone")
                f += step
            }
            for sx in [Float(-1), 1] {
                for sz in [Float(-1), 1] {
                    k.add("column", "cube", at: v3(sx * (w / 2 - 0.012), y0 + h / 2, sz * (d / 2 - 0.012)), size: v3(0.024, h, 0.024), color: concrete, material: "stone")
                }
            }
            y0 += h
            remaining -= n
            w *= 0.72
            d *= 0.72
        }
        k.add("roof", "cube", at: v3(0, y0 + 0.015, 0), size: v3(w / 0.72 * 0.6, 0.03, d / 0.72 * 0.6), color: "darkgray", material: "metal")
        if tall || k.wants("antenna") {
            k.add("antenna", "cylinder", at: v3(0, y0 + 0.13, 0), size: v3(0.012, 0.22, 0.012), color: "silver", material: "metal")
            k.add("light", "sphere", at: v3(0, y0 + 0.245, 0), size: v3(0.022, 0.022, 0.022), color: "red", material: "emissive")
        }
        k.add("door", "cube", at: v3(0, plinth + 0.05, D / 2 + 0.006), size: v3(0.12, 0.1, 0.01), color: k.color("door", "black"), material: "glass")
        k.add("canopy", "cube", at: v3(0, plinth + 0.105, D / 2 + 0.04), size: v3(0.18, 0.012, 0.08), color: concrete, material: "stone")
        k.handle("floor", "body")
        return tall ? "Skyscraper" : "\(floors)-floor building"
    }

    static func castle(_ k: inout DesignKit) -> String {
        let stone = k.color("wall", k.mainColor("gray"))
        let roofColor = k.color("roof", "navy")
        let flagColor = k.color("flag", "red")
        let towers = k.count("tower", 4, 1...8)
        let radius: Float = 0.46
        let wallH: Float = 0.24, wallT: Float = 0.05
        let towerR: Float = 0.085, towerH: Float = 0.4
        let phase: Float = towers == 4 ? 45 : 0
        var spots: [SIMD3<Float>] = []
        for i in 0..<towers {
            let a = (phase + 360 * Float(i) / Float(towers)) * Float.pi / 180
            spots.append(v3(radius * sin(a), 0, radius * cos(a)))
        }
        for p in spots {
            k.add("tower", "cylinder", at: v3(p.x, towerH / 2, p.z), size: v3(2 * towerR, towerH, 2 * towerR), color: stone, material: "stone")
            if k.keeps("roof") {
                k.add("roof", "cone", at: v3(p.x, towerH + 0.11, p.z), size: v3(2 * towerR + 0.04, 0.22, 2 * towerR + 0.04), color: roofColor, material: "plastic")
            }
            if k.keeps("flag") {
                let poleTop = towerH + (k.keeps("roof") ? 0.3 : 0.12)
                k.add("flag pole", "cylinder", at: v3(p.x, poleTop - 0.05, p.z), size: v3(0.008, 0.12, 0.008), color: "darkgray", material: "metal")
                k.add("flag", "cube", at: v3(p.x + 0.035, poleTop - 0.025, p.z), size: v3(0.06, 0.04, 0.004), color: flagColor, material: "fabric")
            }
        }
        if towers >= 2 {
            for i in 0..<towers {
                let a = spots[i], b = spots[(i + 1) % towers]
                if towers == 2 && i == 1 { break }
                k.beam("wall", from: a, to: b, y: wallH / 2, height: wallH, thickness: wallT, color: stone, material: "stone", trim: towerR * 0.7)
                let d = b - a
                let len = simdLength(SIMD3(d.x, 0, d.z))
                let merlons = Swift.max(2, Int(len / 0.09))
                for m in 1..<merlons {
                    let t = Float(m) / Float(merlons)
                    let p = a + d * t
                    k.beam("battlement", from: p - d * (0.018 / len), to: p + d * (0.018 / len), y: wallH + 0.02, height: 0.04, thickness: wallT, color: stone, material: "stone")
                }
                // The gate goes in the wall that faces the viewer.
                let mid = (a + b) / 2
                if mid.z > 0 && abs(mid.x) < 0.2 && k.keeps("gate") {
                    let out = simdNormalize(SIMD3(mid.x, 0, mid.z))
                    let angle = atan2(d.x, d.z) * 180 / Float.pi
                    k.add("gate", "halfCylinder", at: v3(mid.x + out.x * (wallT / 2 + 0.004), 0.075, mid.z + out.z * (wallT / 2 + 0.004)),
                          size: v3(0.02, 0.15, 0.12), rot: v3(0, angle, 0), color: k.color("gate", "brown"), material: "wood")
                }
            }
        }
        k.add("keep", "cube", at: v3(0, 0.25, -0.04), size: v3(0.26, 0.5, 0.26), color: stone, material: "stone")
        for sx in [Float(-1), 1] {
            for sz in [Float(-1), 1] {
                k.add("battlement", "cube", at: v3(sx * 0.1, 0.525, -0.04 + sz * 0.1), size: v3(0.05, 0.05, 0.05), color: stone, material: "stone")
            }
        }
        k.pane(at: v3(0, 0.36, 0.091), width: 0.05, height: 0.08, color: "black")
        k.handle("body")
        return "Castle"
    }

    static func tower(_ k: inout DesignKit) -> String {
        if k.variant == "lighthouse" {
            let a = k.mainColor("white"), b = k.accentColor("red")
            k.add("base", "sphere", at: v3(0, 0.04, 0), size: v3(0.5, 0.14, 0.45), color: "gray", material: "stone")
            let segments = 6
            let bottom: Float = 0.32, topD: Float = 0.2, height: Float = 0.84, y0: Float = 0.06
            for i in 0..<segments {
                let t0 = Float(i) / Float(segments), t1 = Float(i + 1) / Float(segments)
                let d0 = bottom + (topD - bottom) * t0, d1 = bottom + (topD - bottom) * t1
                let h = height / Float(segments)
                k.add("body", "frustum", at: v3(0, y0 + h * (Float(i) + 0.5), 0), size: v3(d0, h, d0), color: i % 2 == 0 ? a : b, material: "paint", param: d1 / d0)
            }
            let yTop = y0 + height
            k.add("gallery", "cylinder", at: v3(0, yTop + 0.015, 0), size: v3(0.3, 0.03, 0.3), color: "darkgray", material: "metal")
            k.add("railing", "torus", at: v3(0, yTop + 0.07, 0), size: v3(0.29, 0.012, 0.29), color: "darkgray", material: "metal")
            k.add("lantern", "cylinder", at: v3(0, yTop + 0.1, 0), size: v3(0.16, 0.14, 0.16), color: k.color("window", "cyan"), material: "glass")
            k.add("light", "sphere", at: v3(0, yTop + 0.1, 0), size: v3(0.08, 0.08, 0.08), color: k.color("light", "yellow"), material: "emissive")
            k.add("roof", "hemisphere", at: v3(0, yTop + 0.22, 0), size: v3(0.2, 0.1, 0.2), color: k.color("roof", b), material: "paint")
            k.add("finial", "sphere", at: v3(0, yTop + 0.285, 0), size: v3(0.035, 0.035, 0.035), color: "darkgray", material: "metal")
            k.add("door", "cube", at: v3(0, y0 + 0.07, 0.158), size: v3(0.07, 0.12, 0.012), color: "darkgray", material: "wood")
            k.handle("body")
            return "Lighthouse"
        }
        if k.variant == "clock" {
            let brick = k.mainColor("beige")
            k.add("body", "cube", at: v3(0, 0.45, 0), size: v3(0.26, 0.9, 0.26), color: brick, material: "stone")
            k.add("base", "cube", at: v3(0, 0.04, 0), size: v3(0.32, 0.08, 0.32), color: "gray", material: "stone")
            let face = k.color("clock", "white")
            for (pos, rot) in [(v3(0, 0.72, 0.131), v3(90, 0, 0)), (v3(0, 0.72, -0.131), v3(90, 0, 0)),
                               (v3(0.131, 0.72, 0), v3(0, 0, 90)), (v3(-0.131, 0.72, 0), v3(0, 0, 90))] {
                k.add("clock", "cylinder", at: pos, size: v3(0.18, 0.012, 0.18), rot: rot, color: face, material: "plastic")
            }
            k.add("clock hand", "cube", at: v3(0, 0.75, 0.139), size: v3(0.008, 0.07, 0.004), color: "black", material: "metal")
            k.add("clock hand", "cube", at: v3(0.025, 0.72, 0.139), size: v3(0.05, 0.008, 0.004), color: "black", material: "metal")
            k.add("roof", "pyramid", at: v3(0, 1.03, 0), size: v3(0.32, 0.26, 0.32), color: k.color("roof", "darkgreen"), material: "metal")
            k.add("window", "halfCylinder", at: v3(0, 0.5, 0.132), size: v3(0.01, 0.12, 0.08), rot: v3(0, 90, 0), color: "black", material: "glass")
            k.handle("body")
            return "Clock tower"
        }
        let c = k.mainColor("silver")
        k.add("base", "frustum", at: v3(0, 0.06, 0), size: v3(0.34, 0.12, 0.34), color: c, material: "stone", param: 0.5)
        k.add("body", "frustum", at: v3(0, 0.5, 0), size: v3(0.14, 0.8, 0.14), color: c, material: "stone", param: 0.6)
        k.add("deck", "sphere", at: v3(0, 0.78, 0), size: v3(0.26, 0.12, 0.26), color: k.accentColor("white"), material: "paint")
        k.add("window", "cylinder", at: v3(0, 0.78, 0), size: v3(0.24, 0.035, 0.24), color: k.color("window", "cyan"), material: "glass")
        k.add("spire", "cone", at: v3(0, 1.0, 0), size: v3(0.06, 0.32, 0.06), color: c, material: "metal")
        k.add("light", "sphere", at: v3(0, 1.17, 0), size: v3(0.02, 0.02, 0.02), color: "red", material: "emissive")
        k.handle("body")
        return "Tower"
    }

    static func bridge(_ k: inout DesignKit) -> String {
        let deck = k.mainColor("gray")
        let accent = k.accentColor("red")
        let L: Float = 1.8, w: Float = 0.3, deckY: Float = 0.24
        k.add("body", "cube", at: v3(0, deckY, 0), size: v3(L, 0.04, w), color: deck, material: "stone")
        k.add("road", "plane", at: v3(0, deckY + 0.022, 0), size: v3(L, 0.006, w * 0.8), color: "darkgray", material: "stone")
        for x in [Float(-0.45), 0.45] {
            k.add("tower", "cube", at: v3(x, 0.32, w / 2 + 0.02), size: v3(0.05, 0.64, 0.04), color: accent, material: "paint")
            k.add("tower", "cube", at: v3(x, 0.32, -w / 2 - 0.02), size: v3(0.05, 0.64, 0.04), color: accent, material: "paint")
            k.add("tower beam", "cube", at: v3(x, 0.6, 0), size: v3(0.05, 0.04, w + 0.08), color: accent, material: "paint")
            k.add("pier", "cube", at: v3(x, 0.11, 0), size: v3(0.12, 0.22, w + 0.04), color: "gray", material: "stone")
        }
        for z in [w / 2 + 0.02, -w / 2 - 0.02] {
            k.add("cable", "cylinder", at: v3(0, 0.44, z), size: v3(0.008, 0.92, 0.008), rot: v3(0, 0, 90), color: accent, material: "metal")
            k.add("cable", "cylinder", at: v3(-0.68, 0.42, z), size: v3(0.008, 0.55, 0.008), rot: v3(0, 0, 50), color: accent, material: "metal")
            k.add("cable", "cylinder", at: v3(0.68, 0.42, z), size: v3(0.008, 0.55, 0.008), rot: v3(0, 0, -50), color: accent, material: "metal")
            for i in 1..<6 {
                let x = -0.45 + 0.15 * Float(i)
                k.add("cable", "cylinder", at: v3(x, (0.44 + deckY) / 2, z), size: v3(0.004, 0.44 - deckY, 0.004), color: accent, material: "metal")
            }
        }
        k.handle("body")
        return "Suspension bridge"
    }

    // MARK: - Plants

    static func tree(_ k: inout DesignKit) -> String {
        let request = k.brief.request.lowercased()
        let christmas = request.contains("christmas") || request.contains("크리스마스")
        let trunkColor = k.color("trunk", k.color("stem", "brown"))
        switch k.variant {
        case "pine":
            let green = k.color("leaves", k.mainColor("darkgreen"))
            k.add("trunk", "cylinder", at: v3(0, 0.11, 0), size: v3(0.08, 0.22, 0.08), color: trunkColor, material: "wood")
            let tiers = 4
            for i in 0..<tiers {
                let t = Float(i) / Float(tiers - 1)
                let d = 0.52 - 0.32 * t
                k.add("leaves", "cone", at: v3(0, 0.33 + 0.17 * Float(i), 0), size: v3(d, 0.28, d), color: green, material: "fabric")
            }
            if christmas || k.wants("light") || k.wants("gem") {
                k.add("star", "prism", at: v3(0, 1.04, 0), size: v3(0.15, 0.04, 0.15), rot: v3(90, 0, 0), color: "gold", material: "emissive", param: 5)
                let colors = ["red", "gold", "blue", "white"]
                for i in 0..<10 {
                    let a = Float(i) * 137.5 * Float.pi / 180
                    let h = 0.32 + 0.05 * Float(i)
                    let r = 0.22 - 0.017 * Float(i)
                    k.add("ornament", "sphere", at: v3(r * sin(a), h, r * cos(a)), size: v3(0.035, 0.035, 0.035), color: colors[i % 4], material: "emissive")
                }
                return "Christmas tree"
            }
            k.handle("leaves")
            return "Pine tree"
        case "palm":
            let green = k.color("leaves", k.mainColor("green"))
            var top = v3(0, 0, 0)
            for i in 0..<6 {
                let lean = Float(i) * 2.2
                let seg = v3(sin(lean * Float.pi / 180) * 0.11 * Float(i) * 0.5, 0.07 + 0.13 * Float(i), 0)
                k.add("trunk", "cylinder", at: seg, size: v3(0.065 - 0.003 * Float(i), 0.14, 0.065 - 0.003 * Float(i)), rot: v3(0, 0, -lean),
                      color: trunkColor, material: "wood")
                top = seg + v3(0, 0.07, 0)
            }
            k.ring("leaves", "sphere", count: k.count("leaves", 7, 4...12), at: v3(0, -0.04, 0.2), size: v3(0.07, 0.02, 0.42), rot: v3(22, 0, 0),
                   color: green, material: "fabric", center: top)
            k.ring("fruit", "sphere", count: 3, at: v3(0, -0.06, 0.045), size: v3(0.05, 0.05, 0.05), color: k.color("fruit", "brown"), material: "wood", center: top)
            return "Palm tree"
        default:
            let cherry = k.variant == "cherry"
            let green = k.color("leaves", k.mainColor(cherry ? "pink" : "green"))
            let th: Float = 0.34
            k.add("trunk", "cylinder", at: v3(0, th / 2, 0), size: v3(0.075, th, 0.075), color: trunkColor, material: "wood")
            k.pair("branch", "cylinder", at: v3(0.06, th + 0.02, 0), size: v3(0.03, 0.16, 0.03), rot: v3(0, 0, -35), color: trunkColor, material: "wood")
            let blobs: [(SIMD3<Float>, Float)] = [(v3(0, th + 0.2, 0), 0.42), (v3(0.16, th + 0.12, 0.02), 0.28), (v3(-0.15, th + 0.13, -0.02), 0.28),
                                                  (v3(0.02, th + 0.14, 0.15), 0.27), (v3(-0.02, th + 0.15, -0.15), 0.27), (v3(0.03, th + 0.36, 0.02), 0.26)]
            for (p, d) in blobs {
                k.add("leaves", "sphere", at: p, size: v3(d, d * 0.88, d), color: green, material: "fabric")
            }
            if k.wants("fruit") || k.brief.request.lowercased().contains("apple") || k.brief.request.contains("사과") {
                let fruit = k.color("fruit", "red")
                let spots: [SIMD3<Float>] = [v3(0.2, th + 0.15, 0.12), v3(-0.18, th + 0.2, 0.1), v3(0.05, th + 0.3, 0.19), v3(-0.08, th + 0.08, 0.2),
                                             v3(0.22, th + 0.26, -0.05), v3(-0.21, th + 0.1, -0.1)]
                for p in spots { k.add("fruit", "sphere", at: p, size: v3(0.045, 0.045, 0.045), color: fruit, material: "paint") }
            }
            return cherry ? "Cherry blossom tree" : "Tree"
        }
    }

    static func flower(_ k: inout DesignKit) -> String {
        let variant = k.variant
        let petalColor = k.color("petal", k.mainColor(variant == "sunflower" ? "yellow" : (variant == "rose" ? "red" : (variant == "tulip" ? "pink" : "purple"))))
        var y: Float = 0
        if k.keeps("pot") {
            k.add("pot", "cup", at: v3(0, 0.07, 0), size: v3(0.16, 0.14, 0.16), color: k.color("pot", "orange"), material: "stone")
            k.add("soil", "cylinder", at: v3(0, 0.12, 0), size: v3(0.135, 0.01, 0.135), color: "brown", material: "fabric")
            y = 0.12
        }
        let stemH: Float = variant == "sunflower" ? 0.5 : 0.36
        let green = k.color("stem", k.color("leaves", "green"))
        k.add("stem", "cylinder", at: v3(0, y + stemH / 2, 0), size: v3(0.014, stemH, 0.014), color: green, material: "fabric")
        k.pair("leaves", "sphere", at: v3(0.06, y + stemH * 0.38, 0), size: v3(0.12, 0.014, 0.05), rot: v3(0, 0, 25), color: green, material: "fabric")
        let head = v3(0, y + stemH + 0.03, 0)
        switch variant {
        case "tulip":
            k.ring("petal", "sphere", count: k.count("petal", 6, 3...10), at: v3(0, 0.04, 0.025), size: v3(0.05, 0.11, 0.028), rot: v3(-14, 0, 0),
                   color: petalColor, material: "fabric", center: head)
            return "Tulip"
        case "rose":
            k.add("petal", "sphere", at: head + v3(0, 0.03, 0), size: v3(0.07, 0.08, 0.07), color: petalColor, material: "fabric")
            k.ring("petal", "sphere", count: 5, at: v3(0, 0.025, 0.04), size: v3(0.06, 0.07, 0.03), rot: v3(-25, 0, 0), color: petalColor, material: "fabric", center: head)
            k.ring("petal", "sphere", count: 6, at: v3(0, 0.0, 0.06), size: v3(0.06, 0.05, 0.03), rot: v3(-50, 0, 0), color: petalColor, material: "fabric", phase: 30, center: head)
            k.ring("sepal", "sphere", count: 5, at: v3(0, -0.035, 0.035), size: v3(0.025, 0.012, 0.06), rot: v3(30, 0, 0), color: green, material: "fabric", center: head)
            return "Rose"
        default:
            let sunflower = variant == "sunflower"
            let n = k.count("petal", sunflower ? 18 : 8, 3...30)
            let radius: Float = sunflower ? 0.1 : 0.055
            let length: Float = sunflower ? 0.085 : 0.07
            k.add("center", "cylinder", at: head, size: v3(sunflower ? 0.13 : 0.05, 0.03, sunflower ? 0.13 : 0.05), rot: v3(90, 0, 0),
                  color: k.color("center", sunflower ? "brown" : "yellow"), material: "fabric")
            for i in 0..<n {
                let a = 360 * Float(i) / Float(n)
                let rad = a * Float.pi / 180
                k.add("petal", "sphere", at: head + v3(cos(rad) * radius, sin(rad) * radius, -0.004), size: v3(length, length * 0.45, 0.012),
                      rot: v3(0, 0, a), color: petalColor, material: "fabric")
            }
            return sunflower ? "Sunflower" : "Flower"
        }
    }
}

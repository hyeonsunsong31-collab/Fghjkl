import Foundation

/// Characters, furniture and everyday objects.
extension DesignLibrary {
    // MARK: - Characters

    static func robot(_ k: inout DesignKit) -> String {
        let body = k.mainColor("silver")
        let accent = k.accentColor(k.futuristic ? "cyan" : "blue")
        let eye = k.color("eye", k.color("visor", "cyan"))
        let finish = k.mainMaterial("metal")
        if k.variant == "cute" {
            k.add("body", "roundedCube", at: v3(0, 0.22, 0), size: v3(0.26, 0.22, 0.2), color: body, material: finish, param: 0.6)
            k.add("head", "sphere", at: v3(0, 0.47, 0), size: v3(0.34, 0.3, 0.3), color: k.color("head", body), material: finish)
            k.add("visor", "sphere", at: v3(0, 0.47, 0.1), size: v3(0.26, 0.17, 0.12), color: "black", material: "glass")
            k.pair("eye", "sphere", at: v3(0.055, 0.48, 0.155), size: v3(0.05, 0.06, 0.02), color: eye, material: "emissive")
            k.pair("arm", "capsule", at: v3(0.16, 0.22, 0), size: v3(0.06, 0.16, 0.06), rot: v3(0, 0, 20), color: accent, material: finish)
            k.pair("leg", "capsule", at: v3(0.07, 0.07, 0), size: v3(0.08, 0.14, 0.08), color: accent, material: finish)
            k.add("antenna", "cylinder", at: v3(0, 0.66, 0), size: v3(0.012, 0.09, 0.012), color: "darkgray", material: "metal")
            k.add("antenna tip", "sphere", at: v3(0, 0.71, 0), size: v3(0.035, 0.035, 0.035), color: k.color("antenna", "red"), material: "emissive")
            k.handle("body", "head")
            return "Cute robot"
        }
        let legs = k.count("leg", k.variant == "spider" ? 6 : 2, 0...8)
        let arms = k.count("arm", 2, 0...6)
        var hipY: Float = 0.5
        if legs >= 3 {
            // Walker: legs radiating from the body.
            hipY = 0.3
            k.ring("leg", "capsule", count: legs, at: v3(0, hipY + 0.02, 0.17), size: v3(0.045, 0.24, 0.045), rot: v3(-60, 0, 0), color: accent, material: finish)
            k.ring("leg", "capsule", count: legs, at: v3(0, hipY - 0.15, 0.32), size: v3(0.05, 0.3, 0.05), rot: v3(20, 0, 0), color: body, material: finish)
        } else if legs > 0 {
            k.pair("leg", "roundedCube", at: v3(0.085, 0.38, 0), size: v3(0.09, 0.2, 0.1), color: body, material: finish, param: 0.5)
            k.pair("knee", "sphere", at: v3(0.085, 0.265, 0.005), size: v3(0.085, 0.085, 0.085), color: accent, material: finish)
            k.pair("leg", "roundedCube", at: v3(0.085, 0.15, 0.01), size: v3(0.1, 0.2, 0.11), color: body, material: finish, param: 0.5)
            k.pair("foot", "roundedCube", at: v3(0.085, 0.028, 0.03), size: v3(0.12, 0.056, 0.18), color: accent, material: finish, param: 0.4)
        }
        k.add("pelvis", "roundedCube", at: v3(0, hipY, 0), size: v3(0.26, 0.08, 0.15), color: accent, material: finish, param: 0.5)
        let torsoY = hipY + 0.2
        k.add("body", "roundedCube", at: v3(0, torsoY, 0), size: v3(0.34, 0.3, 0.2), color: body, material: finish, param: 0.35)
        k.add("core", "cylinder", at: v3(0, torsoY + 0.04, 0.1), size: v3(0.08, 0.016, 0.08), rot: v3(90, 0, 0), color: k.color("core", eye), material: "emissive")
        k.pair("trim", "cube", at: v3(0.12, torsoY - 0.02, 0.101), size: v3(0.05, 0.16, 0.006), color: accent, material: finish)
        let shoulderY = torsoY + 0.12
        for pairIndex in 0..<(arms + 1) / 2 {
            let y = shoulderY - Float(pairIndex) * 0.13
            k.pair("shoulder", "sphere", at: v3(0.22, y, 0), size: v3(0.11, 0.11, 0.11), color: accent, material: finish)
            k.pair("arm", "capsule", at: v3(0.235, y - 0.14, 0), size: v3(0.075, 0.2, 0.075), color: body, material: finish)
            k.pair("arm", "capsule", at: v3(0.24, y - 0.31, 0.025), size: v3(0.08, 0.2, 0.08), rot: v3(-12, 0, 0), color: body, material: finish)
            if k.wants("cannon") && pairIndex == 0 {
                k.add("cannon", "cylinder", at: v3(0.24, y - 0.42, 0.07), size: v3(0.05, 0.16, 0.05), rot: v3(-80, 0, 0), color: "darkgray", material: "metal")
                k.add("hand", "roundedCube", at: v3(-0.24, y - 0.44, 0.04), size: v3(0.07, 0.07, 0.06), color: accent, material: finish, param: 0.4)
            } else {
                k.pair("hand", "roundedCube", at: v3(0.24, y - 0.44, 0.04), size: v3(0.07, 0.07, 0.06), color: accent, material: finish, param: 0.4)
            }
        }
        let headY = torsoY + 0.29
        k.add("neck", "cylinder", at: v3(0, torsoY + 0.17, 0), size: v3(0.07, 0.06, 0.07), color: "darkgray", material: "metal")
        k.add("head", "roundedCube", at: v3(0, headY, 0), size: v3(0.2, 0.17, 0.18), color: k.color("head", body), material: finish, param: 0.4)
        if k.wants("eye") && !k.wants("visor") {
            k.pair("eye", "sphere", at: v3(0.045, headY + 0.01, 0.09), size: v3(0.04, 0.04, 0.02), color: eye, material: "emissive")
        } else {
            k.add("visor", "roundedCube", at: v3(0, headY + 0.01, 0.09), size: v3(0.17, 0.05, 0.02), color: eye, material: "emissive", param: 0.5)
            k.handle("eye")
        }
        k.pair("ear", "cylinder", at: v3(0.105, headY, 0), size: v3(0.05, 0.02, 0.05), rot: v3(0, 0, 90), color: accent, material: finish)
        let antennas = k.count("antenna", k.wants("antenna") ? 1 : 0, 0...4)
        for i in 0..<antennas {
            let x = antennas == 1 ? 0 : -0.06 + 0.12 * Float(i) / Float(antennas - 1)
            k.add("antenna", "cylinder", at: v3(x, headY + 0.13, 0), size: v3(0.01, 0.09, 0.01), color: "darkgray", material: "metal")
            k.add("antenna tip", "sphere", at: v3(x, headY + 0.18, 0), size: v3(0.03, 0.03, 0.03), color: k.color("antenna", "red"), material: "emissive")
        }
        if k.wants("wing") {
            k.pair("wing", "wedge", at: v3(0.2, torsoY + 0.05, -0.15), size: v3(0.02, 0.3, 0.4), rot: v3(0, 0, -100), color: accent, material: finish)
        }
        k.handle("body")
        return legs >= 3 ? "Walker robot" : "Robot"
    }

    static func helmet(_ k: inout DesignKit) -> String {
        let shell = k.mainColor("red")
        let plate = k.color("visor", k.accentColor("gold"))
        let eye = k.color("eye", "cyan")
        let finish = k.mainMaterial("metal")
        k.add("body", "sphere", at: v3(0, 0.26, -0.01), size: v3(0.36, 0.4, 0.4), color: shell, material: finish)
        k.add("visor", "roundedCube", at: v3(0, 0.21, 0.13), size: v3(0.27, 0.24, 0.12), color: plate, material: k.material("visor", "metal"), param: 0.55)
        if k.wants("visor") && k.brief.materials["visor"] == "glass" {
            k.add("eye", "roundedCube", at: v3(0, 0.25, 0.192), size: v3(0.22, 0.06, 0.012), color: eye, material: "glass", param: 0.5)
        } else {
            k.pair("eye", "cube", at: v3(0.058, 0.25, 0.192), size: v3(0.075, 0.022, 0.01), color: eye, material: "emissive")
        }
        k.add("mouth guard", "roundedCube", at: v3(0, 0.1, 0.12), size: v3(0.22, 0.09, 0.12), color: plate, material: "metal", param: 0.5)
        k.add("mouth", "cube", at: v3(0, 0.11, 0.181), size: v3(0.1, 0.008, 0.004), color: "black", material: "metal")
        k.pair("ear", "cylinder", at: v3(0.18, 0.22, 0), size: v3(0.12, 0.035, 0.12), rot: v3(0, 0, 90), color: k.color("ear", "darkgray"), material: "metal")
        k.add("neck ring", "torus", at: v3(0, 0.04, -0.01), size: v3(0.3, 0.05, 0.32), color: "darkgray", material: "metal")
        if k.wants("crest") {
            k.add("crest", "roundedCube", at: v3(0, 0.47, -0.03), size: v3(0.03, 0.08, 0.32), color: k.color("crest", k.accentColor("gold")), material: "metal", param: 0.5)
        }
        let horns = k.count("horn", k.wants("horn") ? 2 : 0, 0...4)
        if horns >= 2 {
            k.pair("horn", "cone", at: v3(0.17, 0.42, 0.0), size: v3(0.06, 0.2, 0.06), rot: v3(0, 0, -40), color: k.color("horn", "beige"), material: "plastic")
        } else if horns == 1 {
            k.add("horn", "cone", at: v3(0, 0.5, 0.06), size: v3(0.06, 0.2, 0.06), rot: v3(20, 0, 0), color: k.color("horn", "beige"), material: "plastic")
        }
        if k.wants("antenna") {
            k.pair("antenna", "cylinder", at: v3(0.2, 0.36, -0.02), size: v3(0.012, 0.16, 0.012), color: "darkgray", material: "metal")
        }
        if k.wants("stand") || k.wants("base") {
            k.add("stand", "cylinder", at: v3(0, -0.06, -0.01), size: v3(0.1, 0.12, 0.1), color: "darkgray", material: "metal")
            k.add("base", "cylinder", at: v3(0, -0.13, -0.01), size: v3(0.26, 0.03, 0.26), color: "black", material: "metal")
        }
        k.handle("body")
        return "Helmet"
    }

    static func snowman(_ k: inout DesignKit) -> String {
        let snow = k.mainColor("white")
        k.add("body", "sphere", at: v3(0, 0.17, 0), size: v3(0.36, 0.34, 0.36), color: snow, material: "fabric")
        k.add("body", "sphere", at: v3(0, 0.44, 0), size: v3(0.27, 0.26, 0.27), color: snow, material: "fabric")
        k.add("head", "sphere", at: v3(0, 0.65, 0), size: v3(0.19, 0.19, 0.19), color: snow, material: "fabric")
        k.pair("eye", "sphere", at: v3(0.035, 0.68, 0.085), size: v3(0.025, 0.025, 0.025), color: k.color("eye", "black"), material: "plastic")
        k.add("nose", "cone", at: v3(0, 0.65, 0.13), size: v3(0.03, 0.09, 0.03), rot: v3(90, 0, 0), color: k.color("nose", "orange"), material: "plastic")
        k.add("mouth", "torus", at: v3(0, 0.61, 0.088), size: v3(0.05, 0.008, 0.02), rot: v3(90, 0, 0), color: "black", material: "plastic")
        let buttons = k.count("button", 3, 0...6)
        for i in 0..<buttons {
            k.add("button", "sphere", at: v3(0, 0.5 - Float(i) * 0.07, 0.128 - Float(i) * 0.008), size: v3(0.025, 0.025, 0.025), color: k.color("button", "black"), material: "plastic")
        }
        k.pair("arm", "cylinder", at: v3(0.2, 0.5, 0), size: v3(0.014, 0.22, 0.014), rot: v3(0, 0, -55), color: k.color("arm", "brown"), material: "wood")
        if k.keeps("scarf") {
            k.add("scarf", "torus", at: v3(0, 0.555, 0), size: v3(0.22, 0.04, 0.22), color: k.color("scarf", k.accentColor("red")), material: "fabric")
        }
        if k.keeps("hat") {
            k.add("hat", "cylinder", at: v3(0, 0.735, 0), size: v3(0.2, 0.012, 0.2), color: k.color("hat", "black"), material: "fabric")
            k.add("hat", "cylinder", at: v3(0, 0.8, 0), size: v3(0.13, 0.13, 0.13), color: k.color("hat", "black"), material: "fabric")
        }
        k.handle("body")
        return "Snowman"
    }

    // MARK: - Furniture

    static func table(_ k: inout DesignKit) -> String {
        let request = k.brief.request.lowercased()
        let round = request.contains("round") || request.contains("원형") || request.contains("둥근") || k.count("leg", 4, 1...8) == 3
        let desk = request.contains("desk") || request.contains("책상")
        let legs = k.count("leg", round ? 1 : 4, 1...8)
        let topMat = k.material("tabletop", k.mainMaterial("wood"))
        let topColor = k.color("tabletop", k.mainColor(topMat == "glass" ? "cyan" : "brown"))
        let legColor = k.color("leg", topMat == "glass" ? "silver" : topColor)
        let legMat = k.material("leg", topMat == "glass" ? "metal" : topMat)
        let h: Float = 0.5
        let W: Float = round ? 0.8 : (desk ? 1.0 : 0.9), D: Float = round ? 0.8 : 0.55
        if round {
            k.add("tabletop", "cylinder", at: v3(0, h, 0), size: v3(W, 0.04, D), color: topColor, material: topMat)
        } else {
            k.add("tabletop", "roundedCube", at: v3(0, h, 0), size: v3(W, 0.04, D), color: topColor, material: topMat, param: 0.2)
            k.pair("apron", "cube", at: v3(W / 2 - 0.05, h - 0.045, 0), size: v3(0.02, 0.05, D - 0.1), color: legColor, material: legMat)
            k.add("apron", "cube", at: v3(0, h - 0.045, D / 2 - 0.05), size: v3(W - 0.1, 0.05, 0.02), color: legColor, material: legMat)
            k.add("apron", "cube", at: v3(0, h - 0.045, -D / 2 + 0.05), size: v3(W - 0.1, 0.05, 0.02), color: legColor, material: legMat)
        }
        let legH = h - 0.02
        if legs == 1 {
            k.add("leg", "cylinder", at: v3(0, legH / 2, 0), size: v3(0.08, legH, 0.08), color: legColor, material: legMat)
            k.add("base", "cylinder", at: v3(0, 0.015, 0), size: v3(0.4, 0.03, 0.4), color: legColor, material: legMat)
        } else if round || legs == 3 {
            k.ring("leg", "cylinder", count: legs, at: v3(0, legH / 2, W * 0.32), size: v3(0.04, legH, 0.04), rot: v3(-6, 0, 0), color: legColor, material: legMat)
        } else {
            let perSide = Swift.max(2, legs / 2)
            for i in 0..<perSide {
                let x = -(W / 2 - 0.06) + (W - 0.12) * Float(i) / Float(perSide - 1)
                k.add("leg", "cube", at: v3(x, legH / 2, D / 2 - 0.05), size: v3(0.045, legH, 0.045), color: legColor, material: legMat)
                k.add("leg", "cube", at: v3(x, legH / 2, -D / 2 + 0.05), size: v3(0.045, legH, 0.045), color: legColor, material: legMat)
            }
        }
        if k.wants("drawer") || desk {
            let drawers = k.count("drawer", desk ? 3 : 1, 1...5)
            let dx = W / 2 - 0.17
            k.add("drawer unit", "cube", at: v3(dx, h - 0.03 - 0.075 * Float(drawers) / 2, 0), size: v3(0.28, 0.075 * Float(drawers), D - 0.08),
                  color: topColor, material: topMat)
            for i in 0..<drawers {
                let y = h - 0.065 - 0.075 * Float(i)
                k.add("drawer", "cube", at: v3(dx, y, D / 2 - 0.035), size: v3(0.25, 0.06, 0.012), color: k.color("drawer", topColor), material: topMat)
                k.add("handle", "cube", at: v3(dx, y, D / 2 - 0.026), size: v3(0.07, 0.01, 0.012), color: "silver", material: "metal")
            }
        }
        k.handle("body")
        return desk ? "Desk" : (round ? "Round table" : "Table")
    }

    static func chair(_ k: inout DesignKit) -> String {
        let seatColor = k.color("seat", k.mainColor(k.variant == "throne" ? "red" : (k.variant == "office" ? "black" : "brown")))
        let frame = k.color("leg", k.variant == "throne" ? "gold" : (k.variant == "office" ? "darkgray" : seatColor))
        let wood = k.mainMaterial(k.variant == "office" || k.variant == "throne" ? "fabric" : "wood")
        let seatY: Float = 0.44
        if k.variant == "office" {
            k.add("seat", "roundedCube", at: v3(0, seatY, 0), size: v3(0.46, 0.07, 0.44), color: seatColor, material: "fabric", param: 0.6)
            k.add("backrest", "roundedCube", at: v3(0, seatY + 0.265, -0.2), size: v3(0.44, 0.48, 0.06), rot: v3(-8, 0, 0), color: seatColor, material: "fabric", param: 0.6)
            k.add("column", "cylinder", at: v3(0, seatY - 0.17, 0), size: v3(0.05, 0.3, 0.05), color: frame, material: "chrome")
            let legs = k.count("leg", 5, 3...6)
            k.ring("leg", "roundedCube", count: legs, at: v3(0, 0.07, 0.15), size: v3(0.04, 0.03, 0.3), color: frame, material: "metal", param: 0.5)
            k.ring("wheel", "sphere", count: legs, at: v3(0, 0.03, 0.29), size: v3(0.05, 0.05, 0.05), color: "black", material: "rubber")
            k.pair("armrest", "roundedCube", at: v3(0.25, seatY + 0.14, 0), size: v3(0.05, 0.03, 0.26), color: frame, material: "plastic", param: 0.5)
            k.pair("armrest post", "cube", at: v3(0.25, seatY + 0.07, 0), size: v3(0.03, 0.12, 0.03), color: frame, material: "metal")
            k.handle("body")
            return "Office chair"
        }
        let stool = k.variant == "stool"
        if stool {
            k.add("seat", "cylinder", at: v3(0, 0.62, 0), size: v3(0.34, 0.05, 0.34), color: seatColor, material: wood)
            k.ring("leg", "cylinder", count: k.count("leg", 4, 3...6), at: v3(0, 0.3, 0.12), size: v3(0.03, 0.62, 0.03), rot: v3(-8, 0, 0), color: frame, material: wood, phase: 45)
            k.add("foot ring", "torus", at: v3(0, 0.22, 0), size: v3(0.3, 0.02, 0.3), color: frame, material: wood)
            k.handle("body")
            return "Stool"
        }
        let throne = k.variant == "throne"
        let W: Float = throne ? 0.6 : 0.42
        k.add("seat", "roundedCube", at: v3(0, seatY, 0), size: v3(W, throne ? 0.1 : 0.05, 0.42), color: seatColor, material: throne ? "fabric" : wood, param: 0.3)
        let legs = k.count("leg", 4, 3...8)
        if legs == 4 {
            for sx in [Float(-1), 1] {
                for sz in [Float(-1), 1] {
                    k.add("leg", throne ? "cube" : "cylinder", at: v3(sx * (W / 2 - 0.035), seatY / 2, sz * 0.175), size: v3(0.04, seatY, 0.04), color: frame,
                          material: throne ? "metal" : wood)
                }
            }
        } else {
            k.ring("leg", "cylinder", count: legs, at: v3(0, seatY / 2, 0.17), size: v3(0.04, seatY, 0.04), color: frame, material: wood)
        }
        if k.keeps("backrest") {
            let backH: Float = throne ? 0.8 : 0.38
            k.add("backrest", "roundedCube", at: v3(0, seatY + backH / 2 + 0.02, -0.19), size: v3(W, backH, throne ? 0.08 : 0.035), rot: v3(-6, 0, 0),
                  color: k.color("backrest", throne ? frame : seatColor), material: throne ? "metal" : wood, param: 0.3)
            if throne {
                k.add("backrest", "roundedCube", at: v3(0, seatY + backH / 2, -0.15), size: v3(W * 0.7, backH * 0.75, 0.02), rot: v3(-6, 0, 0),
                      color: seatColor, material: "fabric", param: 0.5)
                k.ring("gem", "sphere", count: 1, at: v3(0, seatY + backH + 0.05, -0.22), size: v3(0.07, 0.07, 0.07), color: k.color("gem", "red"), material: "glass")
            }
        }
        if k.wants("armrest") || throne {
            k.pair("armrest", "roundedCube", at: v3(W / 2 - 0.02, seatY + 0.16, 0), size: v3(0.05, 0.04, 0.4), color: frame, material: throne ? "metal" : wood, param: 0.4)
            k.pair("armrest post", "cube", at: v3(W / 2 - 0.02, seatY + 0.08, 0.15), size: v3(0.035, 0.16, 0.035), color: frame, material: throne ? "metal" : wood)
        }
        k.handle("body")
        return throne ? "Throne" : "Chair"
    }

    static func sofa(_ k: inout DesignKit) -> String {
        let cloth = k.mainColor("gray")
        let seats = k.count("seat", 3, 1...6)
        let W: Float = 0.36 * Float(seats) + 0.2
        k.add("base", "roundedCube", at: v3(0, 0.15, 0), size: v3(W, 0.18, 0.52), color: cloth, material: "fabric", param: 0.3)
        let cushionW = (W - 0.22) / Float(seats)
        for i in 0..<seats {
            let x = -W / 2 + 0.11 + cushionW * (Float(i) + 0.5)
            k.add("seat", "roundedCube", at: v3(x, 0.29, 0.03), size: v3(cushionW - 0.01, 0.1, 0.44), color: k.color("seat", cloth), material: "fabric", param: 0.7)
            k.add("backrest", "roundedCube", at: v3(x, 0.45, -0.19), size: v3(cushionW - 0.01, 0.3, 0.12), rot: v3(-8, 0, 0), color: k.color("backrest", cloth),
                  material: "fabric", param: 0.7)
        }
        k.pair("armrest", "roundedCube", at: v3(W / 2 - 0.055, 0.32, 0), size: v3(0.11, 0.3, 0.52), color: cloth, material: "fabric", param: 0.6)
        for sx in [Float(-1), 1] {
            for sz in [Float(-1), 1] {
                k.add("leg", "cylinder", at: v3(sx * (W / 2 - 0.06), 0.03, sz * 0.2), size: v3(0.04, 0.06, 0.04), color: k.color("leg", "brown"), material: "wood")
            }
        }
        if k.wants("pillow") {
            let pillow = k.color("pillow", k.accentColor("beige"))
            k.pair("pillow", "roundedCube", at: v3(W / 2 - 0.2, 0.42, -0.08), size: v3(0.2, 0.2, 0.07), rot: v3(-15, 0, 0), color: pillow, material: "fabric", param: 0.8)
        }
        k.handle("body")
        return seats == 1 ? "Armchair" : "Sofa"
    }

    static func bed(_ k: inout DesignKit) -> String {
        let wood = k.color("frame", "brown")
        k.add("frame", "cube", at: v3(0, 0.15, 0), size: v3(0.76, 0.14, 1.16), color: wood, material: "wood")
        for sx in [Float(-1), 1] {
            for sz in [Float(-1), 1] {
                k.add("leg", "cube", at: v3(sx * 0.35, 0.04, sz * 0.54), size: v3(0.05, 0.08, 0.05), color: wood, material: "wood")
            }
        }
        k.add("mattress", "roundedCube", at: v3(0, 0.29, 0.01), size: v3(0.72, 0.14, 1.1), color: "white", material: "fabric", param: 0.4)
        if k.keeps("blanket") {
            k.add("blanket", "roundedCube", at: v3(0, 0.37, 0.18), size: v3(0.76, 0.04, 0.76), color: k.color("blanket", k.mainColor("navy")), material: "fabric", param: 0.6)
        }
        let pillows = k.count("pillow", 2, 0...4)
        for i in 0..<pillows {
            let x = pillows == 1 ? 0 : -0.17 + 0.34 * Float(i) / Float(pillows - 1)
            k.add("pillow", "roundedCube", at: v3(x, 0.39, -0.42), size: v3(pillows > 2 ? 0.16 : 0.3, 0.07, 0.17), color: k.color("pillow", "white"), material: "fabric", param: 0.8)
        }
        if k.keeps("headboard") {
            k.add("headboard", "roundedCube", at: v3(0, 0.38, -0.6), size: v3(0.8, 0.52, 0.05), color: k.color("headboard", wood), material: "wood", param: 0.25)
        }
        k.handle("body")
        return "Bed"
    }

    static func lamp(_ k: inout DesignKit) -> String {
        let request = k.brief.request.lowercased()
        let shade = k.color("shade", k.mainColor(k.variant == "floor" ? "beige" : "white"))
        let metal = k.color("stand", k.accentColor("darkgray"))
        let glow = k.color("bulb", k.color("light", "yellow"))
        if k.variant == "floor" {
            k.add("base", "cylinder", at: v3(0, 0.015, 0), size: v3(0.32, 0.03, 0.32), color: metal, material: "metal")
            k.add("stand", "cylinder", at: v3(0, 0.66, 0), size: v3(0.025, 1.26, 0.025), color: metal, material: "metal")
            k.add("bulb", "sphere", at: v3(0, 1.24, 0), size: v3(0.08, 0.1, 0.08), color: glow, material: "emissive")
            k.add("shade", "frustum", at: v3(0, 1.28, 0), size: v3(0.4, 0.28, 0.4), color: shade, material: "fabric", param: 0.62)
            k.handle("body")
            return "Floor lamp"
        }
        if request.contains("desk") || request.contains("책상") {
            k.add("base", "cylinder", at: v3(0, 0.015, 0), size: v3(0.2, 0.03, 0.2), color: metal, material: "metal")
            k.add("stand", "cylinder", at: v3(0, 0.17, -0.04), size: v3(0.022, 0.31, 0.022), rot: v3(-15, 0, 0), color: metal, material: "metal")
            k.add("joint", "sphere", at: v3(0, 0.32, -0.08), size: v3(0.04, 0.04, 0.04), color: metal, material: "metal")
            k.add("stand", "cylinder", at: v3(0, 0.37, 0.05), size: v3(0.02, 0.28, 0.02), rot: v3(62, 0, 0), color: metal, material: "metal")
            k.add("shade", "frustum", at: v3(0, 0.36, 0.2), size: v3(0.16, 0.13, 0.16), rot: v3(25, 0, 0), color: shade, material: "metal", param: 0.45)
            k.add("bulb", "sphere", at: v3(0, 0.31, 0.22), size: v3(0.055, 0.055, 0.055), color: glow, material: "emissive")
            k.handle("body")
            return "Desk lamp"
        }
        k.add("base", "vase", at: v3(0, 0.13, 0), size: v3(0.18, 0.26, 0.18), color: k.color("base", k.accentColor("navy")), material: "plastic")
        k.add("stand", "cylinder", at: v3(0, 0.3, 0), size: v3(0.02, 0.1, 0.02), color: "gold", material: "metal")
        k.add("bulb", "sphere", at: v3(0, 0.37, 0), size: v3(0.07, 0.08, 0.07), color: glow, material: "emissive")
        k.add("shade", "frustum", at: v3(0, 0.42, 0), size: v3(0.34, 0.22, 0.34), color: shade, material: "fabric", param: 0.65)
        k.handle("body")
        return "Table lamp"
    }

    // MARK: - Objects

    static func mug(_ k: inout DesignKit) -> String {
        let request = k.brief.request.lowercased()
        let teacup = request.contains("tea") || request.contains("찻잔")
        let ceramic = k.mainColor("white")
        let h: Float = teacup ? 0.13 : 0.22, d: Float = teacup ? 0.22 : 0.2
        k.add("body", "cup", at: v3(0, h / 2 + (teacup ? 0.015 : 0), 0), size: v3(d, h, d), color: ceramic, material: k.mainMaterial("plastic"))
        k.add("handle", "torus", at: v3(d / 2 + 0.02, h / 2 + (teacup ? 0.015 : 0), 0), size: v3(teacup ? 0.08 : 0.11, 0.022, teacup ? 0.08 : 0.11), rot: v3(90, 0, 0),
              color: k.color("handle", ceramic), material: "plastic")
        if k.keeps("coffee") {
            k.add("coffee", "cylinder", at: v3(0, h * 0.86 + (teacup ? 0.015 : 0), 0), size: v3(d * 0.86, 0.01, d * 0.86), color: "brown", material: "glass")
        }
        if teacup || k.wants("base") {
            k.add("saucer", "cylinder", at: v3(0, 0.008, 0), size: v3(d * 1.5, 0.016, d * 1.5), color: ceramic, material: "plastic")
        }
        if k.wants("stripe") || k.brief.colors["accent"] != nil {
            k.add("stripe", "tube", at: v3(0, h * 0.75, 0), size: v3(d + 0.004, 0.02, d + 0.004), color: k.accentColor("blue"), material: "plastic", param: 0.04)
        }
        k.handle("body")
        return teacup ? "Teacup" : "Mug"
    }

    static func bottle(_ k: inout DesignKit) -> String {
        let glass = k.mainColor("green")
        k.add("body", "bottle", at: v3(0, 0.19, 0), size: v3(0.14, 0.38, 0.14), color: glass, material: k.mainMaterial("glass"))
        k.add("lid", "cylinder", at: v3(0, 0.39, 0), size: v3(0.032, 0.03, 0.032), color: k.color("lid", "gold"), material: "metal")
        if k.keeps("label") {
            k.add("label", "tube", at: v3(0, 0.15, 0), size: v3(0.142, 0.1, 0.142), color: k.color("label", "beige"), material: "fabric", param: 0.05)
        }
        k.handle("body")
        return "Bottle"
    }

    static func sword(_ k: inout DesignKit) -> String {
        let katana = k.variant == "katana"
        let blade = k.color("blade", k.mainColor("silver"))
        let gold = k.color("guard", k.accentColor(katana ? "black" : "gold"))
        let grip = k.color("handle", katana ? "black" : "brown")
        let bladeL: Float = katana ? 0.72 : 0.68
        let y0: Float = katana ? 0.244 : 0.255
        k.add("pommel", "sphere", at: v3(0, 0.025, 0), size: v3(0.05, 0.05, 0.05), color: gold, material: "metal")
        k.add("handle", "cylinder", at: v3(0, 0.13, 0), size: v3(0.032, 0.2, 0.032), color: grip, material: katana ? "fabric" : "wood")
        if katana {
            k.add("guard", "cylinder", at: v3(0, 0.24, 0), size: v3(0.09, 0.012, 0.09), color: gold, material: "metal")
        } else {
            k.add("guard", "roundedCube", at: v3(0, 0.245, 0), size: v3(0.24, 0.03, 0.045), color: gold, material: "metal", param: 0.6)
        }
        k.add("blade", "cube", at: v3(0, y0 + bladeL / 2, 0), size: v3(katana ? 0.035 : 0.05, bladeL, 0.01), rot: v3(0, 0, katana ? -1.5 : 0),
              color: blade, material: "chrome")
        k.add("blade tip", "pyramid", at: v3(katana ? -0.009 : 0, y0 + bladeL + 0.04, 0), size: v3(katana ? 0.035 : 0.05, 0.08, 0.01), color: blade, material: "chrome")
        if !katana { k.add("fuller", "cube", at: v3(0, y0 + bladeL * 0.4, 0.0055), size: v3(0.01, bladeL * 0.7, 0.002), color: "gray", material: "metal") }
        if k.wants("gem") {
            k.add("gem", "sphere", at: v3(0, 0.245, 0.024), size: v3(0.025, 0.025, 0.012), color: k.color("gem", "red"), material: "glass")
        }
        k.handle("body")
        return katana ? "Katana" : "Sword"
    }

    static func shield(_ k: inout DesignKit) -> String {
        let face = k.mainColor("red")
        let rim = k.color("trim", k.accentColor("silver"))
        let d: Float = 0.62
        k.add("body", "cylinder", at: v3(0, d / 2, 0), size: v3(d, 0.045, d), rot: v3(90, 0, 0), color: face, material: k.mainMaterial("paint"))
        k.add("rim", "torus", at: v3(0, d / 2, 0), size: v3(d + 0.02, 0.05, d + 0.02), rot: v3(90, 0, 0), color: rim, material: "metal")
        k.add("boss", "hemisphere", at: v3(0, d / 2, 0.035), size: v3(0.14, 0.05, 0.14), rot: v3(90, 0, 0), color: k.color("boss", "gold"), material: "metal")
        k.add("emblem", "cube", at: v3(0, d / 2, 0.025), size: v3(0.05, d * 0.8, 0.008), color: rim, material: "metal")
        k.add("emblem", "cube", at: v3(0, d / 2, 0.025), size: v3(d * 0.8, 0.05, 0.008), color: rim, material: "metal")
        k.handle("body")
        return "Shield"
    }

    static func crown(_ k: inout DesignKit) -> String {
        let gold = k.mainColor("gold")
        let metal = k.mainMaterial("metal")
        k.add("body", "tube", at: v3(0, 0.05, 0), size: v3(0.3, 0.1, 0.3), color: gold, material: metal, param: 0.12)
        let points = k.count("point", 6, 3...12)
        k.ring("point", "pyramid", count: points, at: v3(0, 0.13, 0.135), size: v3(0.05, 0.08, 0.02), color: gold, material: metal)
        k.ring("point tip", "sphere", count: points, at: v3(0, 0.18, 0.135), size: v3(0.025, 0.025, 0.025), color: gold, material: metal)
        let gems = k.count("gem", points, 0...12)
        let palette = ["red", "blue", "darkgreen", "purple"]
        for i in 0..<gems {
            let a = Float(i) / Float(Swift.max(gems, 1)) * 360
            var gem = ModelSpec.Part(name: "gem", shape: "sphere", position: v3(0, 0.05, 0.152), size: v3(0.03, 0.03, 0.016),
                                     color: k.brief.colors["gem"] ?? palette[i % palette.count], material: "glass")
            gem = gem.rotatedAboutY(a)
            k.add(gem.name, gem.shape, at: gem.position, size: gem.size, rot: gem.rotation, color: gem.color, material: gem.material)
        }
        if k.style("luxury") || k.wants("cap") {
            k.add("cap", "hemisphere", at: v3(0, 0.1, 0), size: v3(0.27, 0.12, 0.27), color: k.accentColor("red"), material: "fabric")
        }
        k.handle("body")
        return "Crown"
    }

    static func computer(_ k: inout DesignKit) -> String {
        let shell = k.mainColor(k.variant == "laptop" ? "silver" : "black")
        let screen = k.color("screen", "blue")
        if k.variant == "laptop" {
            k.add("base", "roundedCube", at: v3(0, 0.012, 0.0), size: v3(0.46, 0.024, 0.32), color: shell, material: "metal", param: 0.4)
            k.add("keyboard", "cube", at: v3(0, 0.025, 0.02), size: v3(0.38, 0.003, 0.14), color: "black", material: "plastic")
            k.add("body", "roundedCube", at: v3(0, 0.15, -0.17), size: v3(0.46, 0.3, 0.014), rot: v3(-12, 0, 0), color: shell, material: "metal", param: 0.4)
            k.add("screen", "cube", at: v3(0, 0.152, -0.161), size: v3(0.42, 0.26, 0.004), rot: v3(-12, 0, 0), color: screen, material: "emissive")
            k.handle("body")
            return "Laptop"
        }
        k.add("base", "roundedCube", at: v3(0, 0.01, -0.02), size: v3(0.22, 0.02, 0.16), color: shell, material: "metal", param: 0.5)
        k.add("stand", "roundedCube", at: v3(0, 0.12, -0.05), size: v3(0.05, 0.22, 0.03), color: shell, material: "metal", param: 0.5)
        k.add("body", "roundedCube", at: v3(0, 0.34, -0.03), size: v3(0.62, 0.38, 0.03), color: shell, material: "plastic", param: 0.2)
        k.add("screen", "cube", at: v3(0, 0.345, -0.013), size: v3(0.58, 0.33, 0.004), color: screen, material: "emissive")
        if k.keeps("keyboard") {
            k.add("keyboard", "roundedCube", at: v3(0, 0.012, 0.2), size: v3(0.44, 0.024, 0.14), color: k.color("keyboard", shell), material: "plastic", param: 0.3)
            k.add("mouse", "sphere", at: v3(0.3, 0.015, 0.2), size: v3(0.06, 0.03, 0.1), color: k.color("keyboard", shell), material: "plastic")
        }
        k.handle("body")
        return "Computer"
    }

    static func windmill(_ k: inout DesignKit) -> String {
        let blades = k.count("blade", k.count("propeller", 4, 2...8), 2...8)
        if k.brief.request.lowercased().contains("turbine") || k.brief.request.contains("발전기") {
            k.add("body", "frustum", at: v3(0, 0.6, 0), size: v3(0.06, 1.2, 0.06), color: "white", material: "paint", param: 0.6)
            k.add("nacelle", "capsule", at: v3(0, 1.22, 0.02), size: v3(0.07, 0.2, 0.07), rot: v3(90, 0, 0), color: "white", material: "paint")
            for i in 0..<3 {
                let a = Float(i) * 120
                let rad = a * Float.pi / 180
                k.add("blade", "roundedCube", at: v3(sin(rad) * 0.27, 1.22 + cos(rad) * 0.27, 0.13), size: v3(0.04, 0.54, 0.012), rot: v3(0, 0, -a),
                      color: k.color("blade", "white"), material: "paint", param: 0.6)
            }
            k.handle("body")
            return "Wind turbine"
        }
        let wall = k.mainColor("white")
        k.add("body", "frustum", at: v3(0, 0.4, 0), size: v3(0.42, 0.8, 0.42), color: wall, material: k.mainMaterial("stone"), param: 0.62)
        k.add("roof", "cone", at: v3(0, 0.92, 0), size: v3(0.32, 0.26, 0.32), color: k.color("roof", "brown"), material: "wood")
        k.add("hub", "cylinder", at: v3(0, 0.82, 0.17), size: v3(0.06, 0.06, 0.06), rot: v3(90, 0, 0), color: "darkgray", material: "metal")
        for i in 0..<blades {
            let a = 360 * Float(i) / Float(blades) + 45
            let rad = a * Float.pi / 180
            k.add("blade", "cube", at: v3(sin(rad) * 0.25, 0.82 + cos(rad) * 0.25, 0.205), size: v3(0.08, 0.46, 0.01), rot: v3(0, 0, -a),
                  color: k.color("blade", "beige"), material: "wood")
        }
        k.add("door", "halfCylinder", at: v3(0, 0.06, 0.2), size: v3(0.012, 0.12, 0.09), rot: v3(0, 90, 0), color: "brown", material: "wood")
        k.add("window", "cube", at: v3(0, 0.45, 0.178), size: v3(0.06, 0.07, 0.008), color: k.color("window", "cyan"), material: "glass")
        k.handle("body")
        return "Windmill"
    }

    static func reactor(_ k: inout DesignKit) -> String {
        let glow = k.color("core", k.mainColor("cyan"))
        let metal = k.accentColor("silver")
        k.add("base", "cylinder", at: v3(0, 0.03, 0), size: v3(0.5, 0.06, 0.5), color: "darkgray", material: "metal")
        k.add("ring", "torus", at: v3(0, 0.1, 0), size: v3(0.46, 0.06, 0.46), color: metal, material: "chrome")
        k.add("ring", "torus", at: v3(0, 0.12, 0), size: v3(0.3, 0.04, 0.3), color: glow, material: "emissive")
        k.ring("coil", "roundedCube", count: 10, at: v3(0, 0.12, 0.18), size: v3(0.05, 0.05, 0.06), color: metal, material: "metal", param: 0.4)
        k.add("core", "sphere", at: v3(0, 0.16, 0), size: v3(0.14, 0.14, 0.14), color: glow, material: "emissive")
        if k.keeps("dome") {
            k.add("dome", "hemisphere", at: v3(0, 0.18, 0), size: v3(0.34, 0.18, 0.34), color: "cyan", material: "glass")
        }
        k.handle("body")
        return "Arc reactor"
    }

    /// Placeholder for objects the library does not know (used only when no language model can design them).
    static func abstractSculpture(_ brief: DesignBrief) -> ModelSpec {
        let main = brief.colors["main"] ?? "cyan"
        let accent = brief.colors["accent"] ?? "gold"
        var name = brief.subjectPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.count > 40 { name = brief.korean ? "조형물" : "Sculpture" }
        return ModelSpec(name: name, parts: [
            ModelSpec.Part(name: "base", shape: "cylinder", position: v3(0, 0.05, 0), size: v3(0.4, 0.1, 0.4), color: "darkgray", material: "metal"),
            ModelSpec.Part(name: "ring", shape: "torus", position: v3(0, 0.35, 0), size: v3(0.32, 0.06, 0.32), rotation: v3(70, 0, 0), color: main, material: "chrome"),
            ModelSpec.Part(name: "core", shape: "sphere", position: v3(0, 0.35, 0), size: v3(0.16, 0.16, 0.16), color: accent, material: "emissive"),
            ModelSpec.Part(name: "spire", shape: "cone", position: v3(0, 0.58, 0), size: v3(0.08, 0.2, 0.08), color: main, material: "metal"),
            ModelSpec.Part(name: "stand", shape: "cylinder", position: v3(0, 0.17, 0), size: v3(0.04, 0.16, 0.04), color: "silver", material: "metal"),
        ])
    }
}

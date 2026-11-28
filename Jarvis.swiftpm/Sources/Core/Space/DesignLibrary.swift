import Foundation

/// Parametric designs for common objects. Every builder reads the brief, so the
/// details of the request (colours of each part, how many wheels/legs/floors/towers,
/// materials, sizes, style, extra parts, parts to leave out) shape the model.
/// Proportions follow the real objects; models are about 0.5–1.5 m unless a size is asked for.
enum DesignLibrary {
    typealias Builder = (inout DesignKit) -> String

    static let builders: [String: Builder] = [
        "car": car, "robot": robot, "helmet": helmet, "house": house, "building": building, "castle": castle,
        "tower": tower, "tree": tree, "flower": flower, "rocket": rocket, "spaceship": spaceship, "airplane": airplane,
        "helicopter": helicopter, "drone": drone, "boat": boat, "table": table, "chair": chair, "sofa": sofa, "bed": bed,
        "lamp": lamp, "mug": mug, "bottle": bottle, "snowman": snowman, "sword": sword, "shield": shield, "crown": crown,
        "computer": computer, "windmill": windmill, "reactor": reactor, "bridge": bridge,
    ]

    static var subjects: [String] { builders.keys.sorted() }

    struct Result {
        var spec: ModelSpec
        /// Requested components the design includes.
        var handled: Set<String>
        /// Requested components the library could not add (left to the language model or reported).
        var unhandled: [String]
        /// How many of each repeated part the design used (wheels, legs, floors, …).
        var counts: [String: Int]
    }

    /// A parametric design for the brief's subject, or nil when the library has none.
    static func design(_ brief: DesignBrief) -> Result? {
        guard let subject = brief.subject, let builder = builders[subject] else { return nil }
        var kit = DesignKit(brief)
        let name = builder(&kit)
        var spec = kit.spec
        spec.name = name
        // Colours and materials asked for parts the builder did not style itself ("red arms").
        for (component, color) in brief.colors where component != "main" && component != "accent" && !kit.usage.colored.contains(component) {
            for i in spec.parts.indices where spec.parts[i].isComponent(component) { spec.parts[i].color = color }
        }
        for (component, material) in brief.materials where component != "main" && !kit.usage.materials.contains(component) {
            for i in spec.parts.indices where spec.parts[i].isComponent(component) { spec.parts[i].material = material }
        }
        let unhandled = brief.features.filter { !kit.handled.contains($0) && !generic.contains($0) }
        return Result(spec: spec, handled: kit.handled, unhandled: unhandled, counts: kit.usage.counts)
    }

    static func build(_ brief: DesignBrief) -> ModelSpec? { design(brief)?.spec }

    /// Components that describe the object as a whole rather than a part to add.
    static let generic: Set<String> = ["body", "trim", "floor", "base"]

    // MARK: - Vehicles

    static func car(_ k: inout DesignKit) -> String {
        let request = k.brief.request.lowercased()
        if k.variant == "truck" { return truck(&k, pickup: request.contains("pickup") || request.contains("픽업"),
                                               fire: request.contains("fire") || request.contains("소방")) }
        if k.variant == "bus" { return bus(&k) }
        let sports = k.variant == "sports"
        let suv = k.variant == "suv" || k.variant == "van"
        let police = k.variant == "police", taxi = k.variant == "taxi"
        let L: Float = sports ? 1.06 : 1.0
        let W: Float = sports ? 0.5 : 0.46
        let wheelD: Float = suv ? 0.27 : (sports ? 0.25 : 0.24)
        let clearance: Float = suv ? 0.1 : (sports ? 0.05 : 0.065)
        let bodyH: Float = sports ? 0.13 : (suv ? 0.22 : 0.17)
        let bodyTop = clearance + bodyH
        let fallback = sports ? "red" : (suv ? "darkgreen" : (police ? "white" : (taxi ? "yellow" : "blue")))
        let paint = k.mainColor(fallback)
        let finish = k.mainMaterial("paint")
        let glass = k.color("window", "navy")
        k.add("body", "roundedCube", at: v3(0, clearance + bodyH / 2, 0), size: v3(W, bodyH, L), color: paint, material: finish, param: 0.45)

        // Cabin: roof block, sloped windscreen and rear window, side glass.
        let cabinL: Float = sports ? 0.36 : (suv ? 0.58 : 0.44)
        let cabinH: Float = sports ? 0.11 : (suv ? 0.19 : 0.15)
        let cabinW = W * 0.86
        let cabinZ: Float = sports ? -0.07 : (suv ? -0.1 : -0.05)
        let cabinY = bodyTop + cabinH / 2 - 0.004
        if k.keeps("roof") {
            k.add("roof", "roundedCube", at: v3(0, cabinY, cabinZ), size: v3(cabinW, cabinH, cabinL), color: k.color("roof", paint), material: finish, param: 0.35)
        }
        let screenL: Float = sports ? 0.2 : (suv ? 0.1 : 0.15)
        k.add("window", "wedge", at: v3(0, cabinY, cabinZ + cabinL / 2 + screenL / 2 - 0.01), size: v3(cabinW * 0.97, cabinH * 0.96, screenL),
              color: glass, material: "glass")
        let rearL: Float = sports ? 0.17 : (suv ? 0.035 : 0.11)
        k.add("window", "wedge", at: v3(0, cabinY, cabinZ - cabinL / 2 - rearL / 2 + 0.01), size: v3(cabinW * 0.97, cabinH * 0.96, rearL),
              rot: v3(0, 180, 0), color: glass, material: "glass")
        k.pair("window", "cube", at: v3(cabinW / 2 + 0.003, cabinY + 0.006, cabinZ), size: v3(0.006, cabinH * 0.62, cabinL * 0.86), color: glass, material: "glass")

        // Wheels on as many axles as requested.
        let wheels = k.count("wheel", 4, 3...12)
        let tire = "black"
        let wheelColor = k.brief.colors["wheel"]
        let rim = wheelColor == nil || wheelColor == "black" ? (wheelColor == "black" ? "darkgray" : "silver") : wheelColor!
        let front = L / 2 - 0.2 * L, rear = -L / 2 + 0.19 * L
        let x = W / 2 - 0.03
        if wheels == 3 {
            k.wheel(at: v3(0, wheelD / 2, front), diameter: wheelD, width: 0.07, tire: tire, rim: rim)
            k.wheel(at: v3(x, wheelD / 2, rear), diameter: wheelD, width: 0.07, tire: tire, rim: rim)
            k.wheel(at: v3(-x, wheelD / 2, rear), diameter: wheelD, width: 0.07, tire: tire, rim: rim)
        } else {
            for z in axles(count: (wheels + 1) / 2, front: front, rear: rear, spacing: wheelD * 1.12) {
                k.wheel(at: v3(x, wheelD / 2, z), diameter: wheelD, width: sports ? 0.085 : 0.075, tire: tire, rim: rim)
                k.wheel(at: v3(-x, wheelD / 2, z), diameter: wheelD, width: sports ? 0.085 : 0.075, tire: tire, rim: rim)
            }
        }

        // Lights, grille, bumpers, mirrors, handles.
        let lamp = k.color("light", "white")
        k.pair("light", "roundedCube", at: v3(W / 2 - 0.085, bodyTop - 0.045, L / 2 - 0.004), size: v3(0.1, sports ? 0.024 : 0.036, 0.02),
               color: lamp, material: "emissive")
        k.pair("tail light", "roundedCube", at: v3(W / 2 - 0.07, bodyTop - 0.04, -L / 2 + 0.004), size: v3(0.09, 0.03, 0.02), color: "red", material: "emissive")
        k.add("grille", "cube", at: v3(0, clearance + bodyH * 0.42, L / 2 + 0.001), size: v3(W * 0.38, 0.045, 0.012), color: "darkgray", material: "metal")
        let bumper = sports ? paint : "darkgray"
        k.add("bumper", "roundedCube", at: v3(0, clearance + 0.022, L / 2 - 0.012), size: v3(W * 1.01, 0.045, 0.06), color: bumper, material: "plastic")
        k.add("bumper", "roundedCube", at: v3(0, clearance + 0.022, -L / 2 + 0.012), size: v3(W * 1.01, 0.045, 0.06), color: bumper, material: "plastic")
        k.pair("mirror", "roundedCube", at: v3(cabinW / 2 + 0.03, bodyTop + 0.03, cabinZ + cabinL / 2 - 0.02), size: v3(0.05, 0.03, 0.025),
               color: paint, material: finish)
        k.pair("handle", "cube", at: v3(W / 2 + 0.002, bodyTop - 0.04, 0.03), size: v3(0.006, 0.012, 0.045), color: "silver", material: "chrome")

        if k.wants("spoiler") || (sports && k.keeps("spoiler")) {
            let wing = k.color("spoiler", sports ? "black" : paint)
            k.add("spoiler", "roundedCube", at: v3(0, bodyTop + 0.075, -L / 2 + 0.07), size: v3(W * 0.86, 0.016, 0.1), color: wing, material: "paint", param: 0.5)
            k.pair("spoiler post", "cube", at: v3(W * 0.3, bodyTop + 0.035, -L / 2 + 0.07), size: v3(0.02, 0.07, 0.03), color: wing, material: "paint")
        }
        if sports || k.wants("exhaust") {
            k.pair("exhaust", "cylinder", at: v3(0.1, clearance + 0.035, -L / 2 - 0.012), size: v3(0.035, 0.05, 0.035), rot: v3(90, 0, 0),
                   color: "silver", material: "chrome")
        }
        if k.wants("stripe") {
            let stripe = k.color("stripe", k.accentColor("white"))
            k.pair("stripe", "cube", at: v3(0.05, bodyTop + 0.002, 0), size: v3(0.035, 0.004, L * 0.97), color: stripe, material: "paint")
            if k.keeps("roof") {
                k.pair("stripe", "cube", at: v3(0.05, cabinY + cabinH / 2 + 0.002, cabinZ), size: v3(0.035, 0.004, cabinL * 0.9), color: stripe, material: "paint")
            }
        }
        if let trim = k.brief.colors["accent"] ?? k.brief.colors["trim"] {
            k.pair("trim", "cube", at: v3(W / 2 + 0.002, clearance + 0.02, 0), size: v3(0.006, 0.022, L * 0.62), color: trim, material: "paint")
        }
        if police || k.wants("siren") {
            k.add("siren", "roundedCube", at: v3(0.04, cabinY + cabinH / 2 + 0.018, cabinZ), size: v3(0.08, 0.03, 0.06), color: "red", material: "emissive")
            k.add("siren", "roundedCube", at: v3(-0.04, cabinY + cabinH / 2 + 0.018, cabinZ), size: v3(0.08, 0.03, 0.06), color: "blue", material: "emissive")
        }
        if taxi {
            k.add("sign", "roundedCube", at: v3(0, cabinY + cabinH / 2 + 0.022, cabinZ), size: v3(0.16, 0.04, 0.06), color: "white", material: "emissive")
        }
        if suv {
            k.pair("roof rail", "cube", at: v3(cabinW / 2 - 0.03, cabinY + cabinH / 2 + 0.012, cabinZ), size: v3(0.015, 0.015, cabinL * 0.9), color: "darkgray", material: "metal")
            k.add("spare wheel", "torus", at: v3(0, clearance + bodyH * 0.6, -L / 2 - 0.03), size: v3(wheelD * 0.9, 0.06, wheelD * 0.9), rot: v3(90, 0, 0),
                  color: "black", material: "rubber")
        }
        if k.wants("antenna") {
            k.add("antenna", "cylinder", at: v3(-0.08, cabinY + cabinH / 2 + 0.08, cabinZ - cabinL / 2 + 0.04), size: v3(0.006, 0.16, 0.006), color: "black", material: "metal")
        }
        k.handle("body")
        if police { return "Police car" }
        if taxi { return "Taxi" }
        return sports ? "Sports car" : (suv ? "SUV" : "Car")
    }

    /// Axle positions from front to rear; extra axles are added towards the rear.
    static func axles(count: Int, front: Float, rear: Float, spacing: Float) -> [Float] {
        let n = Swift.max(2, count)
        var zs: [Float] = [front]
        if n == 2 { return [front, rear] }
        let rearAxles = n - 1
        for i in 0..<rearAxles { zs.append(rear + Float(i) * spacing) }
        return zs
    }

    static func truck(_ k: inout DesignKit, pickup: Bool, fire: Bool) -> String {
        let W: Float = 0.5
        let wheelD: Float = 0.26
        let clearance: Float = 0.1
        let paint = k.mainColor(fire ? "red" : (pickup ? "blue" : "white"))
        let cabColor = k.color("cabin", k.brief.colors["main"] ?? (fire ? "red" : (pickup ? paint : "orange")))
        let glass = k.color("window", "navy")
        let L: Float = pickup ? 1.05 : 1.4
        let cabL: Float = 0.38
        let cabZ = L / 2 - cabL / 2
        let cabH: Float = 0.34
        k.add("body", "roundedCube", at: v3(0, clearance + 0.06, 0), size: v3(W * 0.9, 0.1, L), color: "darkgray", material: "metal", param: 0.3)
        k.add("cabin", "roundedCube", at: v3(0, clearance + 0.11 + cabH / 2, cabZ), size: v3(W, cabH, cabL), color: cabColor, material: "paint", param: 0.3)
        k.pane(at: v3(0, clearance + 0.11 + cabH * 0.68, L / 2 + 0.004), width: W * 0.86, height: cabH * 0.38, color: glass)
        k.pair("window", "cube", at: v3(W / 2 + 0.003, clearance + 0.11 + cabH * 0.68, cabZ + 0.04), size: v3(0.006, cabH * 0.34, cabL * 0.5), color: glass, material: "glass")
        let bedL = L - cabL - 0.02
        let bedZ = -L / 2 + bedL / 2
        if pickup {
            k.add("cargo bed", "cube", at: v3(0, clearance + 0.13, bedZ), size: v3(W, 0.03, bedL), color: paint, material: "paint")
            k.pair("cargo wall", "cube", at: v3(W / 2 - 0.01, clearance + 0.21, bedZ), size: v3(0.02, 0.16, bedL), color: paint, material: "paint")
            k.add("tailgate", "cube", at: v3(0, clearance + 0.21, -L / 2 + 0.01), size: v3(W, 0.16, 0.02), color: paint, material: "paint")
        } else {
            let boxColor = fire ? "red" : k.color("cargo", paint)
            k.add("cargo box", "roundedCube", at: v3(0, clearance + 0.11 + 0.24, bedZ), size: v3(W * 1.04, 0.48, bedL), color: boxColor, material: "paint", param: 0.15)
            if fire {
                k.add("ladder", "cube", at: v3(0, clearance + 0.62, bedZ + 0.05), size: v3(0.14, 0.03, bedL * 1.05), color: "silver", material: "metal")
                k.pair("stripe", "cube", at: v3(W * 0.52 + 0.003, clearance + 0.3, bedZ), size: v3(0.006, 0.04, bedL * 0.9), color: "white", material: "emissive")
            }
        }
        let wheels = k.count("wheel", pickup ? 4 : 6, 4...12)
        let front = L / 2 - 0.2, rear = -L / 2 + 0.22
        for z in axles(count: (wheels + 1) / 2, front: front, rear: rear, spacing: wheelD * 1.08) {
            k.wheel(at: v3(W / 2 - 0.035, wheelD / 2, z), diameter: wheelD, width: 0.08, tire: "black", rim: k.color("wheel", "silver"))
            k.wheel(at: v3(-(W / 2 - 0.035), wheelD / 2, z), diameter: wheelD, width: 0.08, tire: "black", rim: k.color("wheel", "silver"))
        }
        k.pair("light", "roundedCube", at: v3(W / 2 - 0.07, clearance + 0.16, L / 2 + 0.004), size: v3(0.08, 0.04, 0.02), color: k.color("light", "white"), material: "emissive")
        k.add("grille", "cube", at: v3(0, clearance + 0.17, L / 2 + 0.003), size: v3(W * 0.42, 0.07, 0.012), color: "silver", material: "chrome")
        k.add("bumper", "roundedCube", at: v3(0, clearance + 0.05, L / 2 + 0.01), size: v3(W * 1.02, 0.05, 0.05), color: "darkgray", material: "metal")
        if fire || k.wants("siren") {
            k.add("siren", "roundedCube", at: v3(0, clearance + 0.11 + cabH + 0.02, cabZ), size: v3(W * 0.6, 0.035, 0.06), color: "red", material: "emissive")
        }
        k.pair("mirror", "roundedCube", at: v3(W / 2 + 0.014, clearance + 0.32, cabZ + cabL / 2 - 0.03), size: v3(0.03, 0.08, 0.02), color: "black", material: "plastic")
        k.handle("body", "cabin")
        return fire ? "Fire truck" : (pickup ? "Pickup truck" : "Truck")
    }

    static func bus(_ k: inout DesignKit) -> String {
        let W: Float = 0.5, H: Float = 0.5, L: Float = 1.6
        let clearance: Float = 0.08
        let paint = k.mainColor("yellow")
        let glass = k.color("window", "navy")
        k.add("body", "roundedCube", at: v3(0, clearance + H / 2, 0), size: v3(W, H, L), color: paint, material: "paint", param: 0.25)
        let windows = k.count("window", 6, 2...10)
        let span = L * 0.78
        for i in 0..<windows {
            let z = -span / 2 + span * (Float(i) + 0.5) / Float(windows) - 0.04
            k.pair("window", "cube", at: v3(W / 2 + 0.003, clearance + H * 0.68, z), size: v3(0.006, H * 0.3, span / Float(windows) * 0.82), color: glass, material: "glass")
        }
        k.pane(at: v3(0, clearance + H * 0.62, L / 2 + 0.004), width: W * 0.86, height: H * 0.42, color: glass)
        k.pane(at: v3(0, clearance + H * 0.66, -L / 2 - 0.004), width: W * 0.7, height: H * 0.3, color: glass)
        k.add("door", "cube", at: v3(W / 2 + 0.004, clearance + H * 0.42, L / 2 - 0.17), size: v3(0.008, H * 0.72, 0.13), color: glass, material: "glass")
        k.pair("stripe", "cube", at: v3(W / 2 + 0.003, clearance + H * 0.38, -0.05), size: v3(0.006, 0.02, L * 0.8), color: k.accentColor("black"), material: "paint")
        let wheels = k.count("wheel", 4, 4...10)
        let d: Float = 0.24
        for z in axles(count: wheels / 2, front: L / 2 - 0.3, rear: -L / 2 + 0.3, spacing: d * 1.1) {
            k.wheel(at: v3(W / 2 - 0.035, d / 2, z), diameter: d, width: 0.08, tire: "black", rim: k.color("wheel", "silver"))
            k.wheel(at: v3(-(W / 2 - 0.035), d / 2, z), diameter: d, width: 0.08, tire: "black", rim: k.color("wheel", "silver"))
        }
        k.pair("light", "roundedCube", at: v3(W / 2 - 0.07, clearance + 0.08, L / 2 + 0.004), size: v3(0.08, 0.04, 0.02), color: k.color("light", "white"), material: "emissive")
        k.pair("tail light", "roundedCube", at: v3(W / 2 - 0.06, clearance + 0.1, -L / 2 - 0.004), size: v3(0.06, 0.06, 0.02), color: "red", material: "emissive")
        k.add("bumper", "roundedCube", at: v3(0, clearance + 0.02, L / 2 + 0.01), size: v3(W, 0.04, 0.04), color: "black", material: "plastic")
        k.add("bumper", "roundedCube", at: v3(0, clearance + 0.02, -L / 2 - 0.01), size: v3(W, 0.04, 0.04), color: "black", material: "plastic")
        k.handle("body")
        return "Bus"
    }

    // MARK: - Aircraft and spacecraft

    static func airplane(_ k: inout DesignKit) -> String {
        if k.variant == "fighter" { return fighter(&k) }
        let body = k.mainColor("white")
        let livery = k.accentColor("blue")
        let y: Float = 0.3
        k.add("body", "capsule", at: v3(0, y, 0), size: v3(0.16, 1.3, 0.16), rot: v3(90, 0, 0), color: body, material: "paint")
        k.add("cockpit", "cube", at: v3(0, y + 0.045, 0.6), size: v3(0.09, 0.03, 0.006), rot: v3(-35, 0, 0), color: "black", material: "glass")
        k.pair("window", "cube", at: v3(0.081, y + 0.018, 0.05), size: v3(0.004, 0.022, 0.92), color: k.color("window", "navy"), material: "glass")
        let wing = k.color("wing", body)
        k.pair("wing", "roundedCube", at: v3(0.34, y - 0.03, -0.02), size: v3(0.58, 0.022, 0.2), rot: v3(0, 18, 4), color: wing, material: "paint", param: 0.6)
        k.pair("stabilizer", "roundedCube", at: v3(0.14, y + 0.03, -0.58), size: v3(0.22, 0.016, 0.1), rot: v3(0, 20, 0), color: wing, material: "paint", param: 0.6)
        k.add("tail", "wedge", at: v3(0, y + 0.17, -0.56), size: v3(0.016, 0.24, 0.26), color: k.color("tail", livery), material: "paint")
        k.pair("stripe", "cube", at: v3(0.0805, y - 0.025, 0.05), size: v3(0.004, 0.012, 1.0), color: livery, material: "paint")
        let engines = k.count("engine", 2, 0...4)
        let slots: [(Float, Float)] = [(0.27, 0.07), (0.45, 0.01)]
        for i in 0..<(engines + 1) / 2 {
            let (ex, ez) = slots[Swift.min(i, 1)]
            k.pair("engine", "cylinder", at: v3(ex, y - 0.075, ez), size: v3(0.075, 0.2, 0.075), rot: v3(90, 0, 0), color: k.color("engine", body), material: "metal")
            k.pair("engine intake", "cylinder", at: v3(ex, y - 0.075, ez + 0.101), size: v3(0.06, 0.006, 0.06), rot: v3(90, 0, 0), color: "darkgray", material: "metal")
            k.pair("pylon", "cube", at: v3(ex, y - 0.042, ez - 0.02), size: v3(0.015, 0.03, 0.08), color: "gray", material: "metal")
        }
        // Landing gear: struts from the wheel axles up into the fuselage (bottom at y - 0.08).
        let belly = y - 0.07
        k.add("gear", "cylinder", at: v3(0, (0.03 + belly) / 2, 0.45), size: v3(0.012, belly - 0.03, 0.012), color: "gray", material: "metal")
        k.add("gear wheel", "cylinder", at: v3(0, 0.03, 0.45), size: v3(0.06, 0.025, 0.06), rot: v3(0, 0, 90), color: "black", material: "rubber")
        k.pair("gear", "cylinder", at: v3(0.06, (0.035 + belly) / 2, -0.05), size: v3(0.014, belly - 0.035, 0.014), color: "gray", material: "metal")
        k.pair("gear wheel", "cylinder", at: v3(0.06, 0.035, -0.05), size: v3(0.07, 0.035, 0.07), rot: v3(0, 0, 90), color: "black", material: "rubber")
        if k.wants("propeller") {
            k.add("propeller", "cube", at: v3(0, y, 0.67), size: v3(0.36, 0.03, 0.01), color: "darkgray", material: "metal")
            k.add("propeller", "cube", at: v3(0, y, 0.67), size: v3(0.03, 0.36, 0.01), color: "darkgray", material: "metal")
        }
        k.handle("body")
        return "Airliner"
    }

    static func fighter(_ k: inout DesignKit) -> String {
        let body = k.mainColor("gray")
        let dark = k.accentColor("darkgray")
        let y: Float = 0.22
        k.add("body", "roundedCube", at: v3(0, y, 0), size: v3(0.16, 0.12, 1.0), color: body, material: "metal", param: 0.6)
        k.add("nose", "ogive", at: v3(0, y, 0.65), size: v3(0.13, 0.32, 0.11), rot: v3(90, 0, 0), color: body, material: "metal")
        k.add("cockpit", "hemisphere", at: v3(0, y + 0.07, 0.3), size: v3(0.11, 0.08, 0.3), color: k.color("cockpit", "gold"), material: "glass")
        k.pair("wing", "wedge", at: v3(0.25, y - 0.02, -0.12), size: v3(0.02, 0.42, 0.55), rot: v3(0, 0, -90), color: k.color("wing", body), material: "metal")
        k.pair("tail", "wedge", at: v3(0.08, y + 0.13, -0.4), size: v3(0.014, 0.18, 0.2), rot: v3(0, 0, -12), color: dark, material: "metal")
        k.pair("intake", "roundedCube", at: v3(0.1, y - 0.01, 0.08), size: v3(0.06, 0.08, 0.3), color: dark, material: "metal", param: 0.4)
        k.add("engine", "cylinder", at: v3(0, y, -0.52), size: v3(0.1, 0.06, 0.1), rot: v3(90, 0, 0), color: "darkgray", material: "metal")
        if k.futuristic || k.wants("engine") {
            k.add("flame", "cone", at: v3(0, y, -0.62), size: v3(0.08, 0.16, 0.08), rot: v3(-90, 0, 0), color: "orange", material: "emissive")
        }
        if k.wants("cannon") {
            k.pair("cannon", "cylinder", at: v3(0.45, y - 0.03, -0.05), size: v3(0.02, 0.3, 0.02), rot: v3(90, 0, 0), color: "darkgray", material: "metal")
        }
        k.add("gear", "cylinder", at: v3(0, y - 0.12, 0.35), size: v3(0.012, 0.12, 0.012), color: "gray", material: "metal")
        k.pair("gear", "cylinder", at: v3(0.12, y - 0.12, -0.15), size: v3(0.012, 0.12, 0.012), color: "gray", material: "metal")
        k.add("gear wheel", "cylinder", at: v3(0, 0.03, 0.35), size: v3(0.05, 0.02, 0.05), rot: v3(0, 0, 90), color: "black", material: "rubber")
        k.pair("gear wheel", "cylinder", at: v3(0.12, 0.03, -0.15), size: v3(0.06, 0.03, 0.06), rot: v3(0, 0, 90), color: "black", material: "rubber")
        k.handle("body")
        return "Fighter jet"
    }

    static func helicopter(_ k: inout DesignKit) -> String {
        let body = k.mainColor("red")
        let y: Float = 0.27
        k.add("body", "sphere", at: v3(0, y, 0.05), size: v3(0.34, 0.3, 0.52), color: body, material: "paint")
        k.add("window", "hemisphere", at: v3(0, y + 0.03, 0.2), size: v3(0.28, 0.16, 0.24), rot: v3(90, 0, 0), color: k.color("window", "cyan"), material: "glass")
        k.add("tail boom", "cylinder", at: v3(0, y + 0.04, -0.5), size: v3(0.07, 0.62, 0.07), rot: v3(90, 0, 0), color: body, material: "paint")
        k.add("tail", "wedge", at: v3(0, y + 0.12, -0.78), size: v3(0.012, 0.16, 0.14), color: k.accentColor(body), material: "paint")
        k.add("tail rotor", "cube", at: v3(0.03, y + 0.1, -0.79), size: v3(0.006, 0.16, 0.02), color: "darkgray", material: "metal")
        k.add("tail rotor", "cube", at: v3(0.03, y + 0.1, -0.79), size: v3(0.006, 0.02, 0.16), color: "darkgray", material: "metal")
        k.add("mast", "cylinder", at: v3(0, y + 0.18, 0), size: v3(0.035, 0.09, 0.035), color: "darkgray", material: "metal")
        k.add("rotor hub", "cylinder", at: v3(0, y + 0.23, 0), size: v3(0.07, 0.03, 0.07), color: "darkgray", material: "metal")
        let blades = k.count("propeller", 4, 2...6)
        k.ring("propeller", "cube", count: blades, at: v3(0, y + 0.235, 0.29), size: v3(0.05, 0.008, 0.52), color: k.color("propeller", "darkgray"), material: "metal")
        k.pair("gear", "cylinder", at: v3(0.15, 0.015, 0.02), size: v3(0.025, 0.62, 0.025), rot: v3(90, 0, 0), color: "darkgray", material: "metal")
        k.pair("gear strut", "cylinder", at: v3(0.13, 0.08, 0.14), size: v3(0.016, 0.13, 0.016), rot: v3(0, 0, -12), color: "darkgray", material: "metal")
        k.pair("gear strut", "cylinder", at: v3(0.13, 0.08, -0.1), size: v3(0.016, 0.13, 0.016), rot: v3(0, 0, -12), color: "darkgray", material: "metal")
        k.handle("body")
        return "Helicopter"
    }

    static func drone(_ k: inout DesignKit) -> String {
        let body = k.mainColor("white")
        let accent = k.accentColor("darkgray")
        let rotors = k.count("propeller", 4, 3...8)
        k.add("body", "roundedCube", at: v3(0, 0.12, 0), size: v3(0.2, 0.07, 0.22), color: body, material: "plastic", param: 0.6)
        k.add("cover", "hemisphere", at: v3(0, 0.175, 0), size: v3(0.14, 0.04, 0.16), color: accent, material: "plastic")
        let phase: Float = rotors == 4 ? 45 : 0
        k.ring("arm", "roundedCube", count: rotors, at: v3(0, 0.13, 0.17), size: v3(0.035, 0.022, 0.24), color: accent, material: "plastic", phase: phase)
        k.ring("motor", "cylinder", count: rotors, at: v3(0, 0.155, 0.29), size: v3(0.05, 0.045, 0.05), color: "darkgray", material: "metal", phase: phase)
        k.ring("propeller", "cylinder", count: rotors, at: v3(0, 0.182, 0.29), size: v3(0.2, 0.004, 0.2), color: k.color("propeller", "gray"), material: "glass", phase: phase)
        k.pair("gear", "cube", at: v3(0.07, 0.05, 0), size: v3(0.012, 0.09, 0.012), color: accent, material: "plastic")
        k.pair("gear", "cylinder", at: v3(0.07, 0.006, 0), size: v3(0.012, 0.2, 0.012), rot: v3(90, 0, 0), color: accent, material: "plastic")
        k.add("camera", "sphere", at: v3(0, 0.07, 0.08), size: v3(0.06, 0.06, 0.06), color: "black", material: "plastic")
        k.add("camera lens", "cylinder", at: v3(0, 0.07, 0.11), size: v3(0.03, 0.012, 0.03), rot: v3(90, 0, 0), color: "navy", material: "glass")
        k.pair("light", "sphere", at: v3(0.06, 0.12, 0.112), size: v3(0.02, 0.02, 0.02), color: k.color("light", "white"), material: "emissive")
        k.pair("tail light", "sphere", at: v3(0.06, 0.12, -0.112), size: v3(0.02, 0.02, 0.02), color: "red", material: "emissive")
        k.handle("body")
        return "Drone"
    }

    static func spaceship(_ k: inout DesignKit) -> String {
        if k.variant == "ufo" {
            let hull = k.mainColor("silver")
            k.add("body", "sphere", at: v3(0, 0.2, 0), size: v3(0.8, 0.12, 0.8), color: hull, material: "chrome")
            k.add("upper hull", "hemisphere", at: v3(0, 0.29, 0), size: v3(0.5, 0.12, 0.5), color: hull, material: "chrome")
            k.add("cockpit", "hemisphere", at: v3(0, 0.39, 0), size: v3(0.28, 0.14, 0.28), color: k.color("cockpit", k.color("window", "cyan")), material: "glass")
            k.ring("light", "sphere", count: k.count("light", 10, 4...24), at: v3(0, 0.2, 0.395), size: v3(0.035, 0.035, 0.035),
                   color: k.color("light", "cyan"), material: "emissive")
            k.add("beam emitter", "cylinder", at: v3(0, 0.135, 0), size: v3(0.2, 0.02, 0.2), color: k.accentColor("cyan"), material: "emissive")
            k.ring("leg", "capsule", count: k.count("leg", 3, 0...8), at: v3(0, 0.08, 0.24), size: v3(0.025, 0.18, 0.025), rot: v3(-20, 0, 0),
                   color: "darkgray", material: "metal")
            k.handle("body")
            return "Flying saucer"
        }
        let hull = k.mainColor("white")
        let accent = k.accentColor("navy")
        let y: Float = 0.2
        k.add("body", "roundedCube", at: v3(0, y, 0), size: v3(0.22, 0.12, 0.8), color: hull, material: "paint", param: 0.5)
        k.add("nose", "ogive", at: v3(0, y, 0.55), size: v3(0.2, 0.3, 0.11), rot: v3(90, 0, 0), color: hull, material: "paint")
        k.add("cockpit", "hemisphere", at: v3(0, y + 0.06, 0.26), size: v3(0.13, 0.08, 0.24), color: k.color("cockpit", k.color("window", "cyan")), material: "glass")
        k.pair("wing", "wedge", at: v3(0.3, y - 0.03, -0.1), size: v3(0.03, 0.42, 0.45), rot: v3(0, 0, -90), color: k.color("wing", hull), material: "paint")
        k.pair("stripe", "cube", at: v3(0.112, y, 0.05), size: v3(0.006, 0.025, 0.6), color: accent, material: "paint")
        k.add("tail", "wedge", at: v3(0, y + 0.13, -0.3), size: v3(0.02, 0.16, 0.22), color: accent, material: "paint")
        let engines = k.count("engine", 2, 1...6)
        let glow = k.color("light", "cyan")
        for i in 0..<engines {
            let x = (Float(i) - Float(engines - 1) / 2) * 0.12
            k.add("engine", "cylinder", at: v3(x, y, -0.43), size: v3(0.1, 0.12, 0.1), rot: v3(90, 0, 0), color: "darkgray", material: "metal")
            k.add("engine glow", "cylinder", at: v3(x, y, -0.495), size: v3(0.08, 0.01, 0.08), rot: v3(90, 0, 0), color: glow, material: "emissive")
        }
        if k.wants("cannon") || k.style("military") {
            k.pair("cannon", "cylinder", at: v3(0.5, y - 0.03, 0.0), size: v3(0.025, 0.32, 0.025), rot: v3(90, 0, 0), color: "darkgray", material: "metal")
        }
        if k.wants("leg") || k.wants("gear") {
            k.pair("gear", "cylinder", at: v3(0.08, 0.07, 0.15), size: v3(0.015, 0.14, 0.015), color: "gray", material: "metal")
            k.pair("gear", "cylinder", at: v3(0.08, 0.07, -0.2), size: v3(0.015, 0.14, 0.015), color: "gray", material: "metal")
        }
        k.handle("body")
        return "Spaceship"
    }

    static func rocket(_ k: inout DesignKit) -> String {
        let body = k.mainColor("white")
        let accent = k.accentColor("red")
        let R: Float = 0.1
        let base: Float = 0.12
        k.add("body", "cylinder", at: v3(0, base + 0.31, 0), size: v3(2 * R, 0.62, 2 * R), color: body, material: "paint")
        k.add("nose", "ogive", at: v3(0, base + 0.62 + 0.13, 0), size: v3(2 * R, 0.26, 2 * R), color: k.color("nose", accent), material: "paint")
        let stages = k.count("stage", 1, 1...4)
        for s in 1..<Swift.max(stages, 1) {
            k.add("stage band", "tube", at: v3(0, base + 0.62 * Float(s) / Float(stages), 0), size: v3(2 * R + 0.006, 0.02, 2 * R + 0.006),
                  color: "black", material: "metal")
        }
        let fins = k.count("fin", 4, 2...8)
        k.ring("fin", "wedge", count: fins, at: v3(0, base + 0.1, R + 0.065), size: v3(0.016, 0.2, 0.13), color: k.color("fin", accent), material: "paint", phase: 45)
        k.add("engine", "frustum", at: v3(0, base - 0.05, 0), size: v3(0.15, 0.1, 0.15), color: "darkgray", material: "metal", param: 0.6)
        if k.wants("engine") || k.futuristic || k.brief.request.lowercased().contains("flame") || k.brief.request.contains("불꽃") {
            k.add("flame", "cone", at: v3(0, base - 0.18, 0), size: v3(0.12, 0.18, 0.12), rot: v3(180, 0, 0), color: "orange", material: "emissive")
        }
        let windows = k.count("porthole", k.count("window", 2, 0...4), 0...4)
        for i in 0..<windows {
            let y = base + 0.48 - Float(i) * 0.12
            k.add("porthole", "cylinder", at: v3(0, y, R), size: v3(0.055, 0.012, 0.055), rot: v3(90, 0, 0), color: k.color("window", "cyan"), material: "glass")
            k.add("porthole frame", "torus", at: v3(0, y, R + 0.002), size: v3(0.068, 0.012, 0.068), rot: v3(90, 0, 0), color: "silver", material: "chrome")
        }
        if (k.brief.counts["engine"] ?? 1) > 1 || k.wants("engine") {
            k.pair("booster", "cylinder", at: v3(R + 0.05, base + 0.16, 0), size: v3(0.08, 0.34, 0.08), color: body, material: "paint")
            k.pair("booster nose", "ogive", at: v3(R + 0.05, base + 0.38, 0), size: v3(0.08, 0.1, 0.08), color: accent, material: "paint")
        }
        k.handle("body")
        return "Rocket"
    }

    // MARK: - Boats

    static func boat(_ k: inout DesignKit) -> String {
        let request = k.brief.request.lowercased()
        let ship = request.contains("ship") || request.contains("선박") || request.contains("크루즈") || request.contains("여객선")
        let sail = k.variant == "sail"
        let hullColor = k.mainColor(ship ? "navy" : "white")
        let W: Float = ship ? 0.42 : 0.38
        let H: Float = ship ? 0.2 : 0.15
        let L: Float = ship ? 1.3 : 0.9
        let sternL = L * 0.6
        let bowL = L - sternL
        k.add("body", "roundedCube", at: v3(0, H / 2, -L / 2 + sternL / 2), size: v3(W, H, sternL), color: hullColor, material: sail ? k.mainMaterial("wood") : "paint", param: 0.25)
        k.add("bow", "prism", at: v3(0, H / 2, L / 2 - bowL / 2 - 0.005), size: v3(W, H, bowL), rot: v3(0, 180, 0), color: hullColor,
              material: sail ? k.mainMaterial("wood") : "paint", param: 3)
        k.pair("stripe", "cube", at: v3(W / 2 + 0.002, H * 0.72, -L / 2 + sternL / 2), size: v3(0.004, 0.025, sternL * 0.95),
               color: k.color("stripe", k.accentColor(ship ? "red" : "blue")), material: "paint")
        k.add("deck", "plane", at: v3(0, H + 0.004, -L / 2 + sternL / 2), size: v3(W * 0.92, 0.008, sternL * 0.94), color: "beige", material: "wood")
        if sail {
            let sailColor = k.color("sail", "white")
            k.add("mast", "cylinder", at: v3(0, H + 0.42, 0.02), size: v3(0.025, 0.84, 0.025), color: "brown", material: "wood")
            k.add("sail", "wedge", at: v3(0, H + 0.38, -0.16), size: v3(0.008, 0.62, 0.34), rot: v3(0, 180, 0), color: sailColor, material: "fabric")
            k.add("sail", "wedge", at: v3(0, H + 0.32, 0.16), size: v3(0.008, 0.52, 0.26), color: sailColor, material: "fabric")
            k.add("boom", "cylinder", at: v3(0, H + 0.07, -0.16), size: v3(0.018, 0.36, 0.018), rot: v3(90, 0, 0), color: "brown", material: "wood")
            k.add("flag", "cube", at: v3(0, H + 0.86, -0.02), size: v3(0.004, 0.05, 0.08), color: k.color("flag", "red"), material: "fabric")
            k.handle("body")
            return "Sailboat"
        }
        if ship {
            k.add("superstructure", "roundedCube", at: v3(0, H + 0.08, -0.15), size: v3(W * 0.8, 0.16, 0.5), color: "white", material: "paint", param: 0.15)
            k.add("superstructure", "roundedCube", at: v3(0, H + 0.2, -0.12), size: v3(W * 0.66, 0.1, 0.32), color: "white", material: "paint", param: 0.15)
            k.pane(at: v3(0, H + 0.21, 0.04 + 0.005), width: W * 0.6, height: 0.04, color: k.color("window", "navy"))
            k.add("funnel", "cylinder", at: v3(0, H + 0.33, -0.22), size: v3(0.08, 0.16, 0.08), color: k.color("funnel", "red"), material: "paint")
            k.add("funnel top", "cylinder", at: v3(0, H + 0.42, -0.22), size: v3(0.082, 0.025, 0.082), color: "black", material: "paint")
            for i in 0..<5 {
                let z = -L / 2 + 0.12 + Float(i) * 0.13
                k.pair("porthole", "cylinder", at: v3(W / 2 + 0.002, H * 0.45, z), size: v3(0.03, 0.006, 0.03), rot: v3(0, 0, 90), color: "cyan", material: "glass")
            }
            k.handle("body")
            return "Ship"
        }
        k.add("cabin", "roundedCube", at: v3(0, H + 0.055, 0.0), size: v3(W * 0.66, 0.1, 0.2), color: "white", material: "paint", param: 0.3)
        k.add("window", "wedge", at: v3(0, H + 0.055, 0.14), size: v3(W * 0.64, 0.09, 0.08), color: k.color("window", "navy"), material: "glass")
        k.add("engine", "roundedCube", at: v3(0, H * 0.8, -L / 2 - 0.03), size: v3(0.08, 0.17, 0.07), color: "black", material: "plastic", param: 0.3)
        k.pair("seat", "roundedCube", at: v3(0.08, H + 0.04, -0.2), size: v3(0.1, 0.06, 0.1), color: k.color("seat", "beige"), material: "fabric", param: 0.5)
        k.handle("body")
        return k.variant == "speed" ? "Speedboat" : "Motorboat"
    }
}

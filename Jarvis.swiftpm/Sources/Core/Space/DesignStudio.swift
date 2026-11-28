import Foundation

/// Text for the language model: how to build objects from parts, and exactly what
/// this request requires (taken from the brief so no detail is lost).
struct DesignPrompt: Equatable {
    var instructions: String
    var prompt: String

    static let guide = """
    You are the 3D design engine of Jarvis. Build the requested object from primitive parts so it is instantly \
    recognisable, correctly proportioned and faithful to every detail the user asked for.
    Coordinates are metres: x right, y up, z toward the viewer; the object's front faces +z; the floor is y = 0. \
    Every part touches another part or the floor; nothing floats.
    Part fields: name (what it is: body, wheel, window, leg, roof…), shape, x/y/z centre, width/height/depth \
    (full size along x/y/z before rotation), rx/ry/rz rotation in degrees, color, material, mirror (true also places \
    a copy at -x), radial (N > 1 repeats the part N times around the vertical axis through x = 0, z = 0; 1 = once).
    Shapes: cube; roundedCube (soft edges, for bodies); sphere (ellipsoid); hemisphere (dome, flat side down); \
    cylinder (upright); tube (hollow); cone; frustum (upright, narrower top); torus (flat ring: width = outer \
    diameter, height = ring thickness); capsule (upright pill); pyramid; wedge (ramp: tall at the back, sloping down \
    to the front, for windscreens, roofs and fins); prism (hexagonal column); halfCylinder (arch lying along x, flat \
    side down); plane (thin panel); cup (open vessel); bowl; bottle; vase; ogive (rounded nose cone).
    Orientation: rotate a cylinder, capsule or cone 90 about x to lie along z, or 90 about z to lie along x. A car \
    wheel is a cylinder with width = depth = diameter and height = tyre width, rotated 90 about z. A torus stands up \
    when rotated 90 about x.
    Materials: paint, plastic, metal, chrome, glass, rubber, wood, stone, fabric, emissive (lights that glow).
    Colors: red, orange, yellow, lime, green, darkgreen, teal, cyan, blue, navy, purple, pink, maroon, white, beige, \
    brown, gold, silver, gray, darkgray, black.
    Use 12 to 24 parts: first the large masses with realistic proportions, then the details that make it \
    recognisable (windows, lights, trims, handles, joints). Make left/right pairs with mirror and repeats with \
    radial instead of listing each copy. Overall size 0.5 to 1.5 metres unless a size is given.
    Example, a desk lamp: base cylinder at (0, 0.015, 0) size 0.2×0.03×0.2 darkgray metal; arm cylinder at \
    (0, 0.17, -0.04) size 0.02×0.31×0.02 rx -15; joint sphere at (0, 0.32, -0.08) size 0.04; upper arm cylinder at \
    (0, 0.37, 0.05) size 0.02×0.28×0.02 rx 62; shade frustum at (0, 0.36, 0.2) size 0.16×0.13×0.16 rx 25 white metal; \
    bulb sphere at (0, 0.31, 0.22) size 0.055 yellow emissive.
    """

    /// The whole object from scratch.
    static func full(_ brief: DesignBrief, feedback: [String] = []) -> DesignPrompt {
        var lines = ["Design: \(brief.request)"]
        lines += requirements(brief)
        lines.append(brief.korean ? "Give the model a short Korean name." : "Give the model a short name.")
        if !feedback.isEmpty {
            lines.append("Your previous design had these problems; fix every one: " + feedback.joined(separator: "; ") + ".")
        }
        return DesignPrompt(instructions: guide, prompt: lines.joined(separator: "\n"))
    }

    /// Only the parts the parametric library could not add, attached to its model.
    static func addOn(to base: ModelSpec, brief: DesignBrief, features: [String]) -> DesignPrompt {
        let b = base.bounds
        func f(_ v: Float) -> String { String(format: "%.2f", v) }
        var lines = ["Request: \(brief.request)",
                     "An existing \(base.name) occupies x \(f(b.min.x))…\(f(b.max.x)), y \(f(b.min.y))…\(f(b.max.y)), z \(f(b.min.z))…\(f(b.max.z)) (front faces +z)."]
        let largest = base.parts.sorted { DesignValidator.volume($0) > DesignValidator.volume($1) }.prefix(8)
        lines.append("Its main parts: " + largest.map { p in
            "\(p.name) at (\(f(p.position.x)), \(f(p.position.y)), \(f(p.position.z))) size \(f(p.size.x))×\(f(p.size.y))×\(f(p.size.z))"
        }.joined(separator: "; ") + ".")
        lines.append("Design ONLY these additional parts, attached to it in the same coordinates: " + features.joined(separator: ", ") + ".")
        lines += requirements(brief).filter { $0.hasPrefix("Colours") || $0.hasPrefix("Materials") || $0.hasPrefix("Style") }
        lines.append("Use 1 to 12 parts named after what they are.")
        return DesignPrompt(instructions: guide, prompt: lines.joined(separator: "\n"))
    }

    /// The brief as explicit requirements.
    static func requirements(_ brief: DesignBrief) -> [String] {
        var lines: [String] = []
        if let subject = brief.subject { lines.append("Object: \(brief.variant.map { "\($0) " } ?? "")\(subject)") }
        var must: [String] = []
        for feature in brief.features where !DesignLibrary.generic.contains(feature) {
            var item = feature
            if let n = brief.counts[feature] { item = "\(n) × \(feature)" }
            if let c = brief.colors[feature] { item += " (\(c))" }
            must.append(item)
        }
        for (component, n) in brief.counts.sorted(by: { $0.key < $1.key }) where !brief.features.contains(component) {
            must.append(component == "floor" ? "\(n) floors/storeys" : "\(n) × \(component)")
        }
        if !must.isEmpty { lines.append("Must include: " + must.joined(separator: "; ") + ".") }
        var colours: [String] = []
        if let m = brief.colors["main"] { colours.append("overall \(m)") }
        if let a = brief.colors["accent"] { colours.append("accents \(a)") }
        for (component, c) in brief.colors.sorted(by: { $0.key < $1.key }) where component != "main" && component != "accent" {
            colours.append("\(component) \(c)")
        }
        if !colours.isEmpty { lines.append("Colours: " + colours.joined(separator: "; ") + ".") }
        let materials = brief.materials.sorted { $0.key < $1.key }.map { "\($0.key == "main" ? "overall" : $0.key) \($0.value)" }
        if !materials.isEmpty { lines.append("Materials: " + materials.joined(separator: "; ") + ".") }
        if !brief.excluded.isEmpty { lines.append("Leave out: " + brief.excluded.joined(separator: ", ") + ".") }
        if let h = brief.height { lines.append(String(format: "Height: %.2f m.", h)) }
        if let l = brief.length { lines.append(String(format: "Length: %.2f m.", l)) }
        if let w = brief.width { lines.append(String(format: "Width: %.2f m.", w)) }
        if let o = brief.overall { lines.append(String(format: "Size: about %.2f m.", o)) }
        if !brief.styles.isEmpty { lines.append("Style: " + brief.styles.joined(separator: ", ") + ".") }
        let names = brief.features.filter { !DesignLibrary.generic.contains($0) }
        if !names.isEmpty { lines.append("Name the parts with these words where they apply: " + names.joined(separator: ", ") + ".") }
        return lines
    }
}

extension ModelSpec.Part {
    /// The part plus the mirror copy and radial repeats a language model asked for.
    func expanded(mirror: Bool, radial: Int) -> [ModelSpec.Part] {
        let n = Swift.min(Swift.max(radial, 1), 24)
        var out: [ModelSpec.Part] = []
        for k in 0..<n {
            let p = n > 1 ? rotatedAboutY(360 * Float(k) / Float(n)) : self
            out.append(p)
            if mirror && abs(p.position.x) > 0.005 { out.append(p.mirroredX()) }
        }
        return out
    }
}

/// Request → brief → design (parametric library, language model, or both) → quality pass.
enum DesignStudio {
    /// Asks the language model for parts; nil when it is unavailable or fails.
    typealias Designer = (DesignPrompt) async -> ModelSpec?

    enum Source: String {
        case library
        case languageModel = "language model"
        case combined = "library + language model"
        case placeholder
    }

    struct Outcome {
        var spec: ModelSpec
        var brief: DesignBrief
        var source: Source
        /// Requested parts the design could not include.
        var unhandled: [String]
        /// Remaining differences from the request (language-model designs).
        var issues: [String]
    }

    static func design(_ brief: DesignBrief, designer: Designer?) async -> Outcome {
        if let library = DesignLibrary.design(brief) {
            var spec = library.spec
            var unhandled = library.unhandled
            var source = Source.library
            if !unhandled.isEmpty, let designer {
                if let extra = await designer(DesignPrompt.addOn(to: spec, brief: brief, features: unhandled)), !extra.parts.isEmpty {
                    let added = attach(extra.sanitized(maxParts: 16).parts, to: spec)
                    spec.parts += added
                    unhandled = unhandled.filter { f in !added.contains { $0.isComponent(f) } }
                    source = .combined
                }
            }
            return Outcome(spec: DesignValidator.finish(spec, brief: brief, fromLanguageModel: false), brief: brief,
                           source: source, unhandled: unhandled, issues: [])
        }
        if let designer {
            var best: ModelSpec?
            var bestIssues: [String] = []
            var feedback: [String] = []
            for _ in 0..<2 {
                guard let raw = await designer(DesignPrompt.full(brief, feedback: feedback)), raw.parts.count >= 3 else { continue }
                let candidate = raw.sanitized()
                let issues = DesignValidator.compliance(candidate, brief: brief)
                if best == nil || issues.count < bestIssues.count {
                    best = candidate
                    bestIssues = issues
                }
                if issues.isEmpty { break }
                feedback = issues
            }
            if let spec = best {
                let final = DesignValidator.finish(spec, brief: brief, fromLanguageModel: true)
                let missing = brief.features.filter { !DesignLibrary.generic.contains($0) && final.parts(of: $0).isEmpty }
                return Outcome(spec: final, brief: brief, source: .languageModel, unhandled: missing,
                               issues: DesignValidator.compliance(final, brief: brief))
            }
        }
        let placeholder = DesignValidator.finish(DesignLibrary.abstractSculpture(brief), brief: brief, fromLanguageModel: false)
        return Outcome(spec: placeholder, brief: brief, source: .placeholder,
                       unhandled: brief.features.filter { !DesignLibrary.generic.contains($0) }, issues: [])
    }

    /// Extra parts from the language model, moved into contact with the base model if they float.
    static func attach(_ extra: [ModelSpec.Part], to base: ModelSpec) -> [ModelSpec.Part] {
        let merged = DesignValidator.connected(ModelSpec(name: base.name, parts: base.parts + extra))
        return Array(merged.parts.suffix(extra.count))
    }
}

/// What Jarvis says about a finished design: the details it honoured, in the user's language.
enum DesignReport {
    static func text(_ o: DesignStudio.Outcome) -> String {
        o.brief.korean ? korean(o) : english(o)
    }

    // MARK: English

    static func english(_ o: DesignStudio.Outcome) -> String {
        let b = o.brief
        var details: [String] = []
        var described = Set<String>()
        for (component, n) in b.counts.sorted(by: { $0.key < $1.key }) {
            let color = b.colors[component].map { "\(colorName($0)) " } ?? ""
            details.append(component == "floor" ? "\(n) \(n == 1 ? "storey" : "storeys")" : "\(n) \(color)\(plural(component, n))")
            described.insert(component)
        }
        for (component, c) in b.colors.sorted(by: { $0.key < $1.key }) where !described.contains(component) && component != "main" && component != "accent" {
            details.append("\(article(colorName(c))) \(colorName(c)) \(component)")
            described.insert(component)
        }
        for feature in b.features where !described.contains(feature) && !DesignLibrary.generic.contains(feature) && !o.unhandled.contains(feature) {
            details.append(article(feature) + " " + feature)
        }
        var head = "I've designed " + article(o.spec.name.lowercased()) + " " + o.spec.name.lowercased()
        if let main = b.colors["main"] { head += " in \(colorName(main))" }
        if let accent = b.colors["accent"] { head += " with \(colorName(accent)) accents" }
        var text = head
        if !details.isEmpty { text += " with " + list(details) }
        text += ", \(o.spec.parts.count) parts in all, sir."
        if !o.unhandled.isEmpty {
            let why = o.source == .placeholder || o.source == .library
                ? "my parts library has no such piece and Apple Intelligence isn't available"
                : "the design engine couldn't place it convincingly"
            text += " I couldn't add the " + list(o.unhandled) + ": " + why + "."
        }
        if o.source == .placeholder {
            text = "I don't have a design for that yet, so I've placed a placeholder sculpture, sir. With Apple Intelligence on, I'll design it part by part."
        }
        return text
    }

    private static func list(_ items: [String]) -> String {
        if items.count <= 1 { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    private static func article(_ word: String) -> String {
        guard let first = word.lowercased().first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }

    private static func plural(_ word: String, _ n: Int) -> String {
        if n == 1 { return word }
        if word.hasSuffix("s") || word.hasSuffix("sh") || word.hasSuffix("ch") { return word + "es" }
        if word.hasSuffix("y") && !"aeiou".contains(word.dropLast().last ?? "a") { return String(word.dropLast()) + "ies" }
        if word == "leaves" { return word }
        return word + "s"
    }

    static func colorName(_ key: String) -> String {
        switch key {
        case "darkgray": return "dark grey"
        case "darkgreen": return "dark green"
        case "gray": return "grey"
        default: return key
        }
    }

    // MARK: Refinements

    /// What a follow-up request changed ("Done, sir: the wheels are now gold and I added a chimney.").
    static func changes(_ edit: DesignBrief, outcome o: DesignStudio.Outcome) -> String {
        let ko = edit.korean
        var items: [String] = []
        var mentioned = Set<String>()
        for (component, color) in edit.colors.sorted(by: { $0.key < $1.key }) where component != "accent" {
            mentioned.insert(component)
            if component == "main" {
                items.append(ko ? "전체 색 \(koreanColor(color))" : "the main colour is now \(colorName(color))")
            } else {
                let many = DesignValidator.countParts(o.spec, component) > 1
                items.append(ko ? "\(koreanColor(color)) \(koreanName(component))"
                                : "the \(many ? plural(component, 2) : component) \(many ? "are" : "is") now \(colorName(color))")
            }
        }
        for (component, n) in edit.counts.sorted(by: { $0.key < $1.key }) {
            mentioned.insert(component)
            items.append(ko ? (component == "floor" ? "\(n)층" : "\(koreanName(component)) \(n)개") : (component == "floor" ? "\(n) storeys" : "\(n) \(plural(component, n))"))
        }
        for (component, f) in edit.scales.sorted(by: { $0.key < $1.key }) {
            mentioned.insert(component)
            items.append(ko ? "\(koreanName(component)) \(f > 1 ? "확대" : "축소")" : "\(f > 1 ? "larger" : "smaller") \(plural(component, 2))")
        }
        for (component, material) in edit.materials.sorted(by: { $0.key < $1.key }) where !mentioned.contains(component) {
            mentioned.insert(component)
            items.append(ko ? "\(koreanName(component)) 재질 \(material)" : "\(component == "main" ? "the whole model" : "the \(component)") in \(material)")
        }
        for f in edit.features where !mentioned.contains(f) && !DesignLibrary.generic.contains(f) && !o.unhandled.contains(f) {
            items.append(ko ? "\(koreanName(f)) 추가" : "I added \(article(f)) \(f)")
        }
        for e in edit.excluded { items.append(ko ? "\(koreanName(e)) 제거" : "I removed the \(e)") }
        if edit.sizeFactor != 1 { items.append(ko ? (edit.sizeFactor > 1 ? "전체 확대" : "전체 축소") : (edit.sizeFactor > 1 ? "the whole model is larger" : "the whole model is smaller")) }
        var text: String
        if items.isEmpty {
            text = ko ? "설계를 다시 다듬었습니다." : "I've refreshed the design, sir."
        } else {
            text = ko ? "반영했습니다: " + items.joined(separator: ", ") + "." : "Done, sir: " + list(items) + "."
        }
        let missing = o.unhandled.filter { edit.features.contains($0) }
        if !missing.isEmpty {
            text += ko ? " 다만 " + missing.map(koreanName).joined(separator: ", ") + "은(는) 추가할 부품이 없습니다."
                       : " I couldn't add the " + list(missing) + "; I have no part for it without Apple Intelligence."
        }
        return text
    }

    // MARK: Korean

    static func korean(_ o: DesignStudio.Outcome) -> String {
        if o.source == .placeholder {
            return "아직 그 물체의 설계도가 없어 임시 조형물을 배치했습니다. Apple Intelligence를 켜시면 부품 단위로 설계해 드리겠습니다."
        }
        let b = o.brief
        var details: [String] = []
        var described = Set<String>()
        for (component, n) in b.counts.sorted(by: { $0.key < $1.key }) {
            let color = b.colors[component].map { koreanColor($0) + " " } ?? ""
            details.append(component == "floor" ? "\(n)층" : "\(color)\(koreanName(component)) \(n)개")
            described.insert(component)
        }
        for (component, c) in b.colors.sorted(by: { $0.key < $1.key }) where !described.contains(component) && component != "main" && component != "accent" {
            details.append("\(koreanColor(c)) \(koreanName(component))")
            described.insert(component)
        }
        for feature in b.features where !described.contains(feature) && !DesignLibrary.generic.contains(feature) && !o.unhandled.contains(feature) {
            details.append(koreanName(feature))
        }
        let name = koreanSubject(b) ?? o.spec.name
        var head = ""
        if let main = b.colors["main"] { head += koreanColor(main) + " " }
        head += name
        var text = "\(head)\(Hangul.objectParticle(for: name)) 설계했습니다."
        if !details.isEmpty { text += " " + details.joined(separator: ", ") + "\(details.count == 1 ? "을(를)" : "") 반영해" }
        text += details.isEmpty ? " 총 \(o.spec.parts.count)개 부품입니다." : " 총 \(o.spec.parts.count)개 부품으로 만들었습니다."
        if !o.unhandled.isEmpty {
            text += " 다만 " + o.unhandled.map(koreanName).joined(separator: ", ") + "\(Hangul.objectParticle(for: koreanName(o.unhandled.last ?? ""))) 추가할 부품이 없어 넣지 못했습니다."
        }
        return text
    }

    static func koreanName(_ component: String) -> String {
        if component == "floor" { return "층" }
        let words = DesignVocabulary.components.first { $0.key == component }?.words ?? []
        return words.first { DesignVocabulary.containsHangul($0) } ?? component
    }

    static func koreanColor(_ key: String) -> String {
        let names: [String: String] = [
            "red": "빨간", "orange": "주황색", "yellow": "노란", "lime": "연두색", "green": "초록색", "darkgreen": "짙은 초록색", "teal": "청록색",
            "cyan": "하늘색", "blue": "파란", "navy": "남색", "purple": "보라색", "pink": "분홍색", "maroon": "자주색", "white": "하얀",
            "beige": "베이지색", "brown": "갈색", "gold": "금색", "silver": "은색", "gray": "회색", "darkgray": "짙은 회색", "black": "검은",
        ]
        return names[key] ?? key
    }

    static func koreanSubject(_ b: DesignBrief) -> String? {
        let variants: [String: String] = [
            "sports": "스포츠카", "truck": "트럭", "bus": "버스", "van": "밴", "suv": "SUV", "police": "경찰차", "taxi": "택시",
            "pine": "소나무", "palm": "야자수", "cherry": "벚나무", "cottage": "오두막", "mansion": "저택", "skyscraper": "고층 빌딩",
            "sail": "범선", "speed": "모터보트", "fighter": "전투기", "airliner": "여객기", "ufo": "비행접시", "lighthouse": "등대",
            "clock": "시계탑", "sunflower": "해바라기", "tulip": "튤립", "rose": "장미", "stool": "스툴", "throne": "왕좌",
            "office": "사무용 의자", "floor": "플로어 스탠드", "laptop": "노트북", "cute": "귀여운 로봇", "spider": "거미 로봇", "katana": "카타나",
        ]
        if let v = b.variant, let name = variants[v] { return name }
        guard let s = b.subject else { return nil }
        let words = DesignVocabulary.subjects.first { $0.key == s }?.words ?? []
        let floors = b.counts["floor"].map { $0 > 1 ? "\($0)층 " : "" } ?? ""
        return floors + (words.first { DesignVocabulary.containsHangul($0) } ?? s)
    }
}

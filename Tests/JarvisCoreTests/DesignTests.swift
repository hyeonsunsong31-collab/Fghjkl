import XCTest
@testable import JarvisCore

final class DesignBriefTests: XCTestCase {
    func testEnglishDetails() {
        let b = DesignBrief.parse("make a red sports car with six black wheels and a spoiler")
        XCTAssertEqual(b.subject, "car")
        XCTAssertEqual(b.variant, "sports")
        XCTAssertEqual(b.colors["main"], "red")
        XCTAssertEqual(b.colors["wheel"], "black")
        XCTAssertEqual(b.counts["wheel"], 6)
        XCTAssertTrue(b.wants("spoiler"))
        XCTAssertTrue(b.wants("wheel"))
        XCTAssertFalse(b.korean)
    }

    func testKoreanDetails() {
        let b = DesignBrief.parse("검은 바퀴가 6개인 빨간 스포츠카 만들어줘")
        XCTAssertEqual(b.subject, "car")
        XCTAssertEqual(b.variant, "sports")
        XCTAssertEqual(b.colors["wheel"], "black")
        XCTAssertEqual(b.colors["main"], "red")
        XCTAssertEqual(b.counts["wheel"], 6)
        XCTAssertTrue(b.korean)
    }

    func testKoreanPredicateColours() {
        let b = DesignBrief.parse("바퀴는 검은색이고 차체는 빨간색인 자동차")
        XCTAssertEqual(b.colors["wheel"], "black")
        XCTAssertEqual(b.colors["body"], "red")
        let eyes = DesignBrief.parse("눈이 빨간 로봇 만들어줘")
        XCTAssertEqual(eyes.subject, "robot")
        XCTAssertEqual(eyes.colors["eye"], "red")
        XCTAssertNil(eyes.colors["main"])
    }

    func testHouseFloorsRoofAndChimney() {
        let b = DesignBrief.parse("design a two story house with a blue roof and a chimney")
        XCTAssertEqual(b.subject, "house")
        XCTAssertEqual(b.counts["floor"], 2)
        XCTAssertEqual(b.colors["roof"], "blue")
        XCTAssertTrue(b.wants("chimney"))
        XCTAssertFalse(b.features.contains("floor"))
        XCTAssertEqual(DesignBrief.parse("이층집 만들어줘").counts["floor"], 2)
        XCTAssertEqual(DesignBrief.parse("3층짜리 건물 만들어").counts["floor"], 3)
        XCTAssertEqual(DesignBrief.parse("파란 지붕 2층 집").colors["roof"], "blue")
    }

    func testCountsInKoreanForms() {
        XCTAssertEqual(DesignBrief.parse("다리가 세 개인 의자").counts["leg"], 3)
        XCTAssertEqual(DesignBrief.parse("팔이 4개인 로봇").counts["arm"], 4)
        XCTAssertEqual(DesignBrief.parse("탑 6개가 있는 성").counts["tower"], 6)
        XCTAssertEqual(DesignBrief.parse("a table with three legs").counts["leg"], 3)
        XCTAssertEqual(DesignBrief.parse("a robot with a pair of wings").counts["wing"], 2)
    }

    func testExclusionsMaterialsSizesStyles() {
        let b = DesignBrief.parse("a futuristic wooden table without drawers, 1.2 m long")
        XCTAssertEqual(b.subject, "table")
        XCTAssertEqual(b.materials["main"], "wood")
        XCTAssertTrue(b.excluded.contains("drawer"))
        XCTAssertEqual(b.length ?? 0, 1.2, accuracy: 0.001)
        XCTAssertTrue(b.hasStyle("futuristic"))
        let k = DesignBrief.parse("지붕 없는 집")
        XCTAssertTrue(k.excludes("roof"))
        XCTAssertFalse(k.wants("roof"))
        let tall = DesignBrief.parse("a 2 meter tall robot with gold eyes")
        XCTAssertEqual(tall.height ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(tall.colors["eye"], "gold")
        XCTAssertEqual(tall.materials["eye"], "metal")
        XCTAssertEqual(DesignBrief.parse("높이 50cm 로봇").height ?? 0, 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(DesignBrief.parse("a giant castle").sizeFactor, 1.5)
        XCTAssertLessThan(DesignBrief.parse("작은 집").sizeFactor, 1)
        XCTAssertEqual(DesignBrief.parse("a car with big wheels").scales["wheel"] ?? 1, 1.5, accuracy: 0.01)
    }

    func testSubjectChoiceAndAmbiguousKoreanWords() {
        XCTAssertEqual(DesignBrief.parse("a house with a car in front").subject, "house")
        XCTAssertEqual(DesignBrief.parse("자동차가 있는 집 만들어줘").subject, "house")
        let chair = DesignBrief.parse("나무 의자 만들어줘")
        XCTAssertEqual(chair.subject, "chair")
        XCTAssertEqual(chair.materials["main"], "wood")
        XCTAssertEqual(DesignBrief.parse("검은 칼 만들어줘").subject, "sword")
        XCTAssertNil(DesignBrief.parse("검은 고양이 만들어줘").subject)
        XCTAssertEqual(DesignBrief.parse("눈사람 만들어줘").subject, "snowman")
        XCTAssertEqual(DesignBrief.parse("make a pine tree").variant, "pine")
        XCTAssertEqual(DesignBrief.parse("make a dragon").subject, nil)
    }

    func testRefinementEdits() {
        let base = DesignBrief.parse("make a red car")
        let edit = DesignBrief.parse("make the wheels gold and bigger, and add a spoiler")
        let r = base.refined(by: edit)
        XCTAssertEqual(r.subject, "car")
        XCTAssertEqual(r.colors["main"], "red")
        XCTAssertEqual(r.colors["wheel"], "gold")
        XCTAssertGreaterThan(r.scales["wheel"] ?? 1, 1.2)
        XCTAssertTrue(r.wants("spoiler"))
        let removed = r.refined(by: DesignBrief.parse("remove the spoiler"))
        XCTAssertFalse(removed.wants("spoiler"))
        XCTAssertTrue(removed.excludes("spoiler"))
        let korean = base.refined(by: DesignBrief.parse("바퀴를 더 크게 하고 굴뚝 추가해"))
        XCTAssertGreaterThan(korean.scales["wheel"] ?? 1, 1.2)
        let codec = try? JSONDecoder().decode(DesignBrief.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(codec, r)
    }
}

final class DesignLibraryTests: XCTestCase {
    /// Every subject builds a clean, grounded, connected model from a plain request.
    func testEverySubjectBuildsAWellFormedModel() {
        for subject in DesignLibrary.subjects {
            let word = DesignVocabulary.subjects.first { $0.key == subject }!.words.first!
            let brief = DesignBrief.parse("make a \(word)")
            XCTAssertEqual(brief.subject, subject, word)
            guard let result = DesignLibrary.design(brief) else { XCTFail(subject); continue }
            let spec = DesignValidator.finish(result.spec, brief: brief, fromLanguageModel: false)
            XCTAssertGreaterThanOrEqual(spec.parts.count, 3, subject)
            XCTAssertLessThanOrEqual(spec.parts.count, 96, subject)
            XCTAssertTrue(spec.parts.allSatisfy { ModelSpec.supportedShapes.contains($0.shape) }, subject)
            XCTAssertTrue(spec.parts.allSatisfy { ModelSpec.materials.contains($0.material) }, subject)
            XCTAssertEqual(spec.bounds.min.y, 0, accuracy: 0.0005, subject)
            let e = spec.extent
            XCTAssertGreaterThan(max(e.x, e.y, e.z), 0.25, subject)
            XCTAssertLessThan(max(e.x, e.y, e.z), 2.2, subject)
            // Nothing floats: snapping must leave the model unchanged.
            let snapped = DesignValidator.connected(spec)
            let moved = zip(snapped.parts, spec.parts).filter { simdLength($0.0.position - $0.1.position) > 0.02 }.map { $0.1.name }
            XCTAssertTrue(moved.isEmpty, "\(subject): floating \(moved)")
            XCTAssertFalse(spec.name.isEmpty, subject)
        }
    }

    /// Every sample request (variants, colours, counts, extras) gives a grounded model with nothing floating.
    func testSampleRequestsAreConnectedAndGrounded() {
        for request in DesignPreviewExport.requests {
            let brief = DesignBrief.parse(request)
            guard let result = DesignLibrary.design(brief) else { XCTFail(request); continue }
            let spec = DesignValidator.finish(result.spec, brief: brief, fromLanguageModel: false)
            XCTAssertEqual(spec.bounds.min.y, 0, accuracy: 0.0005, request)
            let snapped = DesignValidator.connected(spec)
            let moved = zip(snapped.parts, spec.parts).filter { simdLength($0.0.position - $0.1.position) > 0.02 }.map { $0.1.name }
            XCTAssertTrue(moved.isEmpty, "\(request): floating \(moved)")
            XCTAssertTrue(result.unhandled.isEmpty, "\(request): unhandled \(result.unhandled)")
        }
    }

    func testCarHonoursColoursCountsAndExtras() {
        let brief = DesignBrief.parse("a red sports car with six gold wheels, racing stripes and a spoiler")
        let result = DesignLibrary.design(brief)!
        let spec = result.spec
        XCTAssertEqual(DesignValidator.countParts(spec, "wheel"), 6)
        XCTAssertTrue(spec.parts.filter { $0.name == "wheel rim" }.allSatisfy { $0.color == "gold" })
        XCTAssertEqual(spec.parts.first { $0.name == "body" }?.color, "red")
        XCTAssertFalse(spec.parts(of: "spoiler").isEmpty)
        XCTAssertFalse(spec.parts(of: "stripe").isEmpty)
        XCTAssertTrue(result.unhandled.isEmpty, "\(result.unhandled)")
        // Wheels stand upright (axle along x): taller than they are wide.
        let tyre = spec.parts.first { $0.name == "wheel" }!.bounds
        XCTAssertGreaterThan(tyre.max.y - tyre.min.y, (tyre.max.x - tyre.min.x) * 2)
    }

    func testHouseFloorsRoofColourChimneyAndExclusion() {
        let two = DesignLibrary.design(DesignBrief.parse("a two story house with a blue roof and a chimney"))!.spec
        XCTAssertTrue(two.parts(of: "roof").allSatisfy { $0.color == "blue" })
        XCTAssertFalse(two.parts(of: "chimney").isEmpty)
        let one = DesignLibrary.design(DesignBrief.parse("a house"))!.spec
        XCTAssertGreaterThan(two.extent.y, one.extent.y + 0.2)
        let roofless = DesignLibrary.design(DesignBrief.parse("지붕 없는 집"))!.spec
        XCTAssertTrue(roofless.parts(of: "roof").isEmpty)
    }

    func testCountsDriveRepeatedParts() {
        XCTAssertEqual(DesignValidator.countParts(DesignLibrary.design(DesignBrief.parse("a castle with 6 towers"))!.spec, "tower"), 6)
        XCTAssertEqual(DesignValidator.countParts(DesignLibrary.design(DesignBrief.parse("a table with 3 legs"))!.spec, "leg"), 3)
        XCTAssertEqual(DesignValidator.countParts(DesignLibrary.design(DesignBrief.parse("a robot with four arms"))!.spec, "arm") / 2, 4)
        XCTAssertEqual(DesignValidator.countParts(DesignLibrary.design(DesignBrief.parse("a drone with 6 propellers"))!.spec, "propeller"), 6)
        XCTAssertEqual(DesignValidator.countParts(DesignLibrary.design(DesignBrief.parse("a rocket with 3 fins"))!.spec, "fin"), 3)
        XCTAssertEqual(DesignValidator.countParts(DesignLibrary.design(DesignBrief.parse("꽃잎이 12개인 꽃"))!.spec, "petal"), 12)
    }

    func testColoursForPartsTheBuilderDoesNotStyle() {
        let spec = DesignLibrary.design(DesignBrief.parse("a robot with red arms and gold hands"))!.spec
        XCTAssertTrue(spec.parts(of: "arm").allSatisfy { $0.color == "red" })
        XCTAssertTrue(spec.parts(of: "hand").allSatisfy { $0.color == "gold" })
        XCTAssertEqual(DesignLibrary.design(DesignBrief.parse("a table"))!.counts["leg"], 4)
    }

    func testUnsupportedFeatureIsReported() {
        let result = DesignLibrary.design(DesignBrief.parse("a car with a cannon"))!
        XCTAssertEqual(result.unhandled, ["cannon"])
    }

    func testRequestedSizeIsExact() {
        let brief = DesignBrief.parse("a 2 meter tall robot")
        let spec = DesignValidator.finish(DesignLibrary.design(brief)!.spec, brief: brief, fromLanguageModel: false)
        XCTAssertEqual(spec.extent.y, 2, accuracy: 0.01)
        let long = DesignBrief.parse("a car 4 m long")
        XCTAssertEqual(DesignValidator.finish(DesignLibrary.design(long)!.spec, brief: long, fromLanguageModel: false).extent.z, 4, accuracy: 0.02)
    }
}

final class DesignValidatorTests: XCTestCase {
    func testFloatingPartsAreSnappedOn() {
        let spec = ModelSpec(name: "x", parts: [
            ModelSpec.Part(name: "body", shape: "cube", position: SIMD3(0, 0.5, 0), size: SIMD3(1, 1, 1), color: "red"),
            ModelSpec.Part(name: "antenna", shape: "cylinder", position: SIMD3(0, 1.8, 0), size: SIMD3(0.05, 0.4, 0.05), color: "gray"),
        ])
        let fixed = DesignValidator.connected(spec)
        let antenna = fixed.parts[1].bounds
        XCTAssertLessThanOrEqual(antenna.min.y, 1.0 + 0.001)
        XCTAssertGreaterThan(antenna.max.y, 1.0)
        XCTAssertEqual(fixed.parts[0].position, spec.parts[0].position)
    }

    func testComplianceListsWhatIsMissing() {
        let brief = DesignBrief.parse("a dragon with two wings and a red tail")
        let spec = ModelSpec(name: "Dragon", parts: [
            ModelSpec.Part(name: "body", shape: "capsule", position: SIMD3(0, 0.3, 0), size: SIMD3(0.3, 0.6, 0.3), color: "green"),
            ModelSpec.Part(name: "wing", shape: "wedge", position: SIMD3(0.3, 0.4, 0), size: SIMD3(0.02, 0.3, 0.4), color: "green"),
            ModelSpec.Part(name: "head", shape: "sphere", position: SIMD3(0, 0.7, 0.2), size: SIMD3(0.2, 0.2, 0.2), color: "green"),
        ])
        let issues = DesignValidator.compliance(spec, brief: brief)
        XCTAssertTrue(issues.contains { $0.contains("missing tail") }, "\(issues)")
        XCTAssertTrue(issues.contains { $0.contains("2 wing") }, "\(issues)")
        let finished = DesignValidator.finish(spec, brief: brief, fromLanguageModel: true)
        XCTAssertEqual(finished.bounds.min.y, 0, accuracy: 0.0005)
    }

    func testRotationMatchesRendererOrder() {
        // qY · qX · qZ: z first, then x, then y.
        let r = EulerRotation(degrees: SIMD3(90, 90, 0))
        let v = r.apply(SIMD3(0, 1, 0))
        // x 90 sends +y to +z, then y 90 sends +z to +x.
        XCTAssertEqual(v.x, 1, accuracy: 1e-5)
        XCTAssertEqual(v.y, 0, accuracy: 1e-5)
        XCTAssertEqual(v.z, 0, accuracy: 1e-5)
        let wheel = ModelSpec.Part(name: "wheel", shape: "cylinder", position: .zero, size: SIMD3(0.24, 0.07, 0.24), rotation: SIMD3(0, 0, 90), color: "black")
        let b = wheel.bounds
        XCTAssertEqual(b.max.x - b.min.x, 0.07, accuracy: 1e-4)
        XCTAssertEqual(b.max.y - b.min.y, 0.24, accuracy: 1e-4)
    }

    func testMirrorAndRadialExpansion() {
        let part = ModelSpec.Part(name: "leg", shape: "cube", position: SIMD3(0.2, 0.1, 0.1), size: SIMD3(0.04, 0.2, 0.04), color: "brown")
        XCTAssertEqual(part.expanded(mirror: true, radial: 1).count, 2)
        let legs = part.expanded(mirror: false, radial: 4)
        XCTAssertEqual(legs.count, 4)
        XCTAssertEqual(legs[2].position.x, -0.2, accuracy: 1e-4)
        XCTAssertEqual(legs[2].position.z, -0.1, accuracy: 1e-4)
    }
}

final class DesignStudioTests: XCTestCase {
    func testLibraryDesignAndReport() async {
        let brief = DesignBrief.parse("make a red sports car with black wheels and a spoiler")
        let outcome = await DesignStudio.design(brief, designer: nil)
        XCTAssertEqual(outcome.source, .library)
        XCTAssertTrue(outcome.unhandled.isEmpty)
        let text = DesignReport.text(outcome)
        XCTAssertTrue(text.contains("sports car"), text)
        XCTAssertTrue(text.contains("red"), text)
        XCTAssertTrue(text.contains("black wheel"), text)
        XCTAssertTrue(text.contains("spoiler"), text)
        let korean = await DesignStudio.design(DesignBrief.parse("검은 바퀴가 6개인 빨간 스포츠카 만들어줘"), designer: nil)
        let ko = DesignReport.text(korean)
        XCTAssertTrue(ko.contains("스포츠카"), ko)
        XCTAssertTrue(ko.contains("검은 바퀴 6개"), ko)
    }

    func testLanguageModelAddsWhatTheLibraryCannot() async {
        let brief = DesignBrief.parse("a car with a cannon on the roof")
        var prompts: [DesignPrompt] = []
        let outcome = await DesignStudio.design(brief) { prompt in
            prompts.append(prompt)
            return ModelSpec(name: "extra", parts: [
                ModelSpec.Part(name: "cannon", shape: "cylinder", position: SIMD3(0, 1.5, 0), size: SIMD3(0.05, 0.3, 0.05), rotation: SIMD3(90, 0, 0), color: "darkgray", material: "metal"),
            ])
        }
        XCTAssertEqual(prompts.count, 1)
        XCTAssertTrue(prompts[0].prompt.contains("ONLY these additional parts"), prompts[0].prompt)
        XCTAssertTrue(prompts[0].prompt.contains(": cannon."), prompts[0].prompt)
        XCTAssertEqual(outcome.source, .combined)
        XCTAssertTrue(outcome.unhandled.isEmpty)
        let cannon = outcome.spec.parts.first { $0.name == "cannon" }!
        let others = ModelSpec(name: "", parts: outcome.spec.parts.filter { $0.name != "cannon" })
        XCTAssertLessThan(DesignValidator.gap(cannon.bounds, others.bounds), 0.02)
    }

    func testUnknownObjectUsesLanguageModelWithFeedback() async {
        let brief = DesignBrief.parse("a dragon with two wings")
        var calls = 0
        let outcome = await DesignStudio.design(brief) { prompt in
            calls += 1
            XCTAssertTrue(prompt.prompt.contains("2 × wing"), prompt.prompt)
            var parts = [ModelSpec.Part(name: "body", shape: "capsule", position: SIMD3(0, 0.3, 0), size: SIMD3(0.3, 0.6, 0.3), rotation: SIMD3(90, 0, 0), color: "green"),
                         ModelSpec.Part(name: "head", shape: "sphere", position: SIMD3(0, 0.45, 0.4), size: SIMD3(0.2, 0.2, 0.2), color: "green"),
                         ModelSpec.Part(name: "tail", shape: "cone", position: SIMD3(0, 0.3, -0.45), size: SIMD3(0.1, 0.4, 0.1), rotation: SIMD3(-90, 0, 0), color: "green")]
            if calls == 1 {
                parts.append(ModelSpec.Part(name: "wing", shape: "wedge", position: SIMD3(0.3, 0.45, 0), size: SIMD3(0.02, 0.3, 0.4), color: "green"))
            } else {
                XCTAssertTrue(prompt.prompt.contains("previous design had these problems"), prompt.prompt)
                parts += ModelSpec.Part(name: "wing", shape: "wedge", position: SIMD3(0.3, 0.45, 0), size: SIMD3(0.02, 0.3, 0.4), color: "green").expanded(mirror: true, radial: 1)
            }
            return ModelSpec(name: "Dragon", parts: parts)
        }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(outcome.source, .languageModel)
        XCTAssertEqual(DesignValidator.countParts(outcome.spec, "wing"), 2)
        XCTAssertTrue(outcome.issues.isEmpty, "\(outcome.issues)")
    }

    func testRefinementReport() async {
        let base = DesignBrief.parse("make a red car")
        let edit = DesignBrief.parse("make the wheels gold and add a spoiler")
        let outcome = await DesignStudio.design(base.refined(by: edit), designer: nil)
        let text = DesignReport.changes(edit, outcome: outcome)
        XCTAssertTrue(text.contains("wheels are now gold"), text)
        XCTAssertTrue(text.contains("added a spoiler"), text)
        XCTAssertFalse(outcome.spec.parts(of: "spoiler").isEmpty)
        let ko = DesignBrief.parse("굴뚝 추가해")
        let house = await DesignStudio.design(DesignBrief.parse("집 만들어줘").refined(by: ko), designer: nil)
        XCTAssertFalse(house.spec.parts(of: "chimney").isEmpty)
        XCTAssertTrue(DesignReport.changes(ko, outcome: house).contains("굴뚝 추가"))
    }

    func testPlaceholderWithoutLanguageModel() async {
        let outcome = await DesignStudio.design(DesignBrief.parse("make a dragon"), designer: nil)
        XCTAssertEqual(outcome.source, .placeholder)
        XCTAssertTrue(DesignReport.text(outcome).contains("placeholder"))
    }
}

import XCTest
@testable import JarvisCore

final class SceneTests: XCTestCase {
    func testCreateCloneResolveDelete() throws {
        var doc = SceneDocument()
        let cube = doc.add(shape: "cube", color: "red", size: MeshGenerator.defaultSize(for: "cube"))
        _ = doc.add(shape: "sphere", color: "blue", size: MeshGenerator.defaultSize(for: "sphere"))
        XCTAssertEqual(doc.resolve(["targetShape": "cube"]), [cube.id])
        XCTAssertEqual(doc.resolve(["target": "current"]), [doc.objects[1].id], "'it' = current selection")
        let clones = doc.clone([cube.id], count: 2)
        XCTAssertEqual(clones.count, 2)
        XCTAssertNotEqual(clones[0].position, clones[1].position)
        assertNoOverlap(doc)
        XCTAssertEqual(doc.resolve(["targetShape": "cube", "scope": "all"]).count, 3)
        XCTAssertEqual(doc.resolve(["targetShape": "cube", "ordinal": "1"]), [cube.id])
        XCTAssertEqual(doc.resolve(["ordinal": "last"]), [clones[1].id])
        doc.delete([cube.id])
        XCTAssertEqual(doc.objects.count, 3)
        let data = try JSONEncoder().encode(doc)
        XCTAssertEqual(try JSONDecoder().decode(SceneDocument.self, from: data), doc)
    }

    /// The CI scenario ("three red cubes", "clone it twice", "파란 구") plus a mixed scene:
    /// nothing may intersect on the floor, and clones stay next to their original.
    func testPlacementNeverOverlaps() {
        var doc = SceneDocument()
        let cube = MeshGenerator.defaultSize(for: "cube")
        for _ in 0..<3 { doc.add(shape: "cube", color: "red", size: cube) }
        let last = doc.objects[2]
        let clones = doc.clone([last.id], count: 2)
        XCTAssertEqual(clones.count, 2)
        let firstGap = floorDistance(clones[0], last)
        XCTAssertLessThan(firstGap, last.footprint * 2.5, "a clone is placed right beside its original")
        doc.add(shape: "sphere", color: "blue", size: MeshGenerator.defaultSize(for: "sphere"))
        assertNoOverlap(doc)

        for shape in ["torus", "plane", "cylinder", "cube", "cone", "capsule", "pyramid", "sphere"] {
            doc.add(shape: shape, color: "cyan", size: MeshGenerator.defaultSize(for: shape) * 1.5)
        }
        doc.addComposite(ModelSpec.template(for: "robot"))
        _ = doc.clone([doc.objects[0].id, doc.objects[5].id], count: 3)
        XCTAssertEqual(doc.objects.count, 21)
        assertNoOverlap(doc)
    }

    private func floorDistance(_ a: SceneObject, _ b: SceneObject) -> Float {
        let dx = a.position.x - b.position.x, dz = a.position.z - b.position.z
        return (dx * dx + dz * dz).squareRoot()
    }

    private func assertNoOverlap(_ doc: SceneDocument, file: StaticString = #filePath, line: UInt = #line) {
        let objs = doc.objects
        for i in 0..<objs.count {
            for j in (i + 1)..<objs.count {
                let a = objs[i], b = objs[j]
                let d = floorDistance(a, b)
                XCTAssertGreaterThanOrEqual(d + 1e-4, a.clearance + b.clearance,
                                            "\(a.shape)#\(i) overlaps \(b.shape)#\(j)", file: file, line: line)
            }
        }
    }

    func testTemplatesAndComposite() {
        for name in ["iron helmet", "로봇", "car", "house", "tree", "rocket", "snowman", "table", "chair", "arc reactor", "mystery object"] {
            let spec = ModelSpec.template(for: name).sanitized()
            XCTAssertGreaterThanOrEqual(spec.parts.count, 4, name)
            XCTAssertTrue(spec.parts.allSatisfy { ModelSpec.supportedShapes.contains($0.shape) }, name)
        }
        var doc = SceneDocument()
        let group = doc.addComposite(ModelSpec.template(for: "robot"))
        XCTAssertTrue(group.isComposite)
        XCTAssertGreaterThan(group.size.y, 0.8)
        XCTAssertTrue(doc.summary().contains("Robot"))
    }
}

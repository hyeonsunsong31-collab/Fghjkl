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
        XCTAssertGreaterThan(clones[1].position.x, clones[0].position.x)
        XCTAssertEqual(doc.resolve(["targetShape": "cube", "scope": "all"]).count, 3)
        XCTAssertEqual(doc.resolve(["targetShape": "cube", "ordinal": "1"]), [cube.id])
        XCTAssertEqual(doc.resolve(["ordinal": "last"]), [clones[1].id])
        doc.delete([cube.id])
        XCTAssertEqual(doc.objects.count, 3)
        let data = try JSONEncoder().encode(doc)
        XCTAssertEqual(try JSONDecoder().decode(SceneDocument.self, from: data), doc)
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

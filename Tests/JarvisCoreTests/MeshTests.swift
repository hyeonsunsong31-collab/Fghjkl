import XCTest
@testable import JarvisCore

final class MeshTests: XCTestCase {
    /// Every triangle must wind counter-clockwise when seen from outside
    /// (geometric normal agrees with the vertex normals) so back-face culling never hides a face.
    func testAllPrimitivesWindOutwardAndAreWellFormed() {
        for shape in ["cube", "sphere", "cylinder", "cone", "torus", "capsule", "pyramid", "plane"] {
            let m = MeshGenerator.mesh(for: shape, size: MeshGenerator.defaultSize(for: shape), segments: 24)
            XCTAssertEqual(m.positions.count, m.normals.count, shape)
            XCTAssertEqual(m.positions.count, m.uvs.count, shape)
            XCTAssertEqual(m.indices.count % 3, 0, shape)
            XCTAssertTrue(m.indices.allSatisfy { Int($0) < m.positions.count }, shape)
            var bad = 0
            for t in stride(from: 0, to: m.indices.count, by: 3) {
                let ia = Int(m.indices[t]), ib = Int(m.indices[t + 1]), ic = Int(m.indices[t + 2])
                let a = m.positions[ia], b = m.positions[ib], c = m.positions[ic]
                let g = simdCross(b - a, c - a)
                if simdLength(g) < 1e-9 { continue } // degenerate (poles)
                let n = m.normals[ia] + m.normals[ib] + m.normals[ic]
                if simdDot(g, n) <= 0 { bad += 1 }
            }
            XCTAssertEqual(bad, 0, "\(shape): \(bad) inward-facing triangles")
            let (lo, hi) = m.bounds
            let size = hi - lo
            XCTAssertGreaterThan(size.x, 0.05, shape)
            XCTAssertGreaterThan(size.y, 0.003, shape)
        }
    }

    func testOBJExport() {
        let cube = MeshGenerator.box(SIMD3(1, 1, 1))
        let text = MeshGenerator.obj([("cube", cube, { $0 + SIMD3(0, 1, 0) })])
        XCTAssertTrue(text.contains("o cube"))
        XCTAssertEqual(text.components(separatedBy: "\nv ").count - 1, 24)
        XCTAssertEqual(text.components(separatedBy: "\nf ").count - 1, 12)
    }
}

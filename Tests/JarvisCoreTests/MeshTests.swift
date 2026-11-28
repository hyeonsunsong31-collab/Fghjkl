import XCTest
@testable import JarvisCore

final class MeshTests: XCTestCase {
    /// Every triangle must wind counter-clockwise when seen from outside
    /// (geometric normal agrees with the vertex normals) so back-face culling never hides a face.
    func testAllPrimitivesWindOutwardAndAreWellFormed() {
        for shape in MeshGenerator.shapes {
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

    /// Every shape fills exactly the box it is given, even with unequal width, height and depth
    /// (ellipsoids, elliptical cylinders, flattened domes…), and still winds outward.
    func testShapesFillTheirBoxAndStayOutward() {
        let size = SIMD3<Float>(0.5, 0.3, 0.2)
        for shape in MeshGenerator.shapes where shape != "plane" {
            let m = MeshGenerator.mesh(for: shape, size: size, segments: 32)
            let (lo, hi) = m.bounds
            XCTAssertEqual(hi.x - lo.x, size.x, accuracy: 0.01, shape)
            XCTAssertEqual(hi.y - lo.y, size.y, accuracy: 0.01, shape)
            XCTAssertEqual(hi.z - lo.z, size.z, accuracy: 0.01, shape)
            XCTAssertEqual((lo.y + hi.y) / 2, 0, accuracy: 0.01, shape)
            var bad = 0
            for t in stride(from: 0, to: m.indices.count, by: 3) {
                let ia = Int(m.indices[t]), ib = Int(m.indices[t + 1]), ic = Int(m.indices[t + 2])
                let g = simdCross(m.positions[ib] - m.positions[ia], m.positions[ic] - m.positions[ia])
                if simdLength(g) < 1e-10 { continue }
                if simdDot(g, m.normals[ia] + m.normals[ib] + m.normals[ic]) <= 0 { bad += 1 }
            }
            XCTAssertEqual(bad, 0, "\(shape): \(bad) inward-facing triangles")
            XCTAssertTrue(m.normals.allSatisfy { abs(simdLength($0) - 1) < 0.01 }, shape)
        }
    }

    func testShapeParameters() {
        let narrow = MeshGenerator.mesh(for: "frustum", size: SIMD3(1, 1, 1), param: 0.2)
        let topRadius = narrow.positions.filter { $0.y > 0.49 }.map { ($0.x * $0.x + $0.z * $0.z).squareRoot() }.max() ?? 0
        XCTAssertEqual(topRadius, 0.1, accuracy: 0.01)
        let octagon = MeshGenerator.mesh(for: "prism", size: SIMD3(1, 1, 1), param: 8)
        XCTAssertEqual(Set(octagon.normals.filter { abs($0.y) < 0.01 }.map { "\(Int(($0.x * 100).rounded())),\(Int(($0.z * 100).rounded()))" }).count, 8)
    }
}

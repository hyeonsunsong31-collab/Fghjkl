import XCTest
@testable import JarvisCore

/// Writes triangle soups of sample designs for offline preview rendering.
/// Runs only when JARVIS_PREVIEW_DIR is set (not part of the normal test run).
final class DesignPreviewExport: XCTestCase {
    static let requests: [String] = [
        "make a red sports car with six gold wheels and a spoiler", "a car", "a pickup truck", "a yellow school bus",
        "a police car", "a two story house with a blue roof and a chimney", "a cottage", "a modern house with a garage and a fence",
        "a skyscraper", "a castle with 6 towers and red flags", "a lighthouse", "a clock tower", "a tower",
        "a pine tree", "an apple tree with fruit", "a palm tree", "a christmas tree", "a sunflower", "a red rose", "a tulip",
        "a robot with red eyes and an antenna", "a cute robot", "a spider robot", "a futuristic helmet with a gold visor and two horns",
        "a rocket with 3 fins and a flame", "a spaceship", "a ufo", "an airplane", "a fighter jet", "a helicopter", "a drone with 6 propellers",
        "a sailboat", "a speedboat", "a ship", "a wooden table with 4 legs", "a round glass table", "a desk", "a chair", "an office chair",
        "a throne", "a stool", "a gray sofa", "a bed with a red blanket", "a desk lamp", "a floor lamp", "a table lamp", "a mug", "a bottle",
        "a snowman", "a sword", "a katana", "a shield", "a crown", "a computer", "a laptop", "a windmill", "a wind turbine", "an arc reactor", "a bridge",
    ]

    func testExportPreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["JARVIS_PREVIEW_DIR"] else { throw XCTSkip("set JARVIS_PREVIEW_DIR to export previews") }
        let palette: [String: SIMD3<Float>] = [
            "red": SIMD3(1, 0.24, 0.27), "orange": SIMD3(1, 0.56, 0.16), "yellow": SIMD3(1, 0.88, 0.25), "lime": SIMD3(0.65, 0.95, 0.2),
            "green": SIMD3(0.25, 0.8, 0.4), "darkgreen": SIMD3(0.12, 0.45, 0.22), "teal": SIMD3(0.1, 0.6, 0.6), "cyan": SIMD3(0, 0.9, 1),
            "blue": SIMD3(0.2, 0.48, 1), "navy": SIMD3(0.1, 0.16, 0.42), "purple": SIMD3(0.66, 0.38, 1), "pink": SIMD3(1, 0.5, 0.75),
            "maroon": SIMD3(0.5, 0.1, 0.15), "white": SIMD3(0.95, 0.95, 0.95), "beige": SIMD3(0.9, 0.83, 0.68), "brown": SIMD3(0.5, 0.32, 0.18),
            "gold": SIMD3(1, 0.78, 0.3), "silver": SIMD3(0.78, 0.8, 0.84), "gray": SIMD3(0.55, 0.56, 0.58), "darkgray": SIMD3(0.28, 0.29, 0.31),
            "black": SIMD3(0.1, 0.1, 0.11),
        ]
        for (index, request) in Self.requests.enumerated() {
            let brief = DesignBrief.parse(request)
            guard let lib = DesignLibrary.design(brief) else { continue }
            let spec = DesignValidator.finish(lib.spec, brief: brief, fromLanguageModel: false)
            var data = Data()
            var count: Int32 = 0
            var body = Data()
            let yaw = EulerRotation(degrees: SIMD3(0, -32, 0))
            for part in spec.parts {
                let mesh = MeshGenerator.mesh(for: part.shape, size: part.size, param: part.param, segments: 32)
                let r = EulerRotation(degrees: part.rotation)
                let color = palette[part.color] ?? SIMD3(0.8, 0.2, 0.8)
                let flag: Float = part.material == "emissive" ? 2 : (part.material == "glass" ? 1 : (part.material == "chrome" || part.material == "metal" ? 3 : 0))
                for t in stride(from: 0, to: mesh.indices.count, by: 3) {
                    var floats: [Float] = []
                    for k in 0..<3 {
                        let p = yaw.apply(r.apply(mesh.positions[Int(mesh.indices[t + k])]) + part.position)
                        floats += [p.x, p.y, p.z]
                    }
                    floats += [color.x, color.y, color.z, flag]
                    floats.withUnsafeBufferPointer { body.append(Data(buffer: $0)) }
                    count += 1
                }
            }
            withUnsafeBytes(of: count) { data.append(contentsOf: $0) }
            data.append(body)
            let name = String(format: "%02d", index) + "_" + request.replacingOccurrences(of: " ", with: "_").prefix(40)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".tri"))
            let label = "\(spec.name) · \(spec.parts.count) parts"
            try label.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        }
    }
}

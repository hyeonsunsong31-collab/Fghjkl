// swift-tools-version: 5.9
//
// Developer package (NOT the app). It compiles the platform-independent core of
// Jarvis (neural core, command grammar, language heuristics, gesture math,
// G2P front-end, LLM runtime core) on Linux/macOS so it can be unit-tested
// with `swift test`. The app itself is `Jarvis.swiftpm` (open it in Swift Playgrounds).

import PackageDescription

let package = Package(
    name: "JarvisDevKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "JarvisCore", targets: ["JarvisCore"])
    ],
    targets: [
        .target(
            name: "JarvisCore",
            path: "Jarvis.swiftpm/Sources/Core"
        ),
        .testTarget(
            name: "JarvisCoreTests",
            dependencies: ["JarvisCore"],
            path: "Tests/JarvisCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)

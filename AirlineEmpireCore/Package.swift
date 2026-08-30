// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirlineEmpireCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AirlineEmpireCore", targets: ["AirlineEmpireCore"]),
        .executable(name: "ae-bench", targets: ["AEBench"]),
        .executable(name: "ae-map-bench", targets: ["AEMapBench"]),
        // Regenerates docs/AUDIO_ASSET_MANIFEST.md §3 from AudioCue itself, so the
        // documented mix cannot drift from the one the game uses.
        .executable(name: "ae-audio-manifest", targets: ["AEAudioManifest"]),
    ],
    targets: [
        // Swift 6 language mode: strict concurrency is on by default.
        .target(
            name: "AirlineEmpireCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AirlineEmpireCoreTests",
            dependencies: ["AirlineEmpireCore"]
        ),
        .executableTarget(
            name: "AEBench",
            dependencies: ["AirlineEmpireCore"]
        ),
        // The map model is rebuilt once per simulation tick, so its cost sits
        // directly in the renderer's frame budget (docs/MAP_ARCHITECTURE.md
        // §11). Measured rather than assumed.
        .executableTarget(
            name: "AEMapBench",
            dependencies: ["AirlineEmpireCore"]
        ),
        .executableTarget(
            name: "AEAudioManifest",
            dependencies: ["AirlineEmpireCore"]
        ),
    ]
)

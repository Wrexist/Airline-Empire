// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirlineEmpireCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AirlineEmpireCore", targets: ["AirlineEmpireCore"]),
        .executable(name: "ae-bench", targets: ["AEBench"]),
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
    ]
)

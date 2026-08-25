// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirlineEmpireCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AirlineEmpireCore", targets: ["AirlineEmpireCore"])
    ],
    targets: [
        // Swift 6 language mode: strict concurrency is on by default.
        .target(name: "AirlineEmpireCore"),
        .testTarget(
            name: "AirlineEmpireCoreTests",
            dependencies: ["AirlineEmpireCore"]
        ),
    ]
)

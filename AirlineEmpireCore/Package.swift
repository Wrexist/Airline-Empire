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
        // Diffs every rival's state day by day and prints what the
        // competition did, what it cost the player, and whether the player
        // could see it (docs/RIVAL_PRESSURE_AUDIT.md).
        .executable(name: "ae-rival-probe", targets: ["AERivalProbe"]),
        // Headless seed scan: many campaigns, every rival move on the
        // player's network classified by who started the contest
        // (docs/RIVALS_THAT_COME_TO_YOU_AUDIT.md).
        .executable(name: "ae-rival-scan", targets: ["AERivalScan"]),
        // Flies single routes through the real pipeline and reads the
        // ledger back: the fee, fuel, crew, maintenance and service each
        // route actually paid, against what the AI's estimator would have
        // said (docs/FEE_ECONOMY_BASELINE.md).
        .executable(name: "ae-fee-baseline", targets: ["AEFeeBaseline"]),
        // Reads the game's own advice — `marketOpportunities`, narrowed the
        // way Home narrows it — and asks what following it is worth: the
        // economics of each recommendation, and a campaign that does what it
        // says (docs/AE042_NEXT_MOVES_BASELINE.md).
        .executable(name: "ae-advice", targets: ["AEAdvice"]),
        // AE-044's controlled demand battery: holds a market, a fare and a
        // day fixed, varies exactly one of seats / frequency / incumbents,
        // flies it through the real pipeline and prints the estimator's
        // forecast beside the ledger (docs/AE044_AIRFRAME_VALUE_AUDIT.md).
        .executable(name: "ae-demand", targets: ["AEDemand"]),
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
        .executableTarget(
            name: "AERivalProbe",
            dependencies: ["AirlineEmpireCore"]
        ),
        .executableTarget(
            name: "AERivalScan",
            dependencies: ["AirlineEmpireCore"]
        ),
        .executableTarget(
            name: "AEFeeBaseline",
            dependencies: ["AirlineEmpireCore"]
        ),
        .executableTarget(
            name: "AEAdvice",
            dependencies: ["AirlineEmpireCore"]
        ),
        .executableTarget(
            name: "AEDemand",
            dependencies: ["AirlineEmpireCore"]
        ),
    ]
)

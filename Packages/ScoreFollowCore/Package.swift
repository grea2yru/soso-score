// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScoreFollowCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ScoreFollowCore", targets: ["ScoreFollowCore"])
    ],
    targets: [
        .target(name: "ScoreFollowCore", linkerSettings: [.linkedFramework("Accelerate")]),
        .testTarget(name: "ScoreFollowCoreTests", dependencies: ["ScoreFollowCore"]),
    ]
)

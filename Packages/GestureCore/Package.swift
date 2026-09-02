// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GestureCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "GestureCore", targets: ["GestureCore"])
    ],
    targets: [
        .target(name: "GestureCore"),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"]),
    ]
)

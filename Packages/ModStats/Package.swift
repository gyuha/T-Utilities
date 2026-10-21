// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModStats",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModStats", targets: ["ModStats"]),
    ],
    dependencies: [
        .package(path: "../TUCore"),
        .package(path: "../TUUI"),
    ],
    targets: [
        .target(name: "ModStats", dependencies: ["TUCore", "TUUI"]),
        .testTarget(name: "ModStatsTests", dependencies: ["ModStats"]),
    ]
)

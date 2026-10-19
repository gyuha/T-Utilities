// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModAwake",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModAwake", targets: ["ModAwake"]),
    ],
    dependencies: [
        .package(path: "../TUCore"),
    ],
    targets: [
        .target(name: "ModAwake", dependencies: ["TUCore"]),
        .testTarget(name: "ModAwakeTests", dependencies: ["ModAwake"]),
    ]
)

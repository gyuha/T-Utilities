// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModAwake",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModAwake", targets: ["ModAwake"]),
        // Shared with the AwakeGuard helper executable.
        .library(name: "ClamshellKit", targets: ["ClamshellKit"]),
    ],
    dependencies: [
        .package(path: "../TUCore"),
    ],
    targets: [
        .target(name: "ClamshellKit"),
        .target(name: "ModAwake", dependencies: ["TUCore", "ClamshellKit"]),
        .testTarget(name: "ModAwakeTests", dependencies: ["ModAwake"]),
    ]
)

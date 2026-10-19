// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModClock",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModClock", targets: ["ModClock"]),
    ],
    dependencies: [
        .package(path: "../TUCore"),
    ],
    targets: [
        .target(name: "ModClock", dependencies: ["TUCore"]),
        .testTarget(name: "ModClockTests", dependencies: ["ModClock"]),
    ]
)

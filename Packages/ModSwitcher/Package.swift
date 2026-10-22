// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModSwitcher",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModSwitcher", targets: ["ModSwitcher"]),
    ],
    dependencies: [
        .package(path: "../TUCore"),
        .package(path: "../TUUI"),
    ],
    targets: [
        .target(name: "ModSwitcher", dependencies: ["TUCore", "TUUI"]),
        .testTarget(name: "ModSwitcherTests", dependencies: ["ModSwitcher"]),
    ]
)

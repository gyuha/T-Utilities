// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModMouse",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModMouse", targets: ["ModMouse"]),
    ],
    dependencies: [
        .package(path: "../TUCore"),
        .package(path: "../TUUI"),
    ],
    targets: [
        .target(name: "ModMouse", dependencies: ["TUCore", "TUUI"]),
        .testTarget(name: "ModMouseTests", dependencies: ["ModMouse"]),
    ]
)

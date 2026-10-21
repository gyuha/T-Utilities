// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModWindows",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModWindows", targets: ["ModWindows"]),
    ],
    dependencies: [
        .package(path: "../TUCore"),
        .package(path: "../TUUI"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(name: "ModWindows", dependencies: ["TUCore", "TUUI", "KeyboardShortcuts"]),
        .testTarget(name: "ModWindowsTests", dependencies: ["ModWindows"]),
    ]
)

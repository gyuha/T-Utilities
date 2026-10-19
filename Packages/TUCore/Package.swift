// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TUCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TUCore", targets: ["TUCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(
            name: "TUCore",
            dependencies: ["KeyboardShortcuts"]
        ),
        .testTarget(
            name: "TUCoreTests",
            dependencies: ["TUCore"]
        ),
    ]
)

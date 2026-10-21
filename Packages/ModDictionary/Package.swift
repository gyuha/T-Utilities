// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModDictionary",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModDictionary", targets: ["ModDictionary"]),
    ],
    dependencies: [
        .package(path: "../TUCore"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(name: "ModDictionary", dependencies: ["TUCore", "KeyboardShortcuts"]),
        .testTarget(name: "ModDictionaryTests", dependencies: ["ModDictionary"]),
    ]
)

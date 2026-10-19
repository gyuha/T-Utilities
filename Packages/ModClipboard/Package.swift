// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModClipboard",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModClipboard", targets: ["ModClipboard"]),
    ],
    dependencies: [
        .package(path: "../TUCore"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(
            name: "ModClipboard",
            dependencies: ["TUCore", "KeyboardShortcuts"]
        ),
        .testTarget(
            name: "ModClipboardTests",
            dependencies: ["ModClipboard"]
        ),
    ]
)
